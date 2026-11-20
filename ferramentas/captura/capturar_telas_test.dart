// Fotografa as telas do app em vários tamanhos, nos dois temas.
//
// COMO USAR
//
//   CAPTURAR_EM=/pasta/das/fotos flutter test ferramentas/captura/capturar_telas_test.dart
//
// Opcionais (separados por vírgula):
//
//   LARGURAS=375,768,1280,1920     (padrão: as quatro)
//   TELAS=inicio,escala,musica,hinarios,chat,perfil     (padrão: todas)
//   TEMAS=claro,escuro             (padrão: os dois)
//
// POR QUE EXISTE
//
// Não dá para conferir tela lendo código: a rodada de 375 px achou cinco
// defeitos que nenhum teste via, e a de tela larga precisa do mesmo olhar. Isto
// roda o app DE VERDADE — as telas, os providers e o tema são os do app —, só
// que sem Firebase: os providers recebem dados inventados
// (`dados_inventados.dart`), por isso não precisa de emulador, de rede, nem de
// navegador.
//
// O QUE ESTA FOTO NÃO É
//
// É o renderizador de testes do Flutter, com as fontes do app carregadas. A
// distribuição das telas, as cores e o texto são os reais; o desfoque do vidro,
// a suavização das letras e o comportamento de toque/rolagem de um navegador
// de verdade, não. Foto daqui prova que NADA ESTOURA nem fica cortado, e não
// substitui abrir o app num iPhone.
//
// Não roda no `flutter test` normal: fica fora da pasta `test/` de propósito,
// para ninguém esperar dezenas de fotos a cada commit.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
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

import 'dados_inventados.dart';

/// O líder da foto. Estende o AuthProvider de verdade, trocando só o que
/// falaria com o banco.
class _AuthInventado extends AuthProvider {
  @override
  UserModel? get user => lider;

  @override
  bool get isAdmin => true;

  @override
  AuthStatus get status => AuthStatus.authenticated;

  @override
  List<UserModel> get pessoas => ministerio;

  @override
  Map<String, String> get nomes => {for (final p in ministerio) p.id: p.name};

  @override
  String? get emailDeRecuperacao => 'ana@exemplo.com';

  @override
  void ouvirPessoas() {}

  @override
  Future<void> conferirRecuperacao() async {}
}

final _chave = GlobalKey();

class _Tamanho {
  final int largura;
  final int altura;
  final double escala;
  const _Tamanho(this.largura, this.altura, this.escala);
}

/// 375 sai em dobro (é celular, e o olho espera nitidez); o resto em 1×, para
/// as páginas de entrega não passarem de poucos megabytes.
const _tamanhos = {
  375: _Tamanho(375, 812, 2),
  768: _Tamanho(768, 1024, 1),
  1280: _Tamanho(1280, 800, 1),
  1920: _Tamanho(1920, 1080, 1),
};

Future<void> _carregarFontes() async {
  Future<void> carregar(String familia, List<String> arquivos) async {
    final loader = FontLoader(familia);
    for (final a in arquivos) {
      loader.addFont(Future.value(ByteData.sublistView(File(a).readAsBytesSync())));
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
  final flutter = Platform.environment['FLUTTER_ROOT'] ??
      File(Platform.resolvedExecutable).parent.parent.parent.parent.path;
  final icones =
      '$flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf';
  await carregar('MaterialIcons', [
    if (File(icones).existsSync()) icones,
  ]);
}

Future<void> _montar(
  WidgetTester t, {
  required _Tamanho tam,
  required bool escuro,
  required int aba,
}) async {
  t.view.physicalSize = Size(tam.largura * tam.escala, tam.altura * tam.escala);
  t.view.devicePixelRatio = tam.escala;

  SharedPreferences.setMockInitialValues({});
  await LocalStorageService.init();
  await initializeDateFormatting('pt_BR');

  AuthService.pendentesParaTeste =
      Stream<List<UserModel>>.value(const []).asBroadcastStream();

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
  );

  await t.pumpWidget(
    RepaintBoundary(
      key: _chave,
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
          ChangeNotifierProvider<AuthProvider>.value(value: _AuthInventado()),
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
          home: MainScreen(abaInicial: aba, escutas: false),
        ),
      ),
    ),
  );
  await _assentar(t);
}

/// Deixa as animações acabarem sem esperar as que nunca acabam (indicadores
/// de progresso, cursor piscando): `pumpAndSettle` ficaria preso nelas.
Future<void> _assentar(WidgetTester t) async {
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 250));
  }
}

Future<void> _foto(WidgetTester t, String arquivo, _Tamanho tam) async {
  final fronteira = t.renderObject<RenderRepaintBoundary>(find.byKey(_chave));
  await t.runAsync(() async {
    final imagem = await fronteira.toImage(pixelRatio: tam.escala);
    final bytes = await imagem.toByteData(format: ui.ImageByteFormat.png);
    File(arquivo)
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

Future<void> _tocar(WidgetTester t, Finder f) async {
  await t.tap(f.first, warnIfMissed: false);
  await _assentar(t);
}

/// Cada tela: a aba em que o app abre e o que tocar até chegar nela.
class _Tela {
  final String nome;
  final int aba;
  final Future<void> Function(WidgetTester t)? depois;
  const _Tela(this.nome, this.aba, [this.depois]);
}

final _telas = <_Tela>[
  const _Tela('inicio', 0),
  _Tela('escala', 2, (t) => _tocar(t, find.textContaining('Culto de quarta'))),
  _Tela('musica', 1,
      (t) => _tocar(t, find.textContaining('Grande é a tua fidelidade'))),
  _Tela('hinarios', 1, (t) => _tocar(t, find.text('Hinários'))),
  _Tela('hinarios-lista', 1, (t) async {
    await _tocar(t, find.text('Hinários'));
    await _tocar(t, find.text('Ver todos os hinos'));
  }),
  _Tela('hinarios-busca', 1, (t) async {
    await _tocar(t, find.text('Hinários'));
    await _tocar(t, find.text('Ver todos os hinos'));
    await t.enterText(find.byType(TextField), 'promessa firmes');
    await _assentar(t);
  }),
  const _Tela('chat', 3),
  const _Tela('perfil', 4),
];

void main() {
  final saida = Platform.environment['CAPTURAR_EM'];
  if (saida == null) {
    test('captura de telas', () {}, skip: 'defina CAPTURAR_EM=<pasta>');
    return;
  }

  List<String> lista(String chave, List<String> padrao) {
    final v = Platform.environment[chave];
    return v == null || v.trim().isEmpty
        ? padrao
        : v.split(',').map((e) => e.trim()).toList();
  }

  final larguras = lista('LARGURAS', ['375', '768', '1280', '1920'])
      .map(int.parse)
      .toList();
  final nomes = lista('TELAS', _telas.map((e) => e.nome).toList());
  final temas = lista('TEMAS', ['claro', 'escuro']);

  setUpAll(_carregarFontes);

  for (final largura in larguras) {
    final tam = _tamanhos[largura]!;
    for (final tema in temas) {
      for (final tela in _telas.where((e) => nomes.contains(e.nome))) {
        testWidgets('$largura ${tema.padRight(6)} ${tela.nome}', (t) async {
          addTearDown(t.view.reset);
          await _montar(t, tam: tam, escuro: tema == 'escuro', aba: tela.aba);
          if (tela.depois != null) await tela.depois!(t);
          await _foto(t, '$saida/$largura-$tema-${tela.nome}.png', tam);
          // Desmonta, para o relógio do MainScreen não ficar pendente.
          await t.pumpWidget(const SizedBox.shrink());
        });
      }
    }
  }
}
