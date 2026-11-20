// Tela cheia, para projetar a letra.
//
// É a Fullscreen API do navegador. No computador é o que tira a barra de
// endereço e as abas da frente do telão; no iPhone, o Safari só a tem em vídeo
// — e lá a pessoa já abre o app instalado, sem barra nenhuma. Por isso o app
// precisa distinguir "não existe" de "recusou": quem projeta de um navegador
// que não deixa precisa ouvir "aperte F11", em vez de um botão que não faz
// nada.

(function () {
  'use strict';

  function raiz() {
    return document.documentElement;
  }

  window.levitaTelaCheiaExiste = function () {
    return !!(document.fullscreenEnabled && raiz().requestFullscreen);
  };

  window.levitaEmTelaCheia = function () {
    return !!document.fullscreenElement;
  };

  // Devolve 'entrou', 'saiu', 'negado' ou 'sem-suporte'.
  window.levitaAlternarTelaCheia = function () {
    if (document.fullscreenElement) {
      return document.exitFullscreen().then(function () {
        return 'saiu';
      }).catch(function () {
        return 'saiu';
      });
    }
    if (!window.levitaTelaCheiaExiste()) return Promise.resolve('sem-suporte');
    return raiz().requestFullscreen().then(function () {
      return 'entrou';
    }).catch(function () {
      return 'negado';
    });
  };

  window.levitaSairDaTelaCheia = function () {
    if (document.fullscreenElement) {
      try {
        document.exitFullscreen();
      } catch (e) {
        // Já saiu.
      }
    }
  };
})();
