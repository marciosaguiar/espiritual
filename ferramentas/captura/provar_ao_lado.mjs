// Prova, num Chromium de verdade, que tocar num item abre o detalhe AO LADO.
//
// COMO USAR
//
//   flutter build web --release -t ferramentas/captura/main_demo.dart \
//       --base-href / --pwa-strategy=none --no-web-resources-cdn
//   node ferramentas/captura/provar_ao_lado.mjs build/web /pasta/das/fotos
//   # opcional: LARGURAS=1280,1920,2400
//
// POR QUE EXISTE
//
// As fotos do renderizador de testes do Flutter não clicam, não têm teclado e
// não são um navegador. O dono conferiu a tela larga no Chrome e achou o que
// elas não achavam: a música abrindo em tela cheia. Aqui o clique é um clique
// de mouse de verdade, no demo compilado para a web (sem Firebase), e o
// resultado é lido da ÁRVORE DE SEMÂNTICA do Flutter — o texto de cada widget
// com sua posição —, não de pixels.
//
// DUAS COISAS QUE CUSTARAM TEMPO
//
// - O mouse do Playwright derruba a página DEPOIS que a semântica é ligada
//   (o filtro de cliques do motor se perde com ponteiro sintético). Então cada
//   cenário clica ANTES e só no fim liga a semântica para ler; cenário novo,
//   página nova.
// - As coordenadas são as da distribuição do app (barra lateral de 226 px,
//   lista de 36% da janela entre 360 e 440). Se a tela mudar de lugar, o
//   cenário reprova e mostra a foto — é para ser lido, não só aprovado.
//
// Sai com código 1 se algum cenário reprovar.

import { createRequire } from 'node:module';
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';

const { chromium } = createRequire(import.meta.url)('playwright');

const [pastaBuild, pastaSaida = '/tmp/provas'] = process.argv.slice(2);
if (!pastaBuild) {
  console.error('uso: node provar_ao_lado.mjs <build/web> [pasta das fotos]');
  process.exit(2);
}
fs.mkdirSync(pastaSaida, { recursive: true });

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
  if (!arq.startsWith(raiz) || !fs.existsSync(arq) || fs.statSync(arq).isDirectory()) {
    res.writeHead(404); res.end(); return;
  }
  res.writeHead(200, { 'content-type': TIPOS[path.extname(arq)] || 'application/octet-stream' });
  fs.createReadStream(arq).pipe(res);
});
await new Promise((ok) => servidor.listen(0, '127.0.0.1', ok));
const porta = servidor.address().port;

const larguras = (process.env.LARGURAS || '1280,1920,2400').split(',').map(Number);
const ALTURAS = { 1280: 800, 1920: 1080, 2400: 1200 };
const navegador = await chromium.launch();

// ─── Onde fica cada coisa ────────────────────────────────────────────────

const NAVEGACAO = 226;
const larguraDaLista = (w) => Math.min(440, Math.max(360, (w - NAVEGACAO) * 0.36));
const centroDaLista = (w) => NAVEGACAO + larguraDaLista(w) / 2;
const fimDaLista = (w) => NAVEGACAO + larguraDaLista(w);

// ─── Ler a tela ──────────────────────────────────────────────────────────

/// Liga a semântica (por um clique no DOM, NÃO pelo mouse) e devolve o texto
/// de cada elemento com a caixa que ocupa.
async function lerATela(pag) {
  await pag.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click());
  await pag.waitForTimeout(1200);
  return pag.evaluate(() => {
    const saida = [];
    for (const el of document.querySelectorAll('flt-semantics')) {
      const texto = (el.getAttribute('aria-label') || el.textContent || '').trim();
      if (!texto) continue;
      const r = el.getBoundingClientRect();
      if (r.width === 0 && r.height === 0) continue;
      saida.push({ texto, x: r.x, y: r.y, w: r.width, h: r.height });
    }
    return saida;
  });
}

// O elemento MENOR que tem o texto: um contêiner traz o texto de todos os
// filhos (e começa na esquerda da tela), e mediria a posição errada.
const tem = (itens, trecho) =>
  itens
    .filter((i) => i.texto.includes(trecho))
    .sort((a, b) => a.w * a.h - b.w * b.h)[0];

async function abrirPagina(largura, query) {
  const altura = ALTURAS[largura] || 900;
  const ctx = await navegador.newContext({ viewport: { width: largura, height: altura }, deviceScaleFactor: 1 });
  const pag = await ctx.newPage();
  pag.on('pageerror', (e) => console.log('   pageerror:', String(e).slice(0, 160)));
  await pag.goto(`http://127.0.0.1:${porta}/?${query}`);
  await pag.waitForSelector('flt-glass-pane', { state: 'attached', timeout: 60000 });
  await pag.waitForTimeout(3500);
  return { ctx, pag };
}

async function clicar(pag, x, y) {
  await pag.mouse.move(x, y);
  await pag.mouse.click(x, y);
  await pag.waitForTimeout(900);
}

// ─── Cenários ────────────────────────────────────────────────────────────

/// Cada um: o que tocar, e o que tem de aparecer / sumir / onde.
function cenarios(w) {
  const cx = centroDaLista(w);
  const sugestaoY = [285, 336, 387, 438];
  const abrirSugestao = [[cx, 234]];
  return [
    ...sugestaoY.map((y, i) => ({
      nome: `repertorio-sugestao-${i + 1}`,
      query: 'aba=1',
      passos: [...abrirSugestao, [cx, y]],
      vazio: 'Escolha uma música',
      lista: 'Todas as músicas (16)',
      detalhe: 'Tom',
    })),
    {
      nome: 'repertorio-lista',
      query: 'aba=1',
      passos: [[cx, 345]],
      vazio: 'Escolha uma música',
      lista: 'Todas as músicas (16)',
      detalhe: 'Tom',
    },
    {
      nome: 'hinarios-hino',
      query: 'aba=1',
      passos: [[cx - 4, 71], [cx, 340]],
      vazio: 'Escolha um hino',
      lista: '640 hinos',
      detalhe: 'Pôr no repertório',
    },
    {
      nome: 'escala-culto',
      query: 'aba=2',
      passos: [[cx, 452]],
      vazio: 'Escolha um culto',
      lista: 'novembro de 2026',
      detalhe: 'Observações do culto',
    },
  ];
}

let reprovou = 0;
function conferir(ok, mensagem) {
  console.log(`   ${ok ? '✓' : '✗'} ${mensagem}`);
  if (!ok) reprovou++;
}

for (const w of larguras) {
  console.log(`\n══ ${w} px ══`);
  for (const c of cenarios(w)) {
    console.log(`  ${c.nome}`);
    const { ctx, pag } = await abrirPagina(w, c.query);
    for (const [x, y] of c.passos) await clicar(pag, x, y);
    await pag.screenshot({ path: path.join(pastaSaida, `${w}-${c.nome}.png`) });
    const itens = await lerATela(pag);

    conferir(!tem(itens, c.vazio), `o painel NÃO diz mais "${c.vazio}"`);
    const lista = tem(itens, c.lista);
    const detalhe = tem(itens, c.detalhe);
    conferir(!!lista, `a lista continua na tela ("${c.lista}")`);
    conferir(!!detalhe, `o detalhe apareceu ("${c.detalhe}")`);
    if (lista && detalhe) {
      conferir(detalhe.x >= fimDaLista(w) - 8,
        `o detalhe está À DIREITA da lista (x=${Math.round(detalhe.x)} ≥ ${Math.round(fimDaLista(w))})`);
    }

    // Esc fecha o detalhe: só no primeiro cenário de cada largura, e na
    // mesma página (a semântica já está ligada, e o teclado não é o mouse).
    if (c.nome === 'repertorio-sugestao-1') {
      await pag.keyboard.press('Escape');
      await pag.waitForTimeout(900);
      const depois = await pag.evaluate(() =>
        [...document.querySelectorAll('flt-semantics')]
          .map((e) => (e.getAttribute('aria-label') || e.textContent || '').trim()));
      conferir(depois.some((t) => t.includes('Escolha uma música')), 'Esc fecha o detalhe');
      await pag.screenshot({ path: path.join(pastaSaida, `${w}-repertorio-esc.png`) });
    }
    await ctx.close();
  }
}

await navegador.close();
servidor.close();
console.log(reprovou === 0 ? '\nTUDO CERTO' : `\n${reprovou} conferência(s) REPROVADA(S)`);
process.exit(reprovou === 0 ? 0 : 1);
