// As fontes de verdade do app, para os testes de layout.
//
// O teste de widget desenha com uma fonte própria, bem mais larga que a
// Poppins: "cabe a 375 px" medido com ela ora reprova o que cabe, ora aprova o
// que não cabe. Com a Poppins carregada, a largura que o teste mede é a que o
// aparelho vai desenhar.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> carregarFontesDoApp() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  Future<void> carregar(String familia, List<String> arquivos) async {
    final loader = FontLoader(familia);
    for (final a in arquivos) {
      loader.addFont(
          Future.value(ByteData.sublistView(File(a).readAsBytesSync())));
    }
    await loader.load();
  }

  await carregar('Poppins', [
    'assets/fonts/Poppins-Regular.ttf',
    'assets/fonts/Poppins-Medium.ttf',
    'assets/fonts/Poppins-SemiBold.ttf',
    'assets/fonts/Poppins-Bold.ttf',
  ]);
  await carregar('JetBrainsMono', ['assets/fonts/JetBrainsMono.ttf']);

  // Os ícones do Material vêm no SDK do Flutter, não no app. Sem eles, toda
  // foto sai com quadrados no lugar de ícones — e o teste de widget também não
  // saberia a largura certa de um botão com ícone.
  final raiz = Platform.environment['FLUTTER_ROOT'] ??
      File(Platform.resolvedExecutable).parent.parent.parent.parent.path;
  final icones = '$raiz/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf';
  if (File(icones).existsSync()) await carregar('MaterialIcons', [icones]);
}
