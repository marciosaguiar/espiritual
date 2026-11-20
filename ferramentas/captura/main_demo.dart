// O app inteiro, SEM Firebase, para rodar num navegador de verdade.
//
// COMO USAR
//
//   flutter build web --release -t ferramentas/captura/main_demo.dart \
//       --pwa-strategy=none --no-web-resources-cdn
//   # serve build/web e abre ?aba=1 (0 Início, 1 Músicas, 2 Escala, 3 Chat,
//   # 4 Perfil) e, opcionalmente, &tema=escuro
//
// POR QUE EXISTE
//
// O renderizador de testes do Flutter não é um navegador: não tem o desfoque
// do vidro, os emojis, o clique de verdade nem o teclado. A rodada de tela
// larga foi conferida pelo dono no Chrome e achou o que as fotos de teste não
// achavam (a música abrindo em tela cheia). Isto é a mesma montagem das fotos
// — as telas, os providers e o tema do app, com os dados inventados de
// `test/utilitarios/` —, mas compilada para a web, para o Playwright clicar.
//
// Fica FORA de `lib/`: nada daqui entra no pacote que vai para o ar.

// Usa de propósito as costuras de teste (`carregarParaTeste`,
// `pendentesParaTeste`): é exatamente o que este demo é.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

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
import 'package:levitasync/presentation/widgets/common/responsivo.dart';

import '../../test/utilitarios/auth_inventado.dart';
import '../../test/utilitarios/dados_inventados.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LocalStorageService.init();
  await initializeDateFormatting('pt_BR');

  AuthService.pendentesParaTeste =
      Stream<List<UserModel>>.value(const []).asBroadcastStream();

  final params = Uri.base.queryParameters;
  final aba = int.tryParse(params['aba'] ?? '') ?? 0;
  final escuro = params['tema'] == 'escuro';

  final songs = SongsProvider()..carregarParaTeste(repertorioInventado());
  final scale = ScaleProvider()..carregarParaTeste(cultosInventados());
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

  runApp(
    MultiProvider(
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
        title: 'LevitaSync (demo)',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: escuro ? ThemeMode.dark : ThemeMode.light,
        builder: (context, child) => OuvinteDeEntrada(
          child: GlassBackdrop(child: child ?? const SizedBox.shrink()),
        ),
        home: MainScreen(abaInicial: aba, escutas: false),
      ),
    ),
  );
}
