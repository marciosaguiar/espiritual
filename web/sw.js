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

// O que NÃO vale guardar, decidido aqui e não só na publicação: a lista do
// build é a que a publicação carimba, e uma regra errada lá custa uma
// publicação inteira para corrigir.
//
// MEDIDO: o carimbo punha 42 arquivos e 21 MB no cache — as duas versões do
// canvaskit (6,9 MB e 5,5 MB), os arquivos `.symbols` (nomes de função, só
// servem a quem depura) e o `wimp`. No celular, isso ia pela mesma linha que
// o app usava para abrir pela primeira vez.
//
// O Flutter usa UMA das versões do canvaskit, escolhida pelo navegador: a
// "chromium" onde existem `Intl.v8BreakIterator` e `Intl.Segmenter` (Chrome,
// Edge), e a comum nos outros — Safari, ou seja, o iPhone, e Firefox. É a
// mesma conta do `flutter.js`; se um dia ela divergir, o que falta vem da
// rede na primeira vez e é guardado depois, como qualquer outro arquivo.
function usaCanvaskitChromium() {
  try {
    return typeof Intl.v8BreakIterator !== 'undefined' &&
        typeof Intl.Segmenter !== 'undefined';
  } catch (_) {
    return false;
  }
}

const NUNCA_GUARDAR = new RegExp(
  '\\.symbols$' +
  '|^canvaskit/wimp' +
  (usaCanvaskitChromium()
    ? '|^canvaskit/canvaskit\\.(js|wasm)$'
    : '|^canvaskit/chromium/'));

const ESQUELETO = (self.LISTA_DO_BUILD ||
    ['./', 'index.html', 'flutter_bootstrap.js', 'main.dart.js'])
    .filter((caminho) => !NUNCA_GUARDAR.test(caminho));

// ── O SDK do Firebase, que mora fora do nosso domínio ───────────────────────
//
// O Flutter carrega o SDK do Firebase de www.gstatic.com na hora de ligar o
// banco. Ele NÃO é do nosso domínio, então o cache acima nunca o guardou — e
// sem ele o app não liga o Firebase, o que sem internet transformava a
// abertura numa tela de erro. Dependia do cache comum do navegador, que o
// iPhone esvazia quando quer.
//
// Cada arquivo tem a VERSÃO no endereço, então nunca muda: o cache é
// "primeiro o cache, rede só se faltar", e fica numa caixa à parte, que a
// troca de versão do app não apaga. A versão é a do `firebase_core_web` do
// `pubspec.lock`; um teste confere que `index.html`, este arquivo e o lock
// dizem a mesma coisa.
const VERSAO_DO_SDK = '10.11.1';
const ORIGEM_DO_SDK = `https://www.gstatic.com/firebasejs/${VERSAO_DO_SDK}/`;
const CACHE_DO_SDK = `sdk-firebase-${VERSAO_DO_SDK}`;
const ARQUIVOS_DO_SDK = ['firebase-app.js', 'firebase-auth.js', 'firebase-firestore.js']
    .map((a) => ORIGEM_DO_SDK + a);

function ehSdkDoFirebase(pedido) {
  return pedido.method === 'GET' && pedido.url.startsWith(ORIGEM_DO_SDK);
}

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

      // O SDK do Firebase (ver acima): sem desistir se um falhar, e sem
      // refazer o que já está guardado.
      try {
        const sdk = await caches.open(CACHE_DO_SDK);
        await Promise.allSettled(ARQUIVOS_DO_SDK.map(async (url) => {
          if (await sdk.match(url)) return;
          const r = await fetch(url, { mode: 'cors' });
          if (r.ok) await sdk.put(url, r);
        }));
      } catch (_) {
        // Sem o SDK no cache hoje; a primeira abertura com rede o guarda.
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
        nomes.filter((n) =>
                (n.startsWith('levitasync-') && n !== CACHE) ||
                // Versão antiga do SDK; a atual NÃO sai com a versão do app.
                (n.startsWith('sdk-firebase-') && n !== CACHE_DO_SDK))
             .map((n) => caches.delete(n)),
      );
      await self.clients.claim();
    })(),
  );
});

// ── Avisos do chat ──────────────────────────────────────────────────────────
//
// Quem manda é o Worker da Cloudflare (ver `worker/`), porque aviso com o app
// fechado precisa de alguém de pé — e no Firebase isso seria Cloud Function,
// que exige o plano Blaze.
//
// A etiqueta é fixa de propósito: é ela que faz várias mensagens seguidas
// virarem UM aviso que se atualiza, em vez de empilhar cinco na tela.

const ETIQUETA = 'levita-chat';

self.addEventListener('push', (evento) => {
  evento.waitUntil((async () => {
    let dados = {};
    try {
      // O `?? {}` não é enfeite: um push cujo corpo seja exatamente `null` é
      // JSON válido, e `json()` devolve `null` — aí ler `dados.titulo`
      // lançaria, nenhuma notificação apareceria, e o navegador
      // descadastraria o aparelho por abuso. O aparelho pararia de receber
      // aviso para sempre, sem nada na tela.
      dados = (evento.data ? evento.data.json() : null) ?? {};
    } catch (_) {
      // Aviso sem corpo legível ainda tem de aparecer: o navegador exige
      // uma notificação visível para cada push, e não mostrar nada faria o
      // navegador descadastrar o aparelho por abuso.
    }

    const titulo = dados.titulo || 'LevitaSync';
    const corpo = dados.corpo || 'Mensagem nova no chat';
    const abrir = (dados.abrir === 'culto' || dados.abrir === 'membros')
      ? dados.abrir
      : 'chat';
    const cultoId = typeof dados.cultoId === 'string' ? dados.cultoId : '';

    // Aviso de CULTO não se junta com o do chat: "você foi escalado" e o
    // lembrete da véspera não são "mais uma mensagem", e somá-los na mesma
    // contagem esconderia justamente o que importa. Etiqueta por culto, para
    // o lembrete substituir o "foi escalado" do mesmo culto em vez de
    // empilhar dois.
    //
    // Quem manda a etiqueta pode ser o Worker: "novo pedido de entrada" usa
    // uma por pessoa, para dois cadastros no mesmo dia serem dois avisos na
    // tela em vez de um apagando o outro — perder um nome ali é perder o
    // pedido de alguém.
    const etiqueta = (typeof dados.etiqueta === 'string' && dados.etiqueta)
      ? dados.etiqueta
      : (abrir === 'culto' ? `levita-culto-${cultoId}` : ETIQUETA);

    // Quantas já estão na tela sem ninguém ter visto? (Só no chat.)
    let quantas = 1;
    if (!dados.teste && abrir === 'chat') {
      try {
        const abertas = await self.registration.getNotifications({ tag: ETIQUETA });
        for (const n of abertas) quantas += (n.data && n.data.quantas) || 1;
      } catch (_) {
        // Safari antigo não lista as abertas: cai no aviso simples.
      }
    }

    await self.registration.showNotification(
      quantas > 1 ? `${quantas} mensagens novas` : titulo,
      {
        body: quantas > 1 ? `${titulo}: ${corpo}` : corpo,
        tag: etiqueta,
        // Sem isto, o aviso atualizado trocaria o texto em silêncio e a
        // pessoa não saberia que chegou mais uma.
        renotify: true,
        icon: 'icons/Icon-192.png',
        badge: 'icons/Icon-192.png',
        data: { quantas, abrir, cultoId },
      },
    );
  })());
});

self.addEventListener('notificationclick', (evento) => {
  evento.notification.close();
  const dados = evento.notification.data || {};
  const onde = (dados.abrir === 'culto' || dados.abrir === 'membros')
    ? dados.abrir
    : 'chat';
  const cultoId = typeof dados.cultoId === 'string' ? dados.cultoId : '';

  evento.waitUntil((async () => {
    const abertos = await self.clients.matchAll({
      type: 'window', includeUncontrolled: true,
    });
    // App aberto: foca e PEDE a tela. Não dá para navegar até ela — o app
    // não tem endereço por tela (ver `setUrlStrategy(null)`).
    for (const cliente of abertos) {
      if (cliente.url.startsWith(self.registration.scope)) {
        await cliente.focus();
        cliente.postMessage({ tipo: 'ABRIR', onde: onde, cultoId: cultoId });
        return;
      }
    }
    // App fechado: abre com a marca no endereço, que o `avisos.js` lê e
    // apaga assim que o Flutter sobe.
    const marca = onde === 'culto' && cultoId
      ? `?abrir=culto&culto=${encodeURIComponent(cultoId)}`
      : `?abrir=${onde === 'membros' ? 'membros' : 'chat'}`;
    await self.clients.openWindow(`${self.registration.scope}${marca}`);
  })());
});

// O navegador pode trocar a inscrição sozinho (atualização, limpeza).
//
// Aqui não há como gravar a inscrição nova no Firestore: o service worker
// não tem o login da pessoa. Então o que se faz é reinscrever para os avisos
// não pararem, e o app regrava o registro na próxima abertura — ele confere
// a inscrição toda vez que abre, justamente por isto. O iOS não dispara este
// evento; lá a conferência na abertura é o único caminho.
self.addEventListener('pushsubscriptionchange', (evento) => {
  evento.waitUntil((async () => {
    try {
      const chave = evento.oldSubscription?.options?.applicationServerKey;
      if (!chave) return;
      await self.registration.pushManager.subscribe({
        userVisibleOnly: true,
        applicationServerKey: chave,
      });
    } catch (e) {
      console.warn('[sw] não reinscreveu:', e);
    }
  })());
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

  // O SDK do Firebase: do cache, e da rede só se faltar.
  if (ehSdkDoFirebase(pedido)) {
    evento.respondWith((async () => {
      const cache = await caches.open(CACHE_DO_SDK);
      const guardado = await cache.match(pedido.url);
      if (guardado) return guardado;
      const resposta = await fetch(pedido);
      // Só resposta completa e boa: uma parcial no cache quebraria o app
      // para sempre, porque o cache vem ANTES da rede.
      if (resposta.ok && resposta.status === 200) {
        cache.put(pedido.url, resposta.clone()).catch(() => {});
      }
      return resposta;
    })());
    return;
  }

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
