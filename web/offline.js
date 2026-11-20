// Armazém local e estado da rede, para o app funcionar sem internet.
//
// POR QUE ISTO É JAVASCRIPT E NÃO UM PACOTE
//
// O Flutter na web guarda preferências em `localStorage`, que tem ~5 MB e é
// síncrono. A fila de envio, as cópias das músicas e os áudios do chat não
// cabem ali. IndexedDB cabe, e é o mesmo lugar que o Firestore e o login do
// Firebase já usam — então se o navegador apagar um, quase sempre apaga todos,
// e é isso que o app confere ao abrir (ver `memoria_do_aparelho.dart`).
//
// Tudo aqui devolve promessas que NUNCA rejeitam: quem chama do Dart trata
// "não consegui" como valor (nulo ou falso), porque um armazém que falha não
// pode derrubar uma tela.
'use strict';

(function () {
  var NOME = 'levita-armazem';
  var LOJA = 'kv';
  var abrindo = null;

  function abrir() {
    if (abrindo) return abrindo;
    abrindo = new Promise(function (ok, falhou) {
      try {
        var r = indexedDB.open(NOME, 1);
        r.onupgradeneeded = function () { r.result.createObjectStore(LOJA); };
        r.onsuccess = function () { ok(r.result); };
        r.onerror = function () { abrindo = null; falhou(r.error); };
        r.onblocked = function () { abrindo = null; falhou(new Error('bloqueado')); };
      } catch (e) { abrindo = null; falhou(e); }
    });
    return abrindo;
  }

  function transacao(modo, usar) {
    return abrir().then(function (db) {
      return new Promise(function (ok, falhou) {
        var t = db.transaction(LOJA, modo);
        var req = usar(t.objectStore(LOJA));
        t.oncomplete = function () { ok(req ? req.result : null); };
        t.onerror = function () { falhou(t.error); };
        t.onabort = function () { falhou(t.error || new Error('abortada')); };
      });
    });
  }

  window.levitaArmazemLer = function (chave) {
    return transacao('readonly', function (l) { return l.get(chave); })
      .then(function (v) { return v === undefined ? null : v; })
      .catch(function () { return null; });
  };

  window.levitaArmazemGravar = function (chave, texto) {
    return transacao('readwrite', function (l) { return l.put(texto, chave); })
      .then(function () { return true; })
      .catch(function () { return false; });
  };

  window.levitaArmazemApagar = function (chave) {
    return transacao('readwrite', function (l) { return l.delete(chave); })
      .then(function () { return true; })
      .catch(function () { return false; });
  };

  // As chaves que começam com [prefixo], como um JSON de lista.
  window.levitaArmazemChaves = function (prefixo) {
    return transacao('readonly', function (l) { return l.getAllKeys(); })
      .then(function (todas) {
        return JSON.stringify((todas || []).filter(function (k) {
          return typeof k === 'string' && k.indexOf(prefixo) === 0;
        }));
      })
      .catch(function () { return '[]'; });
  };

  // Quanto o navegador diz que o app usa e quanto deixa usar.
  window.levitaArmazemEstimativa = function () {
    try {
      if (navigator.storage && navigator.storage.estimate) {
        return navigator.storage.estimate()
          .then(function (e) { return JSON.stringify({ usado: e.usage || 0, cota: e.quota || 0 }); })
          .catch(function () { return ''; });
      }
    } catch (e) { /* cai no vazio */ }
    return Promise.resolve('');
  };

  // Pede ao navegador para NÃO apagar os dados do site quando faltar espaço.
  // Sem pergunta na tela: o Safari decide sozinho (e costuma conceder ao app
  // instalado na tela de início). Falso não é erro — só quer dizer que o
  // navegador pode apagar, e o app vai perceber e baixar de novo.
  window.levitaArmazemPersistir = function () {
    try {
      if (navigator.storage && navigator.storage.persist) {
        return navigator.storage.persist().then(function (v) { return !!v; }).catch(function () { return false; });
      }
    } catch (e) { /* cai no falso */ }
    return Promise.resolve(false);
  };

  // O service worker já assumiu esta página? Só um arquivo que passa por ELE
  // fica guardado no aparelho — e o service worker se registra depois do
  // primeiro quadro, então os primeiros segundos de uma instalação nova ainda
  // são sem ele. A preparação da Bíblia espera isto: baixar 4 MB antes e
  // achar que ficou guardado seria dizer "pronto para o culto" sem estar.
  window.levitaServicoAtivo = function () {
    try { return !!(navigator.serviceWorker && navigator.serviceWorker.controller); }
    catch (e) { return false; }
  };

  // ── Rede ──────────────────────────────────────────────────────────────
  window.levitaOnline = function () { return navigator.onLine !== false; };
  window.levitaOuvirRede = function (aviso) {
    window.addEventListener('online', function () { aviso(true); });
    window.addEventListener('offline', function () { aviso(false); });
  };
})();
