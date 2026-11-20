// Conta QUANTOS DOCUMENTOS o banco entrega ao app — que é o que o Firebase
// cobra como leitura — em cada situação, antes e depois da rodada "offline
// primeiro".
//
//   # emulador de pé na 8080; proxy contador na 8081 (este script o sobe)
//   node ferramentas/medir/medir_leituras.mjs <build/web carimbado> <saida.json>
//
//   COM_PREPARO=1   também mede a preparação em segundo plano (só existe na
//                   versão nova), em dois "dias" seguidos
//
// O app medido tem de ter sido compilado com
//   --dart-define=EMULADOR=true --dart-define=MEDIR=true --dart-define=PORTA_FIRESTORE=8081
// para falar com o emulador PELO PROXY.
//
// O QUE SE MEDE
//
//   fria      primeira abertura de quem acabou de entrar (cache vazio)
//   quente1   abrir de novo logo em seguida
//   quente2   e mais uma vez
//   (com preparo) o que a preparação puxa no dia 1 e no dia 2
//
// O QUE ISTO NÃO MEDE (e o relatório diz em voz alta): o emulador não
// implementa a regra dos 30 minutos — escuta religada depois de mais de 30 min
// parada é cobrada como consulta NOVA, com todos os documentos de novo. Então
// o número de uma abertura "fria" aqui é o que CADA abertura depois de 30 min
// de intervalo custa em produção, e a conta por dia (`relatorio_leituras`)
// multiplica isso pelo número de aberturas separadas por mais de 30 min.

import { createRequire } from 'node:module';
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { iniciarProxy } from './proxy_leituras.mjs';

const { chromium } = createRequire(import.meta.url)('playwright');

const [pastaBuild, arquivoSaida = '/tmp/leituras.json'] = process.argv.slice(2);
if (!pastaBuild) { console.error('uso: node medir_leituras.mjs <build/web> [saida.json]'); process.exit(2); }
const COM_PREPARO = process.env.COM_PREPARO === '1';
const ENTRAR = JSON.parse(fs.readFileSync(process.env.SEMENTE || '/tmp/semente.json', 'utf8')).entrar;
const ESPERA_PREPARO = Number(process.env.ESPERA_PREPARO || 45000);

const proxy = await iniciarProxy({ de: 8081, para: 8080 });

// ─── servidor estático (sem freio: aqui se conta documento, não tempo) ──────
const TIPOS = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.json': 'application/json',
  '.wasm': 'application/wasm', '.png': 'image/png', '.css': 'text/css', '.otf': 'font/otf',
  '.ttf': 'font/ttf', '.map': 'application/json', '.ico': 'image/x-icon', '.svg': 'image/svg+xml',
};
const raiz = path.resolve(pastaBuild);
const servidor = http.createServer((req, res) => {
  let rel = decodeURIComponent(new URL(req.url, 'http://x').pathname);
  if (rel.endsWith('/')) rel += 'index.html';
  const arq = path.join(raiz, rel);
  if (!arq.startsWith(raiz) || !fs.existsSync(arq) || fs.statSync(arq).isDirectory()) { res.writeHead(404); res.end(); return; }
  res.writeHead(200, { 'content-type': TIPOS[path.extname(arq)] || 'application/octet-stream', 'cache-control': 'max-age=600' });
  fs.createReadStream(arq).pipe(res);
});
await new Promise((ok) => servidor.listen(0, '127.0.0.1', ok));
const origem = `http://127.0.0.1:${servidor.address().port}`;

// ─── o que o contêiner não tem: Google de verdade ───────────────────────────
const guardados = new Map();
async function desviarGoogle(ctx) {
  await ctx.route(/^https:\/\/(www|fonts)\.gstatic\.com\//, async (route) => {
    const url = route.request().url();
    if (!guardados.has(url)) {
      const r = await route.fetch();
      guardados.set(url, { status: r.status(), headers: r.headers(), corpo: await r.body() });
    }
    const g = guardados.get(url);
    await route.fulfill({ status: g.status, headers: g.headers, body: g.corpo });
  });
}
async function desviarAuth(ctx) {
  await ctx.route(/^https:\/\/(identitytoolkit|securetoken)\.googleapis\.com\//, async (route) => {
    const req = route.request();
    const u = new URL(req.url());
    const alvo = `http://${process.env.AUTH || '127.0.0.1:9099'}${u.host.startsWith('securetoken') ? '/securetoken.googleapis.com' : '/identitytoolkit.googleapis.com'}${u.pathname}${u.search}`;
    const r = await fetch(alvo, { method: req.method(), headers: { 'content-type': req.headers()['content-type'] || 'application/json' }, body: ['GET', 'HEAD'].includes(req.method()) ? undefined : req.postData() });
    await route.fulfill({
      status: r.status, body: Buffer.from(await r.arrayBuffer()),
      headers: { 'content-type': 'application/json', 'access-control-allow-origin': '*', 'access-control-allow-headers': '*' },
    });
  });
}

const INICIO = `
  window.levitaMarcar = (n) => performance.mark(n);
  window.addEventListener('flutter-first-frame', () => performance.mark('flutter-first-frame'));
`;
const iphone = { viewport: { width: 390, height: 844 }, deviceScaleFactor: 1, isMobile: true, hasTouch: true };

async function esperarMarca(pag, marca, ms = 60000) {
  await pag.waitForFunction((m) => performance.getEntriesByName(m, 'mark').length > 0, marca, { timeout: ms }).catch(() => {});
}
async function entrar(pag) {
  await esperarMarca(pag, 'flutter-first-frame');
  await pag.waitForTimeout(1500);
  await pag.touchscreen.tap(195, 440); await pag.waitForTimeout(400);
  await pag.keyboard.type(ENTRAR.nome, { delay: 15 });
  await pag.touchscreen.tap(195, 528); await pag.waitForTimeout(400);
  await pag.keyboard.type(ENTRAR.senha, { delay: 15 });
  await pag.touchscreen.tap(195, 598);
  await esperarMarca(pag, 'inicio-com-dados');
}
async function lerArmazem(pag, chave) {
  return pag.evaluate((c) => window.levitaArmazemLer(c), chave);
}

const navegador = await chromium.launch();
const resultado = { comPreparo: COM_PREPARO };

async function contexto() {
  const ctx = await navegador.newContext(iphone);
  await ctx.addInitScript(INICIO);
  await desviarAuth(ctx);
  await desviarGoogle(ctx);
  return ctx;
}

async function abrir(ctx, query) {
  const pag = await ctx.newPage();
  pag.on('pageerror', (e) => console.log('   pageerror:', String(e).slice(0, 140)));
  // O SDK avisa no console quando não consegue o cache persistente (segunda
  // aba, trava de dono): é o que faria uma abertura "quente" custar como fria.
  pag.on('console', (m) => {
    const t = m.text();
    if (/persist|precondition|Failed to obtain|IndexedDB/i.test(t)) console.log('   console:', t.slice(0, 200));
  });
  await pag.goto(`${origem}/${query}`, { waitUntil: 'commit' });
  return pag;
}

// ─── A: a abertura, SEM a preparação (separa o que é de cada coisa) ─────────
{
  const ctx = await contexto();
  proxy.zerar();
  let pag = await abrir(ctx, '?sem-preparo');
  await entrar(pag);
  await pag.waitForTimeout(8000);
  resultado.fria = proxy.lidos();
  resultado.tokensEnviadosNaFria = proxy.tokensEnviados();
  console.log(`fria (entrar + Início): ${resultado.fria} documentos`);

  await pag.evaluate(() => navigator.serviceWorker?.ready).catch(() => {});
  await pag.waitForTimeout(3000);
  await pag.close();
  await new Promise((ok) => setTimeout(ok, 7000)); // a trava de dono do cache (5 s)

  for (const n of [1, 2]) {
    proxy.zerar();
    pag = await abrir(ctx, '?sem-preparo');
    await esperarMarca(pag, 'inicio-com-dados', 30000);
    await pag.waitForTimeout(8000);
    resultado[`quente${n}`] = proxy.lidos();
    resultado[`tokensEnviadosNaQuente${n}`] = proxy.tokensEnviados();
    console.log(`quente ${n}: ${resultado[`quente${n}`]} documentos (o app mandou ${proxy.tokensEnviados()} resumeToken)`);
    await pag.close();
    await new Promise((ok) => setTimeout(ok, 7000));
  }
  await ctx.close();
}

// ─── B: a preparação, dia 1 e dia 2 ─────────────────────────────────────────
if (COM_PREPARO) {
  const ctx = await contexto();
  let pag = await abrir(ctx, '');
  proxy.zerar();
  await entrar(pag);
  const aberturaFria = resultado.fria;
  await pag.waitForTimeout(ESPERA_PREPARO);
  const total1 = proxy.lidos();
  const orc1 = JSON.parse((await lerArmazem(pag, 'preparo:orcamento')) || '{}');
  const prog1 = JSON.parse((await lerArmazem(pag, 'preparo:progresso')) || '{}');
  resultado.dia1 = { total: total1, daPreparacao: total1 - aberturaFria, orcamentoGasto: orc1.gasto, progresso: prog1 };
  console.log(`dia 1: ${total1} documentos no total; preparação ≈ ${total1 - aberturaFria}; orçamento gasto ${orc1.gasto}`);

  // "Dia 2": o orçamento de ontem não vale; abre de novo.
  await pag.evaluate(() => window.levitaArmazemGravar('preparo:orcamento', JSON.stringify({ dia: '2000-01-01', gasto: 250 })));
  await pag.waitForTimeout(1500);
  await pag.close();
  await new Promise((ok) => setTimeout(ok, 7000));
  proxy.zerar();
  pag = await abrir(ctx, '');
  await esperarMarca(pag, 'inicio-com-dados', 30000);
  await pag.waitForTimeout(ESPERA_PREPARO);
  const orc2 = JSON.parse((await lerArmazem(pag, 'preparo:orcamento')) || '{}');
  resultado.dia2 = { total: proxy.lidos(), orcamentoGasto: orc2.gasto };
  console.log(`dia 2: ${resultado.dia2.total} documentos (abertura quente + preparação); orçamento gasto ${orc2.gasto}`);
  await ctx.close();
}

await navegador.close();
servidor.close();
proxy.parar();
fs.writeFileSync(arquivoSaida, JSON.stringify(resultado, null, 1));
console.log('salvo em', arquivoSaida);
// O proxy e o servidor mantêm conexões abertas; sem isto o processo não termina
// e quem espera por ele (um roteiro em sequência) fica esperando para sempre.
process.exit(0);
