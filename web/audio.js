// Gravar e tocar mensagens de voz.
//
// POR QUE ISTO É JAVASCRIPT, E NÃO DART
//
// Gravar som no navegador é `MediaRecorder`, e tocar é um `<audio>`. O
// Flutter web não traz nenhum dos dois: traria um pacote com configuração
// nativa de Android e iOS para resolver algo que o navegador já faz. Aqui
// vale a mesma escolha que já se fez para detectar PWA e para compartilhar:
// um arquivo de JavaScript e uma importação condicional no Dart.
//
// O FORMATO, QUE É A PARTE QUE DÁ ERRADO
//
// Um áudio gravado num aparelho é ouvido em outro. O iPhone grava em
// mp4/AAC, que toca em tudo. O Android costumava só gravar webm/opus, que
// iPhone com iOS abaixo de 18.4 NÃO toca. Então aqui se pede AAC pelo nome,
// e o formato de verdade viaja junto do áudio: quem for ouvir pergunta ao
// próprio navegador se aquilo toca, e a bolha diz que não toca em vez de
// mostrar um play mudo.
//
// PEDIR "audio/mp4" E CONFERIR SÃO COISAS DIFERENTES. Medido num Chromium:
// `isTypeSupported('audio/mp4')` responde que sim, e o MediaRecorder entrega
// `audio/mp4;codecs=opus` — contêiner da Apple com som que a Apple não toca.
// É o pior caso possível: no iPhone, perguntar só pelo contêiner ("mp4, sei
// tocar") daria um play mudo. Por isso o AAC é pedido pelo nome primeiro,
// webm/opus vem ANTES do mp4 solto (webm/opus pelo menos se anuncia pelo que
// é), e `levitaPodeTocar` NÃO joga fora o `;codecs=` antes de perguntar.

(function () {
  'use strict';

  // 32 kbps mono: é voz, não música. Dois minutos dão ~469 KiB, e o
  // documento do Firestore vai até 1 MiB.
  var BITS_POR_SEGUNDO = 32000;
  var LIMITE_MS = 120000;

  var gravador = null;
  var pedacos = [];
  var comecouEm = 0;
  var trilha = null;
  var pararNoTempo = null;

  /// O melhor formato que este aparelho grava, ou null se não grava nenhum.
  function melhorFormato() {
    if (typeof MediaRecorder === 'undefined') return null;
    var candidatos = [
      'audio/mp4;codecs=mp4a.40.2', // AAC: é o único que toca em TUDO
      'audio/webm;codecs=opus',     // honesto: quem não toca, sabe que não
      'audio/mp4',                  // iPhone, que só reconhece o nome curto
      'audio/webm',
    ];
    for (var i = 0; i < candidatos.length; i++) {
      if (MediaRecorder.isTypeSupported(candidatos[i])) return candidatos[i];
    }
    return null;
  }

  window.levitaAudioSuportado = function () {
    return !!(navigator.mediaDevices &&
      navigator.mediaDevices.getUserMedia && melhorFormato());
  };

  /// Este aparelho toca este formato? Vazio ou "no" significa que não.
  ///
  /// Pergunta pelo tipo INTEIRO, com o `;codecs=`. Tirar o codec para
  /// "não dar falso negativo" era o que transformava um mp4/opus — que o
  /// iPhone não toca — num play mudo. Melhor um "não toca neste aparelho"
  /// de vez em quando injusto do que um botão que não faz nada.
  window.levitaPodeTocar = function (tipo) {
    if (!tipo) return true;
    try {
      return !!document.createElement('audio').canPlayType(tipo);
    } catch (e) {
      return true; // na dúvida, deixa tentar: o pior é não sair som.
    }
  };

  /// Começa a gravar. Devolve 'ok', 'sem-permissao', 'sem-suporte' ou 'erro'.
  ///
  /// A permissão do microfone é pedida aqui, no primeiro toque do botão —
  /// nunca na abertura do app, onde a pessoa não faz ideia do porquê.
  window.levitaGravarIniciar = function () {
    var formato = melhorFormato();
    if (!formato || !navigator.mediaDevices) {
      return Promise.resolve('sem-suporte');
    }
    return navigator.mediaDevices.getUserMedia({
      audio: {
        channelCount: 1,
        echoCancellation: true,
        noiseSuppression: true,
        autoGainControl: true,
      },
    }).then(function (stream) {
      trilha = stream;
      pedacos = [];
      gravador = new MediaRecorder(stream, {
        mimeType: formato,
        audioBitsPerSecond: BITS_POR_SEGUNDO,
      });
      gravador.ondataavailable = function (e) {
        if (e.data && e.data.size > 0) pedacos.push(e.data);
      };
      gravador.start();
      comecouEm = Date.now();
      // Trava de dois minutos: para sozinho, e o que foi gravado até ali
      // vale. Melhor do que descartar o áudio inteiro por passar do tempo.
      pararNoTempo = setTimeout(function () {
        if (gravador && gravador.state === 'recording') gravador.stop();
      }, LIMITE_MS);
      return 'ok';
    }).catch(function (e) {
      var nome = (e && e.name) || '';
      if (nome === 'NotAllowedError' || nome === 'SecurityError') {
        return 'sem-permissao';
      }
      return 'erro';
    });
  };

  window.levitaGravandoMs = function () {
    if (!gravador || gravador.state === 'inactive') return 0;
    return Date.now() - comecouEm;
  };

  function soltarMicrofone() {
    if (pararNoTempo) { clearTimeout(pararNoTempo); pararNoTempo = null; }
    if (trilha) {
      trilha.getTracks().forEach(function (t) { t.stop(); });
      trilha = null;
    }
  }

  /// Para e devolve `{ base64, tipo, duracaoMs }`, ou null se não deu.
  window.levitaGravarParar = function () {
    if (!gravador) return Promise.resolve(null);
    var duracao = Date.now() - comecouEm;
    var tipo = gravador.mimeType || melhorFormato();

    return new Promise(function (resolve) {
      gravador.onstop = function () {
        soltarMicrofone();
        var partes = pedacos;
        pedacos = [];
        gravador = null;
        if (!partes.length) { resolve(null); return; }

        var blob = new Blob(partes, { type: tipo });
        var leitor = new FileReader();
        leitor.onloadend = function () {
          // O resultado vem como "data:audio/mp4;base64,AAA…"; o Dart só
          // quer o depois da vírgula.
          var texto = String(leitor.result || '');
          var virgula = texto.indexOf(',');
          resolve({
            base64: virgula >= 0 ? texto.slice(virgula + 1) : '',
            tipo: tipo,
            duracaoMs: duracao,
          });
        };
        leitor.onerror = function () { resolve(null); };
        leitor.readAsDataURL(blob);
      };
      if (gravador.state === 'recording') gravador.stop();
      else { soltarMicrofone(); resolve(null); }
    });
  };

  /// Joga fora o que estava gravando. É o arrastar para o lado.
  window.levitaGravarCancelar = function () {
    if (gravador && gravador.state === 'recording') {
      gravador.onstop = null;
      try { gravador.stop(); } catch (e) { /* já parado */ }
    }
    pedacos = [];
    gravador = null;
    soltarMicrofone();
  };

  // ── Tocar ────────────────────────────────────────────────────────────────
  //
  // Um elemento só, reaproveitado. É o que faz tocar um áudio parar o outro
  // sem nenhuma coordenação: só existe um.

  var tocador = null;
  var tocandoId = '';
  var urlAtual = '';
  // Quem deu erro ao DECODIFICAR. `canPlayType` acerta quase sempre, mas um
  // "maybe" é literalmente um talvez: o erro de verdade só aparece aqui, e
  // sem isto a bolha ficaria com o play parado, sem som e sem explicação.
  var falhouId = '';

  function garantirTocador() {
    if (!tocador) {
      tocador = new Audio();
      tocador.preload = 'auto';
    }
    return tocador;
  }

  function limparUrl() {
    if (urlAtual) { URL.revokeObjectURL(urlAtual); urlAtual = ''; }
  }

  /// Toca os bytes recebidos. Devolve false quando este aparelho não dá
  /// conta do formato — e aí a bolha diz isso, em vez de ficar muda.
  window.levitaTocar = function (id, base64, tipo) {
    if (!window.levitaPodeTocar(tipo)) {
      falhouId = id;
      return Promise.resolve(false);
    }
    try {
      var cru = atob(base64);
      var bytes = new Uint8Array(cru.length);
      for (var i = 0; i < cru.length; i++) bytes[i] = cru.charCodeAt(i);

      var a = garantirTocador();
      a.pause();
      limparUrl();
      urlAtual = URL.createObjectURL(new Blob([bytes], { type: tipo }));
      a.src = urlAtual;
      tocandoId = id;
      falhouId = '';
      a.onended = function () { tocandoId = ''; };
      a.onerror = function () { falhouId = id; tocandoId = ''; };
      return a.play().then(function () { return true; })
        .catch(function () { falhouId = id; tocandoId = ''; return false; });
    } catch (e) {
      falhouId = id;
      return Promise.resolve(false);
    }
  };

  window.levitaPausar = function () {
    if (tocador) tocador.pause();
  };

  window.levitaRetomar = function () {
    if (tocador && tocador.src) tocador.play().catch(function () {});
  };

  /// Quem está tocando e onde, para a barra de progresso.
  window.levitaEstadoAudio = function () {
    var a = tocador;
    if (!a || !tocandoId) {
      return JSON.stringify(
        { id: '', tocando: false, posicaoMs: 0, falhou: falhouId });
    }
    return JSON.stringify({
      id: tocandoId,
      tocando: !a.paused && !a.ended,
      posicaoMs: Math.round((a.currentTime || 0) * 1000),
      falhou: falhouId,
    });
  };
})();
