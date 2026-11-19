// Inscrever o aparelho para receber avisos, e abrir o Chat quando a pessoa
// toca na notificação.
//
// POR QUE ISTO É JAVASCRIPT
//
// A inscrição é `registration.pushManager.subscribe()`, do navegador. O
// mesmo motivo do `audio.js`: um pacote Flutter aqui pediria configuração
// nativa de Android e iOS para fazer o que o navegador já faz.
//
// A PERMISSÃO SÓ SE PEDE NUM TOQUE
//
// O iPhone exige um gesto da pessoa para abrir a caixa de permissão —
// pedir na abertura do app simplesmente não funciona lá. E mesmo onde
// funciona, pedir antes de explicar é o jeito de a pessoa negar para
// sempre: negado não se pergunta de novo, nem reinstalando o app.

(function () {
  'use strict';

  function b64urlParaBytes(texto) {
    var s = String(texto).replace(/-/g, '+').replace(/_/g, '/');
    var cru = atob(s + '='.repeat((4 - (s.length % 4)) % 4));
    var bytes = new Uint8Array(cru.length);
    for (var i = 0; i < cru.length; i++) bytes[i] = cru.charCodeAt(i);
    return bytes;
  }

  function bytesParaB64url(buffer) {
    var b = new Uint8Array(buffer);
    var s = '';
    for (var i = 0; i < b.length; i++) s += String.fromCharCode(b[i]);
    return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  }

  /// Este aparelho sabe receber aviso?
  ///
  /// No iPhone, `PushManager` só existe quando o app está instalado na tela
  /// de início — num Safari comum ele não aparece. É isso que o app usa para
  /// mostrar o passo a passo de instalar em vez do botão.
  window.levitaAvisosSuportados = function () {
    return !!('serviceWorker' in navigator && 'PushManager' in window &&
      'Notification' in window);
  };

  /// 'granted', 'denied' ou 'default'. Em aparelho sem suporte: 'sem-suporte'.
  window.levitaPermissaoDeAvisos = function () {
    if (!window.levitaAvisosSuportados()) return 'sem-suporte';
    try {
      return Notification.permission;
    } catch (e) {
      return 'sem-suporte';
    }
  };

  function comoInscricao(sub) {
    if (!sub) return null;
    var p = sub.getKey ? sub.getKey('p256dh') : null;
    var a = sub.getKey ? sub.getKey('auth') : null;
    if (!p || !a) return null;
    return JSON.stringify({
      endpoint: sub.endpoint,
      p256dh: bytesParaB64url(p),
      auth: bytesParaB64url(a),
    });
  }

  /// A inscrição que já existe neste aparelho, ou null.
  window.levitaInscricaoAtual = function () {
    if (!window.levitaAvisosSuportados()) return Promise.resolve(null);
    return navigator.serviceWorker.ready
      .then(function (reg) { return reg.pushManager.getSubscription(); })
      .then(comoInscricao)
      .catch(function () { return null; });
  };

  /// Pede a permissão e inscreve. Chamar SÓ de dentro de um toque.
  ///
  /// Devolve o JSON da inscrição, ou uma das palavras:
  /// 'sem-suporte', 'negado', 'erro'.
  window.levitaInscrever = function (chavePublica) {
    if (!window.levitaAvisosSuportados()) return Promise.resolve('sem-suporte');

    return Notification.requestPermission().then(function (resposta) {
      if (resposta !== 'granted') return 'negado';
      return navigator.serviceWorker.ready.then(function (reg) {
        return reg.pushManager.getSubscription().then(function (velha) {
          // Se a chave do servidor mudou, a inscrição antiga não serve mais:
          // os avisos sairiam assinados com uma chave que o aparelho recusa.
          if (velha) {
            var mesma = false;
            try {
              var atual = velha.options && velha.options.applicationServerKey;
              mesma = !!atual &&
                bytesParaB64url(atual) === String(chavePublica);
            } catch (e) { mesma = false; }
            if (mesma) return velha;
            return velha.unsubscribe().then(function () { return null; });
          }
          return null;
        }).then(function (reaproveitada) {
          if (reaproveitada) return reaproveitada;
          return reg.pushManager.subscribe({
            // Obrigatório em todos os navegadores: todo push TEM de virar
            // uma notificação visível. Não existe push silencioso aqui.
            userVisibleOnly: true,
            applicationServerKey: b64urlParaBytes(chavePublica),
          });
        });
      }).then(comoInscricao).then(function (j) { return j || 'erro'; });
    }).catch(function (e) {
      console.warn('[avisos] não inscreveu:', e);
      return 'erro';
    });
  };

  /// Desinscreve este aparelho. Devolve se deu.
  window.levitaDesinscrever = function () {
    if (!window.levitaAvisosSuportados()) return Promise.resolve(false);
    return navigator.serviceWorker.ready
      .then(function (reg) { return reg.pushManager.getSubscription(); })
      .then(function (sub) { return sub ? sub.unsubscribe() : true; })
      .catch(function () { return false; });
  };

  /// Chama o Worker dos avisos. Devolve `{"status":200,"corpo":"..."}`.
  ///
  /// Passa por aqui, e não por um pacote Dart, para o app não ganhar uma
  /// dependência nova por causa de um POST — é a mesma escolha do audio.js.
  // Um GET sem login. Serve à rota /saude do Worker, que não pede token de
  // propósito: quem precisa dela é um job de madrugada e um líder leigo
  // abrindo um endereço no celular.
  window.levitaBuscarJson = function (url) {
    return fetch(url).then(function (r) {
      return r.text().then(function (texto) {
        return JSON.stringify({ status: r.status, corpo: texto });
      });
    }).catch(function (e) {
      // Status 0 é "não saiu daqui": sem rede, DNS errado, CORS recusado. A
      // tela precisa distinguir isso de "o servidor respondeu que está
      // quebrado" — um é a internet da pessoa, o outro é conserto de
      // verdade.
      return JSON.stringify({ status: 0, corpo: String(e && e.message || e) });
    });
  };

  window.levitaChamarWorker = function (url, token, corpo) {
    return fetch(url, {
      method: 'POST',
      headers: {
        Authorization: 'Bearer ' + token,
        'Content-Type': 'application/json',
      },
      body: corpo,
    }).then(function (r) {
      return r.text().then(function (texto) {
        return JSON.stringify({ status: r.status, corpo: texto });
      });
    }).catch(function (e) {
      // Sem rede, DNS errado, CORS recusado: status 0 e o motivo no corpo,
      // para a tela do teste poder dizer algo melhor que "falhou".
      return JSON.stringify({ status: 0, corpo: String(e && e.message || e) });
    });
  };

  // ── Abrir o Chat ao tocar na notificação ──────────────────────────────────
  //
  // O app não tem endereço por tela: o `setUrlStrategy(null)` do `main()`
  // tirou isso de propósito, para o gesto de voltar não sair do app. Então a
  // notificação não pode "navegar" até o Chat — ela avisa, e o Flutter troca
  // de aba. São dois caminhos, porque o app pode estar aberto ou fechado:
  //
  //   aberto  → o service worker manda uma mensagem para a página;
  //   fechado → o worker abre o app com ?abrir=chat, e isto lê o endereço.

  var pedido = null;

  try {
    var params = new URL(window.location.href).searchParams;
    var onde = params.get('abrir');
    if (onde === 'chat' || onde === 'culto' || onde === 'membros') {
      pedido = { onde: onde, cultoId: params.get('culto') || '' };
      // Limpa o endereço para o pedido não se repetir se a pessoa
      // recarregar, e para o app instalado não guardar isto como sua página.
      if (window.history && window.history.replaceState) {
        window.history.replaceState(null, '', window.location.pathname);
      }
    }
  } catch (e) { /* endereço estranho: segue sem abrir nada */ }

  if ('serviceWorker' in navigator) {
    navigator.serviceWorker.addEventListener('message', function (evento) {
      var d = evento.data || {};
      if (d.tipo === 'ABRIR') {
        pedido = { onde: d.onde || 'chat', cultoId: d.cultoId || '' };
      }
      // O nome antigo, de antes do aviso de culto: um app aberto numa versão
      // velha do service worker ainda manda este.
      if (d.tipo === 'ABRIR_CHAT') pedido = { onde: 'chat', cultoId: '' };
    });
  }

  /// Alguém tocou numa notificação? Responde uma vez só.
  ///
  /// Devolve `{"onde":"chat"}` ou `{"onde":"culto","cultoId":"..."}`, ou
  /// vazio. O Flutter pergunta de vez em quando; consumir na leitura é o que
  /// impede o app de pular para a mesma tela toda vez que a pessoa sai dela.
  window.levitaPediuAbrir = function () {
    if (!pedido) return '';
    var r = JSON.stringify(pedido);
    pedido = null;
    return r;
  };
})();
