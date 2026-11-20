// O app inteiro, montado com dados inventados e sem Firebase.
//
// É o que o roteiro de fotos e os testes de layout usam: as telas, os
// providers e o tema são os do app; só o que falaria com o banco é trocado
// por dados da memória (`dados_inventados.dart`).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:levitasync/core/theme/app_theme.dart';
import 'package:levitasync/data/models/hino_da_biblioteca.dart';
import 'package:levitasync/data/models/user_model.dart';
import 'package:levitasync/data/services/auth_service.dart';
import 'package:levitasync/data/services/local_storage_service.dart';
import 'package:levitasync/presentation/providers/agenda_provider.dart';
import 'package:levitasync/presentation/providers/auth_provider.dart';
import 'package:levitasync/presentation/providers/biblioteca_provider.dart';
import 'package:levitasync/presentation/providers/chat_provider.dart';
import 'package:levitasync/presentation/providers/saude_provider.dart';
import 'package:levitasync/presentation/providers/scale_provider.dart';
import 'package:levitasync/presentation/providers/songs_provider.dart';
import 'package:levitasync/presentation/providers/theme_provider.dart';
import 'package:levitasync/presentation/screens/main_screen.dart';
import 'package:levitasync/presentation/widgets/common/glass.dart';

import 'auth_inventado.dart';
import 'dados_inventados.dart';
import 'fontes.dart';

export 'auth_inventado.dart';

/// Atalho para o roteiro de fotos e os testes de layout.
Future<void> carregarFontes() => carregarFontesDoApp();

class Tamanho {
  final int largura;
  final int altura;
  final double escala;
  const Tamanho(this.largura, this.altura, this.escala);
}

/// 375 sai em dobro (é celular, e o olho espera nitidez); o resto em 1×, para
/// as páginas de entrega não passarem de poucos megabytes.
const tamanhos = {
  375: Tamanho(375, 812, 2),
  768: Tamanho(768, 1024, 1),
  1280: Tamanho(1280, 800, 1),
  1920: Tamanho(1920, 1080, 1),
  2400: Tamanho(2400, 1200, 1),
};

/// Monta o app na aba [aba], no tamanho [tam]. [chave] vai num
/// RepaintBoundary em volta de tudo, para o roteiro de fotos tirar a foto.
///
/// [escala] troca o provider de cultos (para um teste simular "criar culto"
/// sem banco) e [casa] troca a tela inicial (para testar uma aba sozinha,
/// com os providers do app em volta).
Future<void> montarApp(
  WidgetTester t, {
  required Tamanho tam,
  bool escuro = false,
  int aba = 0,
  Key? chave,
  ScaleProvider? escala,
  Widget? casa,
}) async {
  t.view.physicalSize = Size(tam.largura * tam.escala, tam.altura * tam.escala);
  t.view.devicePixelRatio = tam.escala;

  SharedPreferences.setMockInitialValues({});
  await LocalStorageService.init();
  await initializeDateFormatting('pt_BR');

  AuthService.pendentesParaTeste =
      Stream<List<UserModel>>.value(const []).asBroadcastStream();

  final songs = SongsProvider()..carregarParaTeste(repertorioInventado());
  final scale = (escala ?? ScaleProvider())
    ..carregarParaTeste(cultosInventados());
  final chat = ChatProvider()..carregarParaTeste(conversaInventada());
  final biblioteca = BibliotecaProvider(
    lerIndice: (id) async => (
      indice: indiceInventado(id, id == 'harpa' ? 640 : 581),
      error: null
    ),
    lerHino: (id, n) async => (
      hino: HinoDaBiblioteca(
        hinario: id,
        numero: n,
        titulo: tituloInventado(n),
        letra: letraInventada(n),
      ),
      error: null
    ),
    lerLetras: (id) async => (
      letras: {
        for (var n = 1; n <= (id == 'harpa' ? 640 : 581); n++)
          n: letraInventada(n)
      },
      error: null
    ),
  );

  await t.pumpWidget(
    RepaintBoundary(
      key: chave,
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
          ChangeNotifierProvider<AuthProvider>.value(value: AuthInventado()),
          ChangeNotifierProvider<SongsProvider>.value(value: songs),
          ChangeNotifierProvider<BibliotecaProvider>.value(value: biblioteca),
          ChangeNotifierProvider<ScaleProvider>.value(value: scale),
          ChangeNotifierProvider<ChatProvider>.value(value: chat),
          ChangeNotifierProvider(create: (_) => AgendaProvider()),
          ChangeNotifierProvider(create: (_) => SaudeProvider()),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: escuro ? ThemeMode.dark : ThemeMode.light,
          builder: (context, child) =>
              GlassBackdrop(child: child ?? const SizedBox.shrink()),
          home: casa ?? MainScreen(abaInicial: aba, escutas: false),
        ),
      ),
    ),
  );
  await assentar(t);
}

/// Deixa as animações acabarem sem esperar as que nunca acabam (indicadores
/// de progresso, cursor piscando): `pumpAndSettle` ficaria preso nelas.
Future<void> assentar(WidgetTester t) async {
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 250));
  }
}
