// Prova, num Chromium de verdade com a REDE DESLIGADA, que o app funciona sem
// internet — e que o que foi feito sem sinal chega quando ela volta.
//
//   node ferramentas/medir/provar_offline.mjs <build/web carimbado> [pasta das fotos]
//
// O app tem de estar compilado com
//   --dart-define=EMULADOR=true --dart-define=MEDIR=true --dart-define=PORTA_FIRESTORE=8081
// e o emulador (Auth + Firestore) de pé, semeado com `semear.mjs` e
// `semear_biblioteca.mjs`.
//
// COMO A REDE É DESLIGADA, e por quê tanto
//
// `context.setOffline(true)` só pega a PÁGINA; o service worker é outro alvo e
// continuaria enxergando o servidor. Então, além disso, este roteiro CORTA os
// três lugares de onde o app pode ouvir resposta: o servidor do app, o proxy do
// emulador do Firestore e os endereços do Google (SDK do Firebase e login).
// Um teste que passa porque algo respondeu por baixo dos panos não prova nada.
//
// COMO SE LÊ A TELA: pela árvore de SEMÂNTICA do Flutter (o texto de cada
// widget), e se toca por eventos no DOM — nunca pelo mouse do Playwright, que
// derruba a página com a semântica ligada. Cada cenário abre a página de novo,
// o que já prova, a cada vez, que o app abre sem internet.
//
// Sai com código 1 se alguma prova reprovar.

import { createRequire } from 'node:module';
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { iniciarProxy } from './proxy_leituras.mjs';

const { chromium } = createRequire(import.meta.url)('playwright');
const [pastaBuild, pastaFotos = '/tmp/provas-offline'] = process.argv.slice(2);
if (!pastaBuild) { console.error('uso: node provar_offline.mjs <build/web> [pasta das fotos]'); process.exit(2); }
fs.mkdirSync(pastaFotos, { recursive: true });

const ENTRAR = JSON.parse(fs.readFileSync(process.env.SEMENTE || '/tmp/semente.json', 'utf8')).entrar;
const PROJETO = process.env.PROJETO || 'espiritual-d2403';
const FIRESTORE = process.env.FIRESTORE || '127.0.0.1:8080';
const raizDoc = `projects/${PROJETO}/databases/(default)/documents`;

const rede = { ligada: true };
const proxy = await iniciarProxy({ de: 8081, para: 8080 });

// ─── servidor do app ────────────────────────────────────────────────────────
const TIPOS = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.json': 'application/json',
  '.wasm': 'application/wasm', '.png': 'image/png', '.css': 'text/css', '.otf': 'font/otf',
  '.ttf': 'font/ttf', '.map': 'application/json', '.ico': 'image/x-icon', '.svg': 'image/svg+xml',
};
const raiz = path.resolve(pastaBuild);
const servidor = http.createServer((req, res) => {
  if (!rede.ligada) { req.destroy(); return; }
  let rel = decodeURIComponent(new URL(req.url, 'http://x').pathname);
  if (rel.endsWith('/')) rel += 'index.html';
  const arq = path.join(raiz, rel);
  if (!arq.startsWith(raiz) || !fs.existsSync(arq) || fs.statSync(arq).isDirectory()) { res.writeHead(404); res.end(); return; }
  res.writeHead(200, { 'content-type': TIPOS[path.extname(arq)] || 'application/octet-stream', 'cache-control': 'max-age=600' });
  fs.createReadStream(arq).pipe(res);
});
await new Promise((ok) => servidor.listen(0, '127.0.0.1', ok));
const origem = `http://127.0.0.1:${servidor.address().port}`;

function ligarRede(ligada) {
  rede.ligada = ligada;
  proxy.cortar(!ligada);
}

// ─── Google: o que o contêiner só alcança por desvio ────────────────────────
const guardados = new Map();
async function desviar(ctx) {
  await ctx.route(/^https:\/\/(www|fonts)\.gstatic\.com\//, async (route) => {
    if (!rede.ligada) { await route.abort('internetdisconnected'); return; }
    const url = route.request().url();
    if (!guardados.has(url)) {
      const r = await route.fetch();
      guardados.set(url, { status: r.status(), headers: r.headers(), corpo: await r.body() });
    }
    const g = guardados.get(url);
    await route.fulfill({ status: g.status, headers: g.headers, body: g.corpo });
  });
  await ctx.route(/^https:\/\/(identitytoolkit|securetoken)\.googleapis\.com\//, async (route) => {
    if (!rede.ligada) { await route.abort('internetdisconnected'); return; }
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

// ─── o banco, por fora do app (acesso de dono do emulador) ──────────────────
const valor = (v) => {
  if (v === null || v === undefined) return { nullValue: null };
  if (typeof v === 'string') return { stringValue: v };
  if (typeof v === 'boolean') return { booleanValue: v };
  if (typeof v === 'number') return Number.isInteger(v) ? { integerValue: String(v) } : { doubleValue: v };
  if (Array.isArray(v)) return { arrayValue: { values: v.map(valor) } };
  return { mapValue: { fields: Object.fromEntries(Object.entries(v).map(([k, x]) => [k, valor(x)])) } };
};
const desvalor = (v) => {
  if ('stringValue' in v) return v.stringValue;
  if ('booleanValue' in v) return v.booleanValue;
  if ('integerValue' in v) return Number(v.integerValue);
  if ('timestampValue' in v) return v.timestampValue;
  if ('arrayValue' in v) return (v.arrayValue.values || []).map(desvalor);
  if ('mapValue' in v) return Object.fromEntries(Object.entries(v.mapValue.fields || {}).map(([k, x]) => [k, desvalor(x)]));
  return null;
};
const dono = { authorization: 'Bearer owner', 'content-type': 'application/json' };
async function lerDoc(caminho) {
  const r = await fetch(`http://${FIRESTORE}/v1/${raizDoc}/${caminho}`, { headers: dono });
  if (!r.ok) return null;
  const j = await r.json();
  return Object.fromEntries(Object.entries(j.fields || {}).map(([k, v]) => [k, desvalor(v)]));
}
async function listar(colecao) {
  const r = await fetch(`http://${FIRESTORE}/v1/${raizDoc}/${colecao}?pageSize=300`, { headers: dono });
  const j = await r.json();
  return (j.documents || []).map((d) => ({ id: d.name.split('/').pop(), campos: Object.fromEntries(Object.entries(d.fields || {}).map(([k, v]) => [k, desvalor(v)])) }));
}
async function gravarCampo(caminho, campo, v) {
  const r = await fetch(`http://${FIRESTORE}/v1/${raizDoc}:commit`, {
    method: 'POST', headers: dono,
    body: JSON.stringify({ writes: [{ update: { name: `${raizDoc}/${caminho}`, fields: { [campo]: valor(v) } }, updateMask: { fieldPaths: [campo] } }] }),
  });
  if (!r.ok) throw new Error(await r.text());
}

// ─── o navegador ────────────────────────────────────────────────────────────
const INICIO = `
  window.levitaMarcar = (n) => performance.mark(n);
  window.addEventListener('flutter-first-frame', () => performance.mark('flutter-first-frame'));
`;
const iphone = { viewport: { width: 390, height: 844 }, deviceScaleFactor: 1, isMobile: true, hasTouch: true };
const navegador = await chromium.launch();
const ctx = await navegador.newContext(iphone);
await ctx.addInitScript(INICIO);
await desviar(ctx);

const resultados = [];
function prova(nome, ok, detalhe = '') {
  resultados.push({ nome, ok: !!ok, detalhe });
  console.log(`${ok ? '  ✔' : '  ✘'} ${nome}${detalhe ? ` — ${detalhe}` : ''}`);
}
const foto = (pag, nome) => pag.screenshot({ path: path.join(pastaFotos, `${nome}.png`) }).catch(() => {});

async function esperarMarca(pag, marca, ms = 60000) {
  const t0 = Date.now();
  const ok = await pag.waitForFunction((m) => performance.getEntriesByName(m, 'mark').length > 0, marca, { timeout: ms }).then(() => true).catch(() => false);
  return ok ? Date.now() - t0 : null;
}
async function abrirPagina(query = '') {
  const pag = await ctx.newPage();
  pag.on('pageerror', (e) => console.log('   pageerror:', String(e).slice(0, 160)));
  await pag.goto(`${origem}/${query}`, { waitUntil: 'commit' });
  return pag;
}
async function entrar(pag) {
  await esperarMarca(pag, 'flutter-first-frame');
  await pag.waitForTimeout(1500);
  await pag.touchscreen.tap(195, 440); await pag.waitForTimeout(400);
  await pag.keyboard.type(ENTRAR.nome, { delay: 15 });
  await pag.touchscreen.tap(195, 528); await pag.waitForTimeout(400);
  await pag.keyboard.type(ENTRAR.senha, { delay: 15 });
  await pag.touchscreen.tap(195, 598);
  return esperarMarca(pag, 'inicio-com-dados');
}
async function semantica(pag) {
  await pag.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click());
  await pag.waitForTimeout(1200);
}
async function ler(pag) {
  return pag.evaluate(() => [...document.querySelectorAll('flt-semantics')]
    .map((el) => (el.getAttribute('aria-label') || el.textContent || '').trim()).filter(Boolean));
}
async function tem(pag, trecho) { return (await ler(pag)).some((t) => t.includes(trecho)); }
async function esperarTexto(pag, trecho, ms = 15000) {
  const t0 = Date.now();
  while (Date.now() - t0 < ms) { if (await tem(pag, trecho)) return Date.now() - t0; await pag.waitForTimeout(400); }
  return null;
}
/// Toca no MENOR elemento que tem o texto, com a sequência que move um InkWell.
async function tocar(pag, texto, { exato = false } = {}) {
  const ok = await pag.evaluate(({ texto, exato }) => {
    const els = [...document.querySelectorAll('flt-semantics')]
      .map((el) => ({ el, t: (el.getAttribute('aria-label') || el.textContent || '').trim(), r: el.getBoundingClientRect() }))
      .filter((x) => x.t && x.r.width > 0 && (exato ? x.t === texto : x.t.includes(texto)))
      .sort((a, b) => a.r.width * a.r.height - b.r.width * b.r.height);
    if (!els.length) return false;
    const { el, r } = els[0];
    const o = { bubbles: true, cancelable: true, clientX: r.x + r.width / 2, clientY: r.y + r.height / 2, pointerId: 1, pointerType: 'touch', isPrimary: true };
    el.dispatchEvent(new PointerEvent('pointerdown', o));
    el.dispatchEvent(new PointerEvent('pointerup', o));
    el.dispatchEvent(new MouseEvent('click', o));
    return true;
  }, { texto, exato });
  await pag.waitForTimeout(900);
  return ok;
}
async function lerArmazem(pag, chave) { return pag.evaluate((c) => window.levitaArmazemLer(c), chave); }
async function chavesDoArmazem(pag, prefixo) { return JSON.parse(await pag.evaluate((p) => window.levitaArmazemChaves(p), prefixo)); }

// ─── 0) o culto onde a pessoa está escalada e ainda não confirmou ───────────
const todos = await listar('scales');
const agora = Date.now();
const futuros = todos.filter((c) => c.campos.date && new Date(c.campos.date).getTime() > agora && !c.campos.canceled)
  .sort((a, b) => new Date(a.campos.date) - new Date(b.campos.date));
const culto = futuros[0];
const euNoCulto = { userId: ENTRAR.id, userName: ENTRAR.nome, instrument: 'keyboard', confirmed: false };
const outros = (culto.campos.levitas || []).filter((l) => l.userId !== ENTRAR.id);
await gravarCampo(`scales/${culto.id}`, 'levitas', [euNoCulto, ...outros]);
console.log(`\nCulto da prova: ${culto.id} (${culto.campos.serviceType})\n`);

// ─── 1) online: entra e deixa o app se preparar ─────────────────────────────
console.log('1) Com internet: entrar e esperar a preparação');
let pag = await abrirPagina();
const tEntrar = await entrar(pag);
prova('entrou com internet e o Início tem dados', tEntrar != null, `${tEntrar} ms`);
await foto(pag, '01-online-inicio');

// Espera a preparação (as cifras, o índice e uma parte dos hinos) terminar o dia.
let gasto = 0;
for (let i = 0; i < 100 && gasto < 240; i++) {
  await pag.waitForTimeout(1500);
  gasto = JSON.parse((await lerArmazem(pag, 'preparo:orcamento')) || '{}').gasto || 0;
}
const cifras = (await chavesDoArmazem(pag, 'arr:')).length;
const hinos = (await chavesDoArmazem(pag, 'hino:harpa:')).length;
const biblia = (await chavesDoArmazem(pag, 'preparo:biblia:')).length;
prova('a preparação guardou as cifras do repertório', cifras >= 40, `${cifras} cifras`);
prova('a preparação guardou letras de hinos, dentro do orçamento', hinos > 100 && gasto <= 250, `${hinos} hinos da Harpa, ${gasto} leituras de 250`);
prova('a Bíblia foi baixada (um arquivo, fora do banco)', biblia >= 1);
// Deixa o service worker terminar de guardar o app e o SDK do Firebase.
await pag.evaluate(() => navigator.serviceWorker.ready.then(() => true)).catch(() => {});
await pag.waitForTimeout(4000);
const sdkNoCache = await pag.evaluate(async () => {
  const n = await caches.keys();
  const c = n.find((x) => x.startsWith('sdk-firebase-'));
  if (!c) return 0;
  return (await (await caches.open(c)).keys()).length;
});
prova('o SDK do Firebase está guardado no aparelho (3 arquivos)', sdkNoCache === 3, `${sdkNoCache} arquivos`);
await pag.close();
await new Promise((ok) => setTimeout(ok, 7000)); // a trava de dono do cache do Firestore

// ─── 2) a rede some ─────────────────────────────────────────────────────────
console.log('\n2) SEM internet: tudo cortado (servidor, banco, Google)');
ligarRede(false);
await ctx.setOffline(true);

pag = await abrirPagina();
const tOff = await esperarMarca(pag, 'inicio-com-dados', 30000);
prova('abre o app e mostra o Início com dados', tOff != null, `${tOff} ms`);
await semantica(pag);
await foto(pag, '02-offline-inicio');
prova('o cartão do culto está na tela', await tem(pag, 'Você toca') || await tem(pag, culto.campos.serviceType));
const faixa = await esperarTexto(pag, 'Sem internet', 20000);
prova('a faixa "Sem internet" aparece (só depois de 10 s)', faixa != null);
await foto(pag, '03-offline-faixa');

// Confirmar presença
const tocouConfirmar = await tocar(pag, 'Confirmar presença');
await pag.waitForTimeout(1500);
const esperandoCard = await esperarTexto(pag, 'Esperando a internet', 6000);
prova('confirmar presença: fica "Esperando a internet" e NÃO dá erro', tocouConfirmar && esperandoCard != null);
await foto(pag, '04-offline-presenca-pendente');
const fila1 = JSON.parse((await lerArmazem(pag, 'fila:v1')) || '[]');
prova('a confirmação está na fila, guardada no aparelho', fila1.some((i) => i.tipo === 'presenca' || (i.chave || '').startsWith('presenca:')), `${fila1.length} item(ns)`);
await pag.close();

// Fechar e abrir de novo: a fila sobrevive.
pag = await abrirPagina();
await esperarMarca(pag, 'inicio-com-dados', 30000);
await semantica(pag);
prova('depois de fechar e abrir de novo, a confirmação continua pendente',
  await esperarTexto(pag, 'Esperando a internet', 8000) != null);
await pag.close();

// Música: cifra
pag = await abrirPagina();
await esperarMarca(pag, 'inicio-com-dados', 30000);
await semantica(pag);
await tocar(pag, 'Músicas');
await pag.waitForTimeout(1200);
await tocar(pag, 'Grande é a tua fidelidade');
const cifraNaTela = await esperarTexto(pag, 'Cifra inventada da música', 10000);
prova('lê uma música com a CIFRA, sem internet', cifraNaTela != null, `${cifraNaTela} ms`);
await foto(pag, '05-offline-musica-cifra');
await pag.close();

// Hino pelo número
pag = await abrirPagina();
await esperarMarca(pag, 'inicio-com-dados', 30000);
await semantica(pag);
await tocar(pag, 'Músicas');
await pag.waitForTimeout(800);
await tocar(pag, 'Hinários');
await pag.waitForTimeout(1500);
await tocar(pag, '7', { exato: true });
await tocar(pag, '7', { exato: true });
const hino77 = await esperarTexto(pag, 'Verso inventado 77', 10000);
prova('abre o hino 77 da Harpa pelo número, sem internet', hino77 != null, hino77 != null ? `${hino77} ms` : '');
await foto(pag, '06-offline-hino-77');
await pag.close();

// Hino que nunca foi baixado: diz o que fazer, na hora.
pag = await abrirPagina();
await esperarMarca(pag, 'inicio-com-dados', 30000);
await semantica(pag);
await tocar(pag, 'Músicas'); await pag.waitForTimeout(800);
await tocar(pag, 'Hinários'); await pag.waitForTimeout(1500);
for (const d of ['5', '0', '0']) await tocar(pag, d, { exato: true });
const semBaixar = await esperarTexto(pag, 'Sem internet', 10000);
prova('hino que nunca foi baixado: o app diz que falta internet (sem travar)', semBaixar != null);
await foto(pag, '07-offline-hino-nao-baixado');
await pag.close();

// Bíblia
pag = await abrirPagina();
await esperarMarca(pag, 'inicio-com-dados', 30000);
await semantica(pag);
await tocar(pag, 'Músicas'); await pag.waitForTimeout(800);
await tocar(pag, 'Bíblia'); await pag.waitForTimeout(2500);
const livros = await esperarTexto(pag, 'Gênesis', 20000);
prova('a Bíblia abre sem internet e lista os livros', livros != null, livros != null ? `${livros} ms` : '');
await tocar(pag, 'Gênesis'); await pag.waitForTimeout(1500);
await tocar(pag, '1', { exato: true }); await pag.waitForTimeout(1500);
prova('lê Gênesis 1, sem internet', await tem(pag, 'Gênesis 1'));
await foto(pag, '08-offline-biblia');
await pag.close();

// Escala
pag = await abrirPagina();
await esperarMarca(pag, 'inicio-com-dados', 30000);
await semantica(pag);
await tocar(pag, 'Escala'); await pag.waitForTimeout(1500);
const textos = await ler(pag);
prova('vê a escala dos cultos, sem internet', textos.some((t) => /Culto/.test(t)), `${textos.filter((t) => /Culto/.test(t)).length} cultos à vista`);
await foto(pag, '09-offline-escala');
await pag.close();

// ─── 3) a rede volta: a fila esvazia ────────────────────────────────────────
console.log('\n3) A internet volta');
ligarRede(true);
await ctx.setOffline(false);
pag = await abrirPagina();
await esperarMarca(pag, 'inicio-com-dados', 30000);
let confirmadoNoBanco = false;
for (let i = 0; i < 60 && !confirmadoNoBanco; i++) {
  await pag.waitForTimeout(1500);
  const doc = await lerDoc(`scales/${culto.id}`);
  const eu = (doc?.levitas || []).find((l) => l.userId === ENTRAR.id);
  confirmadoNoBanco = !!eu?.confirmed;
}
prova('a presença chegou ao banco sozinha', confirmadoNoBanco);
const fila2 = JSON.parse((await lerArmazem(pag, 'fila:v1')) || '[]');
prova('a fila esvaziou', fila2.length === 0, `${fila2.length} item(ns)`);
await semantica(pag);
prova('a faixa de rede sumiu', !(await tem(pag, 'Sem internet')));
const docFinal = await lerDoc(`scales/${culto.id}`);
prova('o carimbo "confirmadoEm" foi gravado junto (o aviso ao líder depende dele)', !!docFinal?.confirmadoEm);
await foto(pag, '10-online-de-volta');
await pag.close();

// ─── 4) o aparelho apaga os dados ───────────────────────────────────────────
console.log('\n4) O aparelho apaga o que o app guardou');
// 4a) só o armazém do app (o caso que se PERCEBE: uma das duas marcas some).
pag = await abrirPagina('icons/Icon-192.png');
await pag.waitForTimeout(500);
await pag.evaluate(() => new Promise((ok) => { const r = indexedDB.deleteDatabase('levita-armazem'); r.onsuccess = r.onerror = r.onblocked = () => ok(); }));
await pag.close();
pag = await abrirPagina();
const tApagado = await esperarMarca(pag, 'inicio-com-dados', 40000);
prova('apagado o armazém do app: abre sozinho, sem erro e sem pedir nada', tApagado != null, `${tApagado} ms`);
await semantica(pag);
prova('e não caiu na tela de entrar', !(await tem(pag, 'Entrar')) || (await tem(pag, 'Início')));
let recuperou = 0;
for (let i = 0; i < 40 && recuperou < 20; i++) {
  await pag.waitForTimeout(1500);
  recuperou = (await chavesDoArmazem(pag, 'arr:')).length;
}
prova('o app baixou as cifras de novo por conta própria', recuperou >= 20, `${recuperou} cifras de volta`);
const marcaVoltou = await lerArmazem(pag, 'marca-aparelho');
prova('as marcas de conferência foram refeitas', marcaVoltou != null);
await foto(pag, '11-recuperado');
await pag.close();

// 4b) tudo (inclusive o login): o limite que o app NÃO consegue esconder.
pag = await abrirPagina('icons/Icon-192.png');
await pag.waitForTimeout(500);
await pag.evaluate(async () => {
  localStorage.clear(); sessionStorage.clear();
  const bancos = await indexedDB.databases();
  await Promise.all(bancos.map((b) => new Promise((ok) => { const r = indexedDB.deleteDatabase(b.name); r.onsuccess = r.onerror = r.onblocked = () => ok(); })));
  for (const n of await caches.keys()) await caches.delete(n);
  for (const r of await navigator.serviceWorker.getRegistrations()) await r.unregister();
});
await pag.close();
pag = await abrirPagina();
await esperarMarca(pag, 'flutter-first-frame', 40000);
await pag.waitForTimeout(3000);
await foto(pag, '12-tudo-apagado');
const pediuEntrar = await tem((await (async () => { await semantica(pag); return pag; })()), 'Entrar');
prova('apagado TUDO (login incluído): o app abre na tela de entrar, sem erro', pediuEntrar);
const t2 = await entrar(pag);
prova('entrando de novo, os dados voltam sozinhos', t2 != null, `${t2} ms`);
await pag.close();

await navegador.close();
servidor.close();
proxy.parar();

const falhas = resultados.filter((r) => !r.ok);
fs.writeFileSync(path.join(pastaFotos, 'resultado.json'), JSON.stringify(resultados, null, 1));
console.log(`\n${resultados.length - falhas.length} de ${resultados.length} provas passaram.`);
process.exit(falhas.length ? 1 : 0);
