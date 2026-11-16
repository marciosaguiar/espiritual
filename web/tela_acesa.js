// Manter a tela acesa durante o culto.
//
// POR QUE ISTO É JAVASCRIPT
//
// É a Screen Wake Lock API do navegador. No iPhone ela funciona em PWA
// instalado a partir do iOS 18.4; antes disso o pedido é recusado mesmo
// existindo (era um defeito do WebKit, corrigido naquela versão). Então o
// app precisa saber a diferença entre "não existe", "recusou" e "está
// acesa" — para poder dizer à pessoa, no iPhone antigo, que ponha o
// Bloqueio Automático em "Nunca". Pedir e ficar quieto deixaria a tela
// apagando no meio da música sem ninguém entender.
//
// E A PARTE QUE SE ESQUECE: o navegador SOLTA a trava sozinho quando a
// página sai de vista. Voltar ao app sem pedir de novo deixa a tela
// apagando — exatamente no caso de quem atendeu uma mensagem no meio do
// culto e voltou.

(function () {
  'use strict';

  var trava = null;
  var querAcesa = false;

  function temSuporte() {
    return !!(navigator.wakeLock && navigator.wakeLock.request);
  }

  function pedir() {
    if (!querAcesa || !temSuporte() || trava) return Promise.resolve('ok');
    return navigator.wakeLock.request('screen').then(function (t) {
      trava = t;
      t.addEventListener('release', function () { trava = null; });
      return 'ok';
    }).catch(function (e) {
      trava = null;
      var nome = (e && e.name) || '';
      // NotAllowedError é o iPhone antes do 18.4, em app instalado.
      return nome === 'NotAllowedError' ? 'negado' : 'erro';
    });
  }

  window.levitaManterTelaAcesa = function () {
    if (!temSuporte()) return Promise.resolve('sem-suporte');
    querAcesa = true;
    return pedir();
  };

  window.levitaSoltarTela = function () {
    querAcesa = false;
    if (trava) {
      try { trava.release(); } catch (e) { /* já soltou */ }
      trava = null;
    }
  };

  window.levitaTelaEstaAcesa = function () { return !!trava; };

  // Volta a pedir quando o app reaparece: o navegador soltou a trava ao
  // esconder a página, e sem isto a tela apagaria no meio da música.
  document.addEventListener('visibilitychange', function () {
    if (document.visibilityState === 'visible') pedir();
  });
})();
