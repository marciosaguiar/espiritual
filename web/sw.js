// Service worker do LevitaSync.
//
// POR QUE ESTE ARQUIVO EXISTE
//
// O Flutter tinha um service worker que guardava o app no aparelho. As
// versões novas não têm mais: o `flutter_service_worker.js` que elas geram
// é um arquivo de 784 bytes que só se desregistra. O app continuou
// funcionando, então ninguém percebeu — mas passou a baixar tudo de novo a
// cada abertura. Medido no app no ar: 3,26 MB por carga fria (1,49 MB de
// canvaskit.wasm vindo do servidor do Google, 1,01 MB de main.dart.js), e
// 2,5 s até desenhar a primeira tela numa conexão de datacenter. No 4G de um
// celular, os ~5 s que o Márcio via toda vez que voltava ao app.
//
// Este arquivo devolve esse cache, e é nosso: não some na próxima mudança do
// Flutter.
//
// COMO FUNCIONA
//
// · Na instalação, guarda o esqueleto do app (a página, o carregador, o
//   código Dart, o canvaskit e as fontes).
// · Serve do cache primeiro e confere a rede depois, em segundo plano. É o
//   que faz a abertura ser imediata mesmo sem internet.
// · O cache é versionado. Quando o VERSAO muda, o navegador vê um arquivo
//   diferente, instala a versão nova, apaga a antiga e assume — e só então o
//   index.html recarrega a página, uma vez. Voltar para o app NÃO recarrega
//   nada.
// · Nada do Firebase passa por aqui: só o mesmo domínio e só GET. Dados são
//   sempre da rede.

'use strict';

// A versão e a lista de arquivos são postas na frente deste arquivo pelo
// GitHub Actions, a partir do que o build realmente gerou (ver
// .github/workflows/web-preview.yml).
//
// Escrever a lista à mão aqui não serviria: os nomes mudam entre versões do
// Flutter — foi tentado, e o app não abria sem internet porque o
// canvaskit.wasm tinha ficado de fora. A lista tem de vir do build.
const VERSAO = self.VERSAO_DO_BUILD || 'desenvolvimento';
const CACHE = `levitasync-${VERSAO}`;

const ESQUELETO = self.LISTA_DO_BUILD ||
    ['./', 'index.html', 'flutter_bootstrap.js', 'main.dart.js'];

self.addEventListener('install', (evento) => {
  // Nada de `skipWaiting()` aqui. Assumir na instalação trocaria o código
  // debaixo de quem está usando o app — alguém no meio do culto, com a
  // cifra aberta. A versão nova espera, e a pessoa decide quando entrar.
  evento.waitUntil(
    (async () => {
      const cache = await caches.open(CACHE);
      // Um a um, e sem desistir no primeiro erro: se um arquivo sumir numa
      // versão futura do Flutter, o app fica sem ESSE arquivo no cache, não
      // sem cache nenhum. `addAll` faria o contrário.
      const resultados = await Promise.allSettled(
        ESQUELETO.map((caminho) => cache.add(caminho)),
      );
      const falhas = resultados.filter((r) => r.status === 'rejected').length;
      if (falhas) {
        console.warn(`[sw] ${falhas} de ${ESQUELETO.length} arquivos não foram guardados`);
      }
    })(),
  );
});

// A página pede para esta versão assumir AGORA.
//
// Sem isto, uma versão nova fica esperando a antiga soltar o controle — e no
// iPhone, onde o app instalado raramente é encerrado de verdade, ela podia
// esperar dias. Era o "saí e entrei três vezes e continua a versão velha".
// Quem decide o momento é a pessoa, pela faixa "Nova versão disponível".
self.addEventListener('message', (evento) => {
  if (evento.data && evento.data.tipo === 'ATUALIZAR') self.skipWaiting();
});

self.addEventListener('activate', (evento) => {
  evento.waitUntil(
    (async () => {
      const nomes = await caches.keys();
      await Promise.all(
        nomes.filter((n) => n.startsWith('levitasync-') && n !== CACHE)
             .map((n) => caches.delete(n)),
      );
      await self.clients.claim();
    })(),
  );
});

/// Vale a pena guardar? Só o que é nosso, só GET, e nada de Firebase.
function guardavel(pedido) {
  if (pedido.method !== 'GET') return false;
  const url = new URL(pedido.url);
  if (url.origin !== self.location.origin) return false;
  // A página em si é tratada à parte (ver abaixo).
  return true;
}

self.addEventListener('fetch', (evento) => {
  const pedido = evento.request;
  if (!guardavel(pedido)) return;

  // Abrir o app: serve a página guardada na hora. É isto que faz o app
  // instalado abrir sem esperar a rede.
  if (pedido.mode === 'navigate') {
    evento.respondWith(
      (async () => {
        const cache = await caches.open(CACHE);
        const guardada = await cache.match('index.html');
        if (guardada) {
          // Confere se há versão nova, sem segurar a tela.
          fetch(pedido)
            .then((r) => r.ok && cache.put('index.html', r.clone()))
            .catch(() => {});
          return guardada;
        }
        return fetch(pedido);
      })(),
    );
    return;
  }

  evento.respondWith(
    (async () => {
      const cache = await caches.open(CACHE);
      const guardado = await cache.match(pedido);

      const daRede = fetch(pedido)
        .then((resposta) => {
          // `basic` = mesma origem e resposta completa. Resposta parcial
          // (206) ou opaca não pode ir para o cache.
          if (resposta.ok && resposta.type === 'basic') {
            cache.put(pedido, resposta.clone()).catch(() => {});
          }
          return resposta;
        })
        .catch(() => null);

      if (guardado) return guardado;

      const resposta = await daRede;
      if (resposta) return resposta;
      return new Response('', { status: 504, statusText: 'sem rede' });
    })(),
  );
});
