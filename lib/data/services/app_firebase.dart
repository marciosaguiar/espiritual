import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/platform/rede.dart';

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
///
/// **LIGAR FALHAR NÃO DERRUBA O APP.** Sem internet, o SDK do Firebase (que o
/// navegador busca em www.gstatic.com) pode não carregar, e `initializeApp`
/// lança. Antes isso trocava o app inteiro por uma tela de "falta configurar"
/// — o contrário de funcionar sem sinal. Agora a falha é só "ainda não deu":
/// o app segue com o que tem, e a ligação é tentada de novo — de tempos em
/// tempos e no instante em que a internet volta —, sem nunca completar
/// [pronto] com erro. Configuração inválida é outra coisa, e é conferida
/// ANTES de chegar aqui (`_conferirFirebase`).
class AppFirebase {
  AppFirebase._();

  static Completer<String?>? _fim;
  static bool _ligado = false;

  /// O motivo da última tentativa que não deu, ou nulo. É o que a tela de
  /// abertura mostra, em português, quando a espera se alonga.
  static final ValueNotifier<String?> ultimoErro = ValueNotifier(null);

  /// Quantas tentativas já falharam (para o teste e para o log).
  static int falhas = 0;

  static const List<Duration> _esperas = [
    Duration(seconds: 2),
    Duration(seconds: 5),
    Duration(seconds: 15),
    Duration(seconds: 30),
  ];

  /// Começa a ligar, e só devolve quando CONSEGUIU (nulo). [ligar] faz o
  /// trabalho e tem de poder ser chamado de novo depois de falhar.
  static Future<String?> iniciar(
    Future<void> Function() ligar, {
    List<Duration> esperas = _esperas,
  }) {
    final c = _fim = Completer<String?>();
    _ligado = false;
    falhas = 0;
    ultimoErro.value = null;
    () async {
      while (true) {
        try {
          await ligar();
          _ligado = true;
          ultimoErro.value = null;
          c.complete(null);
          return;
        } catch (e) {
          falhas++;
          ultimoErro.value = '$e';
          debugPrint('Firebase ainda não ligou (tentativa $falhas): $e');
          final espera = esperas[(falhas - 1).clamp(0, esperas.length - 1)];
          // Volta a tentar na hora em que a internet volta — esperar o prazo
          // inteiro com o sinal já de volta seria atraso sem motivo.
          await Future.any([
            Future<void>.delayed(espera),
            Rede.mudancas.firstWhere((online) => online),
          ]);
        }
      }
    }();
    return c.future;
  }

  /// Completa quando o Firebase está pronto, com nulo. Nunca completa com
  /// erro: ver o comentário da classe.
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
    falhas = 0;
    ultimoErro.value = null;
  }
}
