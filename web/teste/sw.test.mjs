// Testa o `web/sw.js` DE VERDADE, com o ambiente do navegador simulado.
//
// POR QUE ASSIM, e não num navegador
//
// A primeira tentativa foi no Chromium: entregar pushes pelo protocolo do
// Chrome e ler as notificações abertas. O push chegava ao service worker, mas
// `Notification.permission` responde `denied` no Chromium headless — nem o
// `grantPermissions` do Playwright nem o `Browser.grantPermissions` do
// protocolo mudam isso. Então `showNotification` lançava e a medição dizia
// "nenhum aviso apareceu" quando o problema era o ambiente.
//
// Aqui o arquivo é o mesmo que vai para o ar: ele é carregado como código e
// recebe um `self` de mentira. O que se mede é a decisão dele — qual etiqueta
// usa, como conta, para onde manda quem toca —, que é onde um erro não
// aparece na tela de ninguém: o aviso chega bonito e leva à tela errada.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const AQUI = dirname(fileURLToPath(import.meta.url));
const CODIGO = readFileSync(join(AQUI, '..', 'sw.js'), 'utf8');

/// Carrega o service worker com um `self` de mentira e devolve o que ele fez.
function montarSw({ clientes = [] } = {}) {
  const ouvintes = {};
  const notificacoes = [];
  const recados = [];
  const janelasAbertas = [];

  const self = {
    addEventListener(nome, fn) {
      (ouvintes[nome] ??= []).push(fn);
    },
    skipWaiting() {},
    location: { origin: 'https://exemplo.app' },
    registration: {
      scope: 'https://exemplo.app/',
      showNotification(titulo, opcoes = {}) {
        // O navegador substitui a notificação de mesma etiqueta, em vez de
        // empilhar. Sem isto, o teste da contagem do chat passaria por
        // acidente.
        const i = notificacoes.findIndex((n) => n.tag === opcoes.tag);
        const nova = { title: titulo, ...opcoes };
        if (i >= 0) notificacoes[i] = nova;
        else notificacoes.push(nova);
        return Promise.resolve();
      },
      getNotifications({ tag } = {}) {
        return Promise.resolve(
          notificacoes.filter((n) => tag === undefined || n.tag === tag));
      },
      pushManager: { subscribe: () => Promise.resolve({}) },
    },
    clients: {
      matchAll: () => Promise.resolve(clientes),
      openWindow(url) {
        janelasAbertas.push(url);
        return Promise.resolve();
      },
      claim: () => Promise.resolve(),
    },
  };

  // `caches` e `fetch` só são usados pelos ouvintes de instalação e de rede,
  // que este teste não dispara.
  const fabrica = new Function('self', 'caches', 'fetch', 'console', CODIGO);
  fabrica(self, undefined, undefined, { warn() {}, log() {} });

  async function disparar(nome, evento) {
    const esperas = [];
    evento.waitUntil = (p) => esperas.push(p);
    for (const fn of ouvintes[nome] ?? []) fn(evento);
    await Promise.all(esperas);
  }

  const push = (dados) => disparar('push', {
    // `corpoQuebrado` imita o que o navegador faz com bytes que não são
    // JSON: o `json()` lança. Já `dados` igual a `null` é JSON VÁLIDO, e
    // chega como null — os dois casos acabam sem título.
    data: dados === 'corpoQuebrado'
      ? { json() { throw new SyntaxError('não é JSON'); } }
      : { json: () => dados },
  });

  const toque = (dados) =>
    disparar('notificationclick', {
      notification: { data: dados, close() {} },
    });

  return { push, toque, notificacoes, recados, janelasAbertas };
}

const PEDIDO_ANA = {
  titulo: 'Novo pedido de entrada',
  corpo: 'Ana quer entrar no ministério',
  abrir: 'membros',
  etiqueta: 'levita-pedido-u1',
};

// ── Novo pedido de entrada ──────────────────────────────────────────────────

test('o pedido de entrada aparece com o nome de quem pediu', async () => {
  const sw = montarSw();
  await sw.push(PEDIDO_ANA);
  assert.equal(sw.notificacoes.length, 1);
  assert.equal(sw.notificacoes[0].title, 'Novo pedido de entrada');
  assert.match(sw.notificacoes[0].body, /Ana quer entrar/);
});

test('DOIS pedidos são dois avisos, não um apagando o outro', async () => {
  // Etiqueta por pessoa. Com etiqueta fixa, o segundo cadastro substituiria o
  // primeiro e o líder perderia um nome — o pedido de alguém sumiria sem
  // nada na tela dizendo que houve dois.
  const sw = montarSw();
  await sw.push(PEDIDO_ANA);
  await sw.push({
    ...PEDIDO_ANA,
    corpo: 'Bruno quer entrar no ministério',
    etiqueta: 'levita-pedido-u2',
  });
  assert.equal(sw.notificacoes.length, 2);
  assert.deepEqual(sw.notificacoes.map((n) => n.tag),
    ['levita-pedido-u1', 'levita-pedido-u2']);
});

test('o pedido NÃO entra na contagem do chat', async () => {
  // "2 mensagens novas" tem de contar mensagens. Somar o pedido de entrada
  // ali esconderia justamente o que importa, e o número ficaria errado.
  const sw = montarSw();
  await sw.push(PEDIDO_ANA);
  await sw.push({ titulo: 'Ana', corpo: 'bom dia' });
  await sw.push({ titulo: 'Ana', corpo: 'alguém leva o cabo?' });

  const chat = sw.notificacoes.filter((n) => n.tag === 'levita-chat');
  assert.equal(chat.length, 1);
  assert.equal(chat[0].title, '2 mensagens novas');
  assert.equal(chat[0].data.quantas, 2);
  // E o pedido continua na tela, inteiro.
  assert.equal(
    sw.notificacoes.filter((n) => n.tag === 'levita-pedido-u1').length, 1);
});

test('aviso de culto também não se mistura', async () => {
  const sw = montarSw();
  await sw.push({ titulo: 'Você foi escalado', corpo: 'Culto domingo',
                  abrir: 'culto', cultoId: '2026-11-22_1900' });
  await sw.push(PEDIDO_ANA);
  await sw.push({ titulo: 'Ana', corpo: 'bom dia' });
  assert.deepEqual(sw.notificacoes.map((n) => n.tag), [
    'levita-culto-2026-11-22_1900',
    'levita-pedido-u1',
    'levita-chat',
  ]);
});

// ── O toque leva à tela certa ───────────────────────────────────────────────
//
// O app não tem endereço por tela (o `setUrlStrategy(null)` tirou isso para o
// gesto de voltar não sair do app). Então são dois caminhos: recado para a
// página, quando o app está aberto; marca no endereço, quando está fechado.

test('app aberto: o toque pede a tela Membros para a página', async () => {
  const recados = [];
  const sw = montarSw({
    clientes: [{
      url: 'https://exemplo.app/',
      focus: () => Promise.resolve(),
      postMessage: (m) => recados.push(m),
    }],
  });
  await sw.toque({ abrir: 'membros' });
  assert.deepEqual(recados, [{ tipo: 'ABRIR', onde: 'membros', cultoId: '' }]);
  assert.deepEqual(sw.janelasAbertas, []);
});

test('app fechado: abre com ?abrir=membros', async () => {
  const sw = montarSw({ clientes: [] });
  await sw.toque({ abrir: 'membros' });
  assert.deepEqual(sw.janelasAbertas, ['https://exemplo.app/?abrir=membros']);
});

test('o culto continua levando o id junto', async () => {
  const sw = montarSw({ clientes: [] });
  await sw.toque({ abrir: 'culto', cultoId: '2026-11-22_1900' });
  assert.deepEqual(sw.janelasAbertas,
    ['https://exemplo.app/?abrir=culto&culto=2026-11-22_1900']);
});

test('aviso sem destino cai no Chat, como antes', async () => {
  const sw = montarSw({ clientes: [] });
  await sw.toque({});
  assert.deepEqual(sw.janelasAbertas, ['https://exemplo.app/?abrir=chat']);
});

test('destino inventado não vira endereço estranho', async () => {
  // Documento mexido à mão, ou uma versão futura do Worker mandando algo que
  // este service worker não conhece: cair no Chat é melhor que abrir
  // `?abrir=<lixo>` e deixar a pessoa numa tela em branco.
  const sw = montarSw({ clientes: [] });
  await sw.toque({ abrir: 'qualquercoisa' });
  assert.deepEqual(sw.janelasAbertas, ['https://exemplo.app/?abrir=chat']);
});

test('push com corpo ilegível ainda mostra alguma coisa', async () => {
  // O navegador exige uma notificação visível para cada push; não mostrar
  // nada faz ele descadastrar o aparelho por abuso — o aparelho pararia de
  // receber aviso para sempre, sem nada na tela.
  const sw = montarSw();
  await sw.push('corpoQuebrado');
  assert.equal(sw.notificacoes.length, 1);
  assert.equal(sw.notificacoes[0].title, 'LevitaSync');
});

test('push com corpo `null` não derruba o service worker', async () => {
  // `null` é JSON válido: o `json()` não lança, devolve null. Sem o `?? {}`
  // no `sw.js`, ler o título lançaria aqui — e era este teste que achava.
  const sw = montarSw();
  await sw.push(null);
  assert.equal(sw.notificacoes.length, 1);
  assert.equal(sw.notificacoes[0].title, 'LevitaSync');
});
