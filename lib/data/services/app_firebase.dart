import 'dart:async';

import 'package:flutter/foundation.dart';

/// Quando o Firebase termina de ligar.
///
/// O app NÃO espera o Firebase para desenhar a primeira tela. Medido na
/// rodada de 20/11/2026, `Firebase.initializeApp` é um dos maiores trechos do
/// caminho até o Início: na web, o plugin do Auth faz a inicialização esperar
/// a conferência da sessão no Google — uma ida e volta de rede — e, sem
/// internet, esperar até desistir. Tudo isso com o repertório e a escala já
/// guardados no próprio celular.
///
/// Então `main()` desenha o app e liga o Firebase em paralelo; quem precisa
/// do banco (as escutas, a conferência da sessão) espera [pronto]. Quem só
/// mostra o que o aparelho guardou não espera nada.
class AppFirebase {
  AppFirebase._();

  static Completer<String?>? _fim;
  static bool _ligado = false;

  /// Começa a ligar. [ligar] faz o trabalho; o resultado é nulo quando deu
  /// certo, ou o texto do erro.
  static Future<String?> iniciar(Future<void> Function() ligar) {
    final c = _fim = Completer<String?>();
    _ligado = false;
    () async {
      try {
        await ligar();
        _ligado = true;
        c.complete(null);
      } catch (e) {
        c.complete('$e');
      }
    }();
    return c.future;
  }

  /// Completa quando o Firebase está pronto, com nulo; ou com o texto do erro.
  ///
  /// Se ninguém chamou [iniciar] (os testes, que não têm Firebase), responde
  /// que está pronto na hora: esperar para sempre travaria toda tela.
  static Future<String?> get pronto => _fim?.future ?? Future.value(null);

  /// O Firebase já terminou de ligar, sem erro?
  static bool get ligado => _fim == null || _ligado;

  @visibleForTesting
  static void esquecerParaTeste() {
    _fim = null;
    _ligado = false;
  }
}
