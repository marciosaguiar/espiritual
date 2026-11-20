// Mede quanto o app demora para abrir num celular com internet ruim, e ONDE
// o tempo vai.
//
//   node ferramentas/medir/medir_abertura.mjs <build/web carimbado> <saida.json>
//
//   PERFIL=lento|rapido|nenhum   (padrão: lento)
//   REPETICOES=5                 (padrão: 5)
//
// O QUE ISTO É, E O QUE NÃO É
//
// É o app de verdade (a mesma `main()`, o mesmo service worker, o mesmo
// Firestore com cache no aparelho), falando com o EMULADOR do Firebase, num
// Chromium com a rede e o processador de um celular segurados. NÃO é um
// iPhone: o Safari tem outro motor de JavaScript e outro WebAssembly, e a
// ordem de grandeza se mantém, mas o número não. Está dito nas conclusões.
//
// O PERFIL "lento" é o do Lighthouse para celular: 1,6 Mbps de descida, 750
// kbps de subida, 150 ms de latência, processador 4× mais lento. É aplicado
// pelo protocolo do Chrome (CDP) à página — o que é pedido pela página,
// inclusive as chamadas ao emulador, passa por ele.
//
// O QUE SE MEDE (em ms desde o início da navegação)
//
//   fcp            primeira coisa pintada: a tela de abertura em HTML puro
//   primeiraTela   o Flutter desenhou o primeiro quadro (`flutter-first-frame`)
//   inicioComDados o Início está na tela COM cultos e músicas (marca do app)
//
// e, entre elas, as marcas do `main()` (`dart-main`, `firebase-pronto`, …) e
// os pedidos de rede agrupados por tipo — que é o que mostra se o tempo foi
// baixar o pacote, o motor gráfico, as fontes ou esperar o banco.

import { createRequire } from 'node:module';
import http from 'node:http';
import zlib from 'node:zlib';
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';

const { chromium } = createRequire(import.meta.url)('playwright');

const [pastaBuild, arquivoSaida = '/tmp/medidas.json'] = process.argv.slice(2);
if (!pastaBuild) { console.error('uso: node medir_abertura.mjs <build/web> [saida.json]'); process.exit(2); }

const PERFIL = process.env.PERFIL || 'lento';
const REPETICOES = Number(process.env.REPETICOES || 5);
const PERFIS = {
  lento: { latency: 150, down: (1.6 * 1000 * 1000) / 8, up: (750 * 1000) / 8, cpu: 4 },
  rapido: { latency: 40, down: (20 * 1000 * 1000) / 8, up: (5 * 1000 * 1000) / 8, cpu: 1 },
  nenhum: null,
};
const perfil = PERFIS[PERFIL];
const ENTRAR = JSON.parse(fs.readFileSync(process.env.SEMENTE || '/tmp/semente.json', 'utf8')).entrar;

// ─── Servidor: imita o GitHub Pages (gzip, ETag, cache de 10 minutos) ────────

const TIPOS = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.json': 'application/json',
  '.wasm': 'application/wasm', '.png': 'image/png', '.css': 'text/css', '.otf': 'font/otf',
  '.ttf': 'font/ttf', '.map': 'application/json', '.ico': 'image/x-icon', '.svg': 'image/svg+xml',
};
const COMPRESSIVEL = new Set(['.html', '.js', '.json', '.wasm', '.css', '.otf', '.ttf', '.svg', '.map']);
const raiz = path.resolve(pastaBuild);
const memoria = new Map();
let pedidosAoServidor = [];

// A LINHA compartilhada. A banda é UMA só para tudo o que sai deste servidor
// — a página e o service worker disputam o mesmo 1,6 Mbps, como num celular.
// (O throttling do Chrome por CDP só alcança a página; o service worker é outro
// alvo e ficaria de fora, escondendo justamente a disputa que mais pesa na
// primeira abertura.)
class Linha {
  constructor(bytesPorSegundo, latenciaMs) {
    this.taxa = bytesPorSegundo; this.latencia = latenciaMs; this.livre = Date.now();
  }
  /// Espera a vez de mandar [n] bytes (e devolve quando já "chegaram").
  async passar(n) {
    const agora = Date.now();
    this.livre = Math.max(this.livre, agora) + (n / this.taxa) * 1000;
    const espera = this.livre - agora;
    if (espera > 0) await new Promise((ok) => setTimeout(ok, espera));
  }
  async atraso() { await new Promise((ok) => setTimeout(ok, this.latencia)); }
}
const linha = perfil ? new Linha(perfil.down, perfil.latency) : null;
const PEDACO = 16 * 1024;

async function mandar(res, corpo) {
  if (!linha) { res.end(corpo); return; }
  for (let i = 0; i < corpo.length; i += PEDACO) {
    const pedaco = corpo.subarray(i, i + PEDACO);
    await linha.passar(pedaco.length);
    if (!res.write(pedaco)) await new Promise((ok) => res.once('drain', ok));
  }
  res.end();
}

const servidor = http.createServer(async (req, res) => {
  let rel = decodeURIComponent(new URL(req.url, 'http://x').pathname);
  if (rel.endsWith('/')) rel += 'index.html';
  const arq = path.join(raiz, rel);
  if (!arq.startsWith(raiz) || !fs.existsSync(arq) || fs.statSync(arq).isDirectory()) {
    res.writeHead(404); res.end(); return;
  }
  const ext = path.extname(arq);
  if (!memoria.has(arq)) {
    const cru = fs.readFileSync(arq);
    const zip = COMPRESSIVEL.has(ext) ? zlib.gzipSync(cru, { level: 6 }) : null;
    memoria.set(arq, { cru, zip, etag: '"' + crypto.createHash('md5').update(cru).digest('hex') + '"' });
  }
  const m = memoria.get(arq);
  pedidosAoServidor.push(rel);
  if (linha) await linha.atraso();
  const cabecas = {
    'content-type': TIPOS[ext] || 'application/octet-stream',
    'cache-control': 'max-age=600', etag: m.etag,
  };
  if (req.headers['if-none-match'] === m.etag) { res.writeHead(304, cabecas); res.end(); return; }
  const aceitaGzip = /\bgzip\b/.test(req.headers['accept-encoding'] || '');
  const corpo = m.zip && aceitaGzip ? m.zip : m.cru;
  res.writeHead(200, {
    ...cabecas, 'content-length': corpo.length,
    ...(corpo === m.zip ? { 'content-encoding': 'gzip' } : {}),
  });
  await mandar(res, corpo);
});
await new Promise((ok) => servidor.listen(0, '127.0.0.1', ok));
const origem = `http://127.0.0.1:${servidor.address().port}`;

// ─── Uma abertura ───────────────────────────────────────────────────────────

async function segurar(ctx, pag) {
  // Só o PROCESSADOR é segurado pelo CDP. A rede é a `Linha` do servidor,
  // que a página e o service worker dividem.
  if (!perfil || perfil.cpu === 1) return;
  const cdp = await ctx.newCDPSession(pag);
  await cdp.send('Emulation.setCPUThrottlingRate', { rate: perfil.cpu });
}

// O que o app pede ao Google (fontes de reserva, SDK do Firebase) sai da
// internet de verdade, mas passa pela MESMA linha: 1,6 Mbps e 150 ms por
// pedido, com os 3 viagens extras da primeira conexão a cada servidor
// (DNS, TCP, TLS). Sem isto esses ~700 KB sairiam de graça.
const conectados = new Set();
const guardados = new Map();
async function desviarGoogle(ctx) {
  await ctx.route(/^https:\/\/(www|fonts)\.gstatic\.com\//, async (route) => {
    const url = route.request().url();
    const origem = new URL(url).origin;
    if (!guardados.has(url)) {
      const r = await route.fetch();
      guardados.set(url, { status: r.status(), headers: r.headers(), corpo: await r.body() });
    }
    const g = guardados.get(url);
    if (linha) {
      if (!conectados.has(origem)) { conectados.add(origem); for (let i = 0; i < 3; i++) await linha.atraso(); }
      await linha.atraso();
      await linha.passar(zlib.gzipSync(g.corpo, { level: 6 }).length);
    }
    await route.fulfill({ status: g.status, headers: g.headers, body: g.corpo });
  });
}

// O app, nesta compilação, fala com o emulador do Auth — mas o SDK confere a
// sessão guardada (`accounts:lookup`) ANTES de `useAuthEmulator` valer, e essa
// conferência vai ao endereço de verdade do Google. Com a conta do emulador
// ela volta 400, o SDK acha que a sessão é inválida e desloga: a "segunda
// abertura" cairia na tela de entrar. Aqui esses dois endereços do Google são
// desviados para o emulador, com a mesma latência do perfil.
async function desviarAuth(ctx) {
  await ctx.route(/^https:\/\/(identitytoolkit|securetoken)\.googleapis\.com\//, async (route) => {
    const req = route.request();
    const u = new URL(req.url());
    const alvo = `http://${process.env.AUTH || '127.0.0.1:9099'}${u.host.startsWith('securetoken') ? '/securetoken.googleapis.com' : '/identitytoolkit.googleapis.com'}${u.pathname}${u.search}`;
    if (perfil) await new Promise((ok) => setTimeout(ok, perfil.latency));
    const r = await fetch(alvo, { method: req.method(), headers: { 'content-type': req.headers()['content-type'] || 'application/json' }, body: ['GET', 'HEAD'].includes(req.method()) ? undefined : req.postData() });
    await route.fulfill({
      status: r.status, body: Buffer.from(await r.arrayBuffer()),
      headers: { 'content-type': 'application/json', 'access-control-allow-origin': '*', 'access-control-allow-headers': '*' },
    });
  });
}

const INICIO = `
  window.__lt = []; new PerformanceObserver((l) => { for (const e of l.getEntries()) window.__lt.push([Math.round(e.startTime), Math.round(e.duration)]); }).observe({ entryTypes: ['longtask'] });
  window.levitaMarcar = (n) => performance.mark(n);
  window.addEventListener('flutter-first-frame', () => performance.mark('flutter-first-frame'));
`;

function tipoDe(url) {
  if (/:8080\b|firestore\.googleapis/.test(url)) return 'firestore';
  if (/:9099\b|identitytoolkit|securetoken/.test(url)) return 'auth';
  if (/main\.dart\.js/.test(url)) return 'main.dart.js';
  if (/canvaskit/.test(url)) return 'canvaskit';
  if (/\/fonts\/|\.(ttf|otf|woff2?)(\?|$)/.test(url)) return 'fontes';
  if (/assets\/(assets|AssetManifest|FontManifest|NOTICES)|\.json(\?|$)/.test(url)) return 'assets';
  if (/flutter(_bootstrap)?\.js|sw\.js|index\.html|\/$|avisos\.js|audio\.js|tela_/.test(url)) return 'carregador';
  return 'outros';
}

/// Espera a marca existir; devolve tudo o que a página registrou.
async function coletar(pag, marca, limiteMs) {
  await pag.waitForFunction((m) => performance.getEntriesByName(m, 'mark').length > 0, marca,
    { timeout: limiteMs }).catch(() => {});
  return pag.evaluate(() => {
    const marcas = {};
    for (const e of performance.getEntriesByType('mark')) marcas[e.name] = Math.round(e.startTime);
    const paint = {};
    for (const e of performance.getEntriesByType('paint')) paint[e.name] = Math.round(e.startTime);
    const nav = performance.getEntriesByType('navigation')[0];
    const recursos = performance.getEntriesByType('resource').map((r) => ({
      url: r.name, inicio: Math.round(r.startTime), fim: Math.round(r.responseEnd),
      bytes: r.transferSize, cru: r.decodedBodySize,
    }));
    return {
      marcas, paint, recursos,
      dcl: Math.round(nav?.domContentLoadedEventEnd ?? 0),
      tarefasLongas: window.__lt.length,
      msEmTarefasLongas: window.__lt.reduce((a, b) => a + b[1], 0),
      respostaHtml: Math.round(nav?.responseEnd ?? 0),
    };
  });
}

function resumir(c) {
  const por = {};
  for (const r of c.recursos) {
    const t = tipoDe(r.url);
    por[t] ??= { n: 0, kb: 0, ate: 0 };
    por[t].n++; por[t].kb += (r.bytes || 0) / 1024; por[t].ate = Math.max(por[t].ate, r.fim);
  }
  for (const t of Object.values(por)) t.kb = Math.round(t.kb);
  // Os maiores pedidos, para ver QUEM pesa (nome curto, KB e quando acabou).
  const grandes = [...c.recursos]
    .sort((a, b) => (b.bytes || 0) - (a.bytes || 0))
    .slice(0, 8)
    .map((r) => `${r.url.replace(/^https?:\/\/[^/]+/, (m) => (m.includes('127.0.0.1:') && !/:(8080|9099)/.test(m) ? '' : m)).slice(0, 80)} ${Math.round((r.bytes || 0) / 1024)}KB até ${r.fim}ms`);
  return {
    grandes,
    fcp: c.paint['first-contentful-paint'] ?? null,
    primeiraTela: c.marcas['flutter-first-frame'] ?? null,
    inicioComDados: c.marcas['inicio-com-dados'] ?? null,
    marcas: c.marcas, rede: por, tarefasLongas: c.tarefasLongas, msEmTarefasLongas: c.msEmTarefasLongas, dcl: c.dcl, respostaHtml: c.respostaHtml,
  };
}

// ─── O roteiro ──────────────────────────────────────────────────────────────

const navegador = await chromium.launch();
// devicePixelRatio 1, e não os 3 de um iPhone: este Chromium desenha por
// SOFTWARE (não há GPU), e a 3× cada quadro leva ~65 ms — a thread principal
// fica saturada e até as respostas do banco esperam na fila. Medido: o mesmo
// login até o Início com dados levou 22 s a 2× e 4 s a 1×. Num celular de
// verdade a placa gráfica faz esse trabalho, e este número NÃO é dele.
const iphone = { viewport: { width: 390, height: 844 }, deviceScaleFactor: 1, isMobile: true, hasTouch: true };
const resultado = { perfil: PERFIL, repeticoes: REPETICOES, frias: [], logins: [], quentes: [] };

for (let i = 0; i < REPETICOES; i++) {
  // Cada rodada: contexto NOVO (cache, IndexedDB e service worker vazios).
  const ctx = await navegador.newContext(iphone);
  await ctx.addInitScript(INICIO);
  await desviarAuth(ctx);
  conectados.clear();
  await desviarGoogle(ctx);

  // 1) Primeira abertura de todas: sem nada guardado. Cai na tela de entrar.
  let pag = await ctx.newPage();
  pag.on('pageerror', (e) => console.log('   pageerror:', String(e).slice(0, 140)));
  await segurar(ctx, pag);
  pedidosAoServidor = [];
  await pag.goto(`${origem}/`, { waitUntil: 'commit' });
  const fria = resumir(await coletar(pag, 'flutter-first-frame', 60000));
  resultado.frias.push(fria);

  // 2) Entra (tocando e digitando, como a pessoa) e espera o Início com
  //    dados. As coordenadas são as da tela de entrar a 390 px de largura:
  //    campo do nome, da senha e o botão "Entrar".
  await pag.waitForTimeout(1500);
  const t0 = await pag.evaluate(() => performance.now());
  await pag.touchscreen.tap(195, 440);
  await pag.waitForTimeout(400);
  await pag.keyboard.type(ENTRAR.nome, { delay: 15 });
  await pag.touchscreen.tap(195, 528);
  await pag.waitForTimeout(400);
  await pag.keyboard.type(ENTRAR.senha, { delay: 15 });
  const tEntrar = await pag.evaluate(() => performance.now());
  await pag.touchscreen.tap(195, 598);
  const entrada = await coletar(pag, 'inicio-com-dados', 60000);
  const login = resumir(entrada);
  login.aposEntrar = login.inicioComDados == null ? null : login.inicioComDados - Math.round(tEntrar);
  if (login.inicioComDados == null) {
    console.log('   !! o Início com dados não apareceu; veja a foto');
    await pag.screenshot({ path: arquivoSaida.replace(/\.json$/, `-falha-${i}.png`) });
  }
  resultado.logins.push(login);

  // 3) Deixa o service worker terminar de guardar o app (sem isto a "segunda
  //    abertura" seria a primeira com outro nome).
  await pag.evaluate(() => navigator.serviceWorker.ready.then(() => true)).catch(() => {});
  await pag.waitForTimeout(perfil ? 20000 : 6000);
  await pag.close();
  // O cache do Firestore (IndexedDB) tem uma "trava de dono" de 5 s que a
  // página fechada à força não solta. Quem fecha o app e o abre na hora
  // seguinte cai nisso também — mas é outro caso, e medir os dois juntos
  // esconderia o comum. Espera a trava vencer.
  await new Promise((ok) => setTimeout(ok, 7000));

  // 4) Abre DE NOVO, no mesmo contexto: é a abertura de quem já usa o app.
  for (let k = 0; k < 2; k++) {
    pag = await ctx.newPage();
    await segurar(ctx, pag);
    pedidosAoServidor = [];
    await pag.goto(`${origem}/`, { waitUntil: 'commit' });
    const q = resumir(await coletar(pag, 'inicio-com-dados', 25000));
    q.pedidosAoServidor = pedidosAoServidor.length;
    if (q.inicioComDados == null) {
      console.log('   !! abertura nova sem Início com dados; veja a foto');
      await pag.screenshot({ path: arquivoSaida.replace(/\.json$/, `-quente-falha-${i}-${k}.png`) });
    }
    resultado.quentes.push(q);
    await pag.waitForTimeout(1500);
    await pag.close();
  }
  await ctx.close();
  console.log(`rodada ${i + 1}/${REPETICOES}: fria ${fria.primeiraTela} ms, entrar→dados ${login.aposEntrar} ms, ` +
    `quentes ${resultado.quentes.slice(-2).map((q) => q.inicioComDados).join(' / ')} ms`);
}

await navegador.close();
servidor.close();
fs.writeFileSync(arquivoSaida, JSON.stringify(resultado, null, 1));

const mediana = (xs) => { const v = xs.filter((x) => x != null).sort((a, b) => a - b); return v.length ? v[Math.floor(v.length / 2)] : null; };
console.log('\n══ medianas (ms desde o início da navegação) ══');
console.log('PRIMEIRA ABERTURA (nada guardado)   tela de abertura:', mediana(resultado.frias.map((x) => x.fcp)),
  '| primeira tela do app:', mediana(resultado.frias.map((x) => x.primeiraTela)));
console.log('ENTRAR → Início com dados            ', mediana(resultado.logins.map((x) => x.aposEntrar)));
console.log('ABRIR DE NOVO                        tela de abertura:', mediana(resultado.quentes.map((x) => x.fcp)),
  '| primeira tela do app:', mediana(resultado.quentes.map((x) => x.primeiraTela)),
  '| Início com dados:', mediana(resultado.quentes.map((x) => x.inicioComDados)));
