/// A fonte de largura fixa da cifra (JetBrains Mono), carregada SÓ quando
/// alguém precisa dela.
///
/// POR QUE NÃO VAI NO PACOTE DE ABERTURA
///
/// Fonte declarada em `fonts:` no pubspec é baixada ANTES do primeiro quadro,
/// toda abertura — mesmo para quem nunca abre uma cifra. Eram 89 KB (cerca de
/// 0,5 s numa linha de 4G ruim) no caminho de abrir o app para uma fonte que
/// só a tela da música, o editor de cifra e o Modo ao vivo usam.
///
/// Agora o arquivo continua no pacote, como ativo, e esta classe o registra
/// quando a primeira dessas telas abre — e sozinha, uns segundos depois da
/// abertura do app, para ela já estar pronta quando a pessoa chegar na cifra.
///
/// E se a cifra abrir antes da fonte chegar? O texto se mede de novo sozinho
/// quando a fonte entra: o Flutter avisa os parágrafos de que as fontes
/// mudaram. Por um instante a cifra aparece na fonte comum — o que não pode
/// acontecer é ficar assim, e por isso o teste confere que toda tela que usa a
/// fonte a pede.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class FonteMono {
  const FonteMono._();

  static const String familia = 'JetBrainsMono';
  static const String arquivo = 'assets/fonts/JetBrainsMono.ttf';

  static Future<void>? _carregando;

  /// Só os testes ligam (ver `test/flutter_test_config.dart`): `garantir` passa
  /// a não carregar nada.
  ///
  /// **Por que existe:** carregar a fonte faz o motor mandar o aviso
  /// "fontsChange", e o Flutter reage agendando um quadro. Se o aviso chega
  /// DEPOIS de o teste terminar, o teste reprova com "An animation is still
  /// running even after the widget tree was disposed". Aqui, com o motor
  /// antigo, o aviso nunca chegava e tudo passava; **no Flutter 3.50.0 da CI ele
  /// chegou, e 5 testes reprovaram** (abrir_ao_lado, campo_multilinha,
  /// letra_em_tela_larga, projetar_tela, responsivo) — todos os que abrem a
  /// tela da música ou o campo de cifra. A corrida entre o aviso e o fim do
  /// teste depende de versão e de máquina; desligar o carregamento a tira do
  /// caminho em vez de torcer para ela ganhar.
  @visibleForTesting
  static bool desligada = false;

  /// Registra a fonte, uma vez só. Quem chama de novo recebe o mesmo
  /// `Future`, então pedir de várias telas não baixa nem registra de novo.
  ///
  /// Nunca lança: sem a fonte a cifra continua legível na fonte comum, só
  /// desalinhada — e derrubar a tela da música por isso seria pior.
  static Future<void> garantir() => _carregando ??= _carregar();

  static Future<void> _carregar() async {
    if (desligada) return;
    try {
      final loader = FontLoader(familia)..addFont(rootBundle.load(arquivo));
      await loader.load();
    } catch (_) {
      // Pedido de novo na próxima vez.
      _carregando = null;
    }
  }
}
