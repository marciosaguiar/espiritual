// Carimba o service worker de um build local, como a publicação faz.
//
//   node ferramentas/medir/carimbar_sw.mjs build/web
//
// A lista do que guardar sai do build (nunca escrita à mão) e é posta na
// frente do `sw.js`. É a MESMA conta do passo "Carimbar a versão" de
// `.github/workflows/web-preview.yml` — copiada aqui para a medição abrir o
// app com o cache que o celular da pessoa de fato teria. Se a publicação
// mudar de regra, esta cópia precisa acompanhar.

import fs from 'node:fs';
import p from 'node:path';

const raiz = process.argv[2] || 'build/web';
const fora = new RegExp(
  '^canvaskit/webparagraph/' +
  '|^assets/assets/biblia/' +
  '|(^|/)(skwasm[^/]*|wimp\\.wasm|NOTICES|sw\\.js|\\.last_build_id)$');
const arquivos = [];
(function anda(dir) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const caminho = p.join(dir, e.name);
    if (e.isDirectory()) { anda(caminho); continue; }
    const rel = p.relative(raiz, caminho).split(p.sep).join('/');
    if (!fora.test(rel)) arquivos.push(rel);
  }
})(raiz);
arquivos.unshift('./');
const versao = (process.env.VERSAO || 'medicao').slice(0, 12);
const cabeca = 'self.VERSAO_DO_BUILD = ' + JSON.stringify(versao) +
  ';\nself.LISTA_DO_BUILD = ' + JSON.stringify(arquivos) + ';\n';
const alvo = p.join(raiz, 'sw.js');
const atual = fs.readFileSync(alvo, 'utf8');
if (atual.startsWith('self.VERSAO_DO_BUILD')) {
  console.log('sw.js já estava carimbado');
} else {
  fs.writeFileSync(alvo, cabeca + atual);
  console.log(`sw.js: versão ${versao}, ${arquivos.length} arquivos no cache`);
}
