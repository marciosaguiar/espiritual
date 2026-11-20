// A tela de hinários compacta: pastilhas lado a lado, o número em dois
// toques, "Ver todos os hinos" com a ordem à vista, e o computador.
//
// Os critérios que o dono pediu, medidos:
//   (a) abrir o hino 15 da Harpa: até 2 toques depois de abrir Hinários;
//   (b) achar um hino por um trecho da letra: até 3 toques;
//   nada cortado a 375 px, no claro e no escuro.
//
// TODO o texto é inventado.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:levitasync/data/models/hino_da_biblioteca.dart';
import 'package:levitasync/data/models/user_model.dart';
import 'package:levitasync/data/services/local_storage_service.dart';
import 'package:levitasync/presentation/providers/auth_provider.dart';
import 'package:levitasync/presentation/providers/biblioteca_provider.dart';
import 'package:levitasync/presentation/providers/scale_provider.dart';
import 'package:levitasync/presentation/providers/songs_provider.dart';
import 'package:levitasync/presentation/screens/songs/hino_por_numero_screen.dart';
import 'package:levitasync/presentation/widgets/common/responsivo.dart';

import 'utilitarios/fontes.dart';

class _Auth extends AuthProvider {
  final String id;
  _Auth(this.id);

  @override
  bool get isAdmin => true;

  @override
  UserModel? get user => UserModel(
        id: id,
        name: 'Teste',
        role: UserRole.admin,
        createdAt: DateTime(2026),
      );
}

class _Banco {
  int leiturasDeLetras = 0;
  String? erroDasLetras;
  final titulos = <int, String>{
    15: 'Título quinze',
    65: 'Título sessenta e cinco',
    66: 'Grande é o nome',
    150: 'Título cento e cinquenta',
  };
  final letras = <int, String>{
    15: '1 Primeira estrofe do quinze\nfirmes nas promessas do Senhor',
    65: '1 Quem guarda o seu povo\nnão deixa de amparar',
    66: '1 Grande é o nome\nde quem nos sustenta',
    150: '1 Cento e cinquenta\nestrofe inventada',
  };

  BibliotecaProvider provider() => BibliotecaProvider(
        lerIndice: (id) async => (
          indice: IndiceDoHinario(
              hinario: id, titulos: id == 'harpa' ? Map.of(titulos) : {}),
          error: null
        ),
        lerHino: (id, n) async {
          final t = titulos[n];
          if (id != 'harpa' || t == null) return (hino: null, error: null);
          return (
            hino: HinoDaBiblioteca(
                hinario: id, numero: n, titulo: t, letra: letras[n]!),
            error: null
          );
        },
        lerLetras: (id) async {
          leiturasDeLetras++;
          if (erroDasLetras != null) return (letras: null, error: erroDasLetras);
          return (letras: id == 'harpa' ? Map.of(letras) : <int, String>{}, error: null);
        },
      );
}

Future<_Banco> _montar(
  WidgetTester t, {
  Size tela = const Size(375, 812),
  bool escuro = false,
  bool dedo = true,
  String usuario = 'ana',
  Map<String, Object> prefs = const {},
  _Banco? banco,
}) async {
  t.view.physicalSize = Size(tela.width * 2, tela.height * 2);
  t.view.devicePixelRatio = 2;
  addTearDown(t.view.reset);
  addTearDown(() => EntradaDoUsuario.definir(false));
  EntradaDoUsuario.definir(dedo);

  SharedPreferences.setMockInitialValues(prefs);
  await LocalStorageService.init();

  final b = banco ?? _Banco();
  await t.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: _Auth(usuario)),
        ChangeNotifierProvider<SongsProvider>(create: (_) => SongsProvider()),
        ChangeNotifierProvider<ScaleProvider>(create: (_) => ScaleProvider()),
        ChangeNotifierProvider<BibliotecaProvider>.value(value: b.provider()),
      ],
      child: MaterialApp(
        themeMode: escuro ? ThemeMode.dark : ThemeMode.light,
        theme: ThemeData(brightness: Brightness.light),
        darkTheme: ThemeData(brightness: Brightness.dark),
        home: const Scaffold(
          body: SafeArea(child: HinoPorNumeroScreen(embutida: true)),
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
  return b;
}

void main() {
  // Poppins de verdade: a fonte de teste é mais larga e mentiria sobre o corte.
  setUpAll(carregarFontesDoApp);

  group('as pastilhas', () {
    testWidgets('os dois hinários ficam LADO A LADO, numa fila só', (t) async {
      await _montar(t);
      final harpa = t.getRect(find.text('Harpa Cristã'));
      final cantor = t.getRect(find.text('Cantor Cristão'));
      expect((harpa.center.dy - cantor.center.dy).abs(), lessThan(1),
          reason: 'mesma altura: lado a lado');
      expect(cantor.left, greaterThan(harpa.right));
      expect(cantor.right, lessThan(375), reason: 'cabe a 375 px, sem cortar');
    });

    testWidgets('a fila é baixa: não come a tela como a lista de pé comia',
        (t) async {
      await _montar(t);
      final r = t.getRect(find.ancestor(
          of: find.text('Harpa Cristã'), matching: find.byType(Material)).first);
      expect(r.height, lessThanOrEqualTo(48));
    });

    testWidgets('"Mudar a ordem" é um botão com TEXTO, e mostra as setas',
        (t) async {
      await _montar(t);
      expect(find.byTooltip('Mover Harpa Cristã para a esquerda'),
          findsNothing, reason: 'as setas só aparecem quando a pessoa pede');
      await t.tap(find.text('Mudar a ordem'));
      await t.pumpAndSettle();
      expect(find.textContaining('Use as setas para mudar a ordem'),
          findsOneWidget);
      expect(find.byTooltip('Mover Cantor Cristão para a esquerda'),
          findsOneWidget);
      // A opção que não tem para onde ir some.
      expect(find.byTooltip('Mover Harpa Cristã para a esquerda'), findsNothing);
      expect(find.byTooltip('Mover Cantor Cristão para a direita'), findsNothing);
    });

    testWidgets('a seta troca a ordem, grava POR PESSOA, e "Pronto" fecha',
        (t) async {
      await _montar(t);
      await t.tap(find.text('Mudar a ordem'));
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('Mover Cantor Cristão para a esquerda'));
      await t.pumpAndSettle();

      expect(LocalStorageService.ordemDosHinariosDe('ana'),
          ['cantor', 'harpa']);
      expect(LocalStorageService.ordemDosHinariosDe('bruno'), isEmpty);
      final harpa = t.getRect(find.text('Harpa Cristã'));
      final cantor = t.getRect(find.text('Cantor Cristão'));
      expect(cantor.left, lessThan(harpa.left), reason: 'o Cantor foi à frente');

      await t.tap(find.text('Pronto'));
      await t.pumpAndSettle();
      expect(find.text('Pronto'), findsNothing);
      expect(find.text('Mudar a ordem'), findsOneWidget);
    });

    testWidgets('quem pôs o Cantor na frente abre NO Cantor da próxima vez',
        (t) async {
      await _montar(t, prefs: {'ordem_hinarios_ana': ['cantor', 'harpa']});
      // O Cantor aqui não tem hino nenhum, e o teclado diz o hinário que é.
      await t.tap(find.text('1'));
      await t.pump();
      expect(find.text('CC 1'), findsOneWidget);
    });
  });

  group('abrir o hino pelo número: até 2 toques', () {
    testWidgets('1 e 5: dois toques e o hino 15 está aberto', (t) async {
      await _montar(t);
      // Hinário já escolhido (a Harpa é a primeira da fila): só o número.
      await t.tap(find.text('1'));
      await t.pump();
      await t.tap(find.text('5'));
      // "15" ainda pode virar "150": o app espera um instante antes de abrir.
      await t.pump(const Duration(milliseconds: 700));
      await t.pumpAndSettle();
      expect(find.text('HC 15'), findsOneWidget);
      expect(find.textContaining('Primeira estrofe do quinze'), findsOneWidget);
    });

    testWidgets('o teclado é a primeira coisa, sem rolar', (t) async {
      await _montar(t);
      for (final d in '1234567890'.split('')) {
        final r = t.getRect(find.text(d).first);
        expect(r.bottom, lessThan(812), reason: 'tecla $d dentro da tela');
      }
    });
  });

  group('"Ver todos os hinos"', () {
    Future<void> abrirLista(WidgetTester t) async {
      await t.tap(find.text('Ver todos os hinos'));
      await t.pumpAndSettle();
    }

    testWidgets('as ordens estão À VISTA, sem tocar em nada', (t) async {
      await _montar(t);
      await abrirLista(t);
      for (final o in ['Número', 'A–Z', 'Z–A']) {
        expect(find.text(o), findsOneWidget, reason: o);
        expect(t.getRect(find.text(o)).right, lessThan(375));
      }
    });

    testWidgets('as ordens que já existiam continuam, ao alcance de um '
        'deslize', (t) async {
      await _montar(t);
      await abrirLista(t);
      expect(find.text('Mais tocados', skipOffstage: false), findsOneWidget);
      expect(find.text('Favoritos', skipOffstage: false), findsOneWidget);
    });

    testWidgets('tocar em "Z–A" põe a lista ao contrário e GRAVA a escolha',
        (t) async {
      await _montar(t);
      await abrirLista(t);
      await t.tap(find.text('Z–A'));
      await t.pumpAndSettle();
      // Z–A: "Título sessenta e cinco" antes de "Grande é o nome".
      expect(t.getRect(find.text('Título sessenta e cinco')).top,
          lessThan(t.getRect(find.text('Grande é o nome')).top));
      expect(LocalStorageService.ordemDosHinosDe('ana'), 'nome_z_a');
      expect(LocalStorageService.ordemDosHinosDe('bruno'), isNull);
    });

    testWidgets('a escolha de OUTRA pessoa não muda a minha lista', (t) async {
      await _montar(t,
          usuario: 'bruno', prefs: {'ordem_hinos_ana': 'nome_z_a'});
      await abrirLista(t);
      // Bruno nunca escolheu: pelo número, como de fábrica.
      expect(t.getRect(find.text('Título quinze')).top,
          lessThan(t.getRect(find.text('Grande é o nome')).top));
    });

    testWidgets('lembrar a ordem de antes: ela volta ao abrir a tela',
        (t) async {
      await _montar(t, prefs: {'ordem_hinos_ana': 'nome'});
      await abrirLista(t);
      // A–Z: "Grande é o nome" antes de "Título quinze".
      expect(t.getRect(find.text('Grande é o nome')).top,
          lessThan(t.getRect(find.text('Título quinze')).top));
    });

    testWidgets('achar por nome: 2 toques e a digitação', (t) async {
      await _montar(t);
      await abrirLista(t); // toque 1
      await t.tap(find.byType(TextField)); // toque 2
      await t.enterText(find.byType(TextField), 'grande');
      await t.pumpAndSettle();
      await t.tap(find.text('Grande é o nome')); // toque 3
      await t.pumpAndSettle();
      expect(find.text('HC 66'), findsOneWidget);
    });
  });

  group('achar pelo que a letra diz', () {
    testWidgets('sem as letras no aparelho, a tela PERGUNTA antes de baixar',
        (t) async {
      final b = await _montar(t);
      await t.tap(find.text('Ver todos os hinos'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), 'amparar');
      await t.pumpAndSettle();

      expect(find.textContaining('procurando só pelos nomes'), findsOneWidget);
      expect(find.text('Trazer'), findsOneWidget);
      expect(b.leiturasDeLetras, 0,
          reason: '640 leituras só quando a pessoa pede');
    });

    testWidgets('depois de trazer, acha o hino e MOSTRA o verso', (t) async {
      final b = await _montar(t);
      await t.tap(find.text('Ver todos os hinos'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), 'amparar');
      await t.pumpAndSettle();

      await t.tap(find.text('Trazer'));
      await t.pumpAndSettle();

      expect(b.leiturasDeLetras, 1);
      expect(find.text('Trazer'), findsNothing);
      expect(find.text('Título sessenta e cinco'), findsOneWidget);
      expect(find.textContaining('não deixa de amparar'), findsOneWidget);
    });

    testWidgets('"firme nas promessas" acha "firmes nas promessas"', (t) async {
      await _montar(t);
      await t.tap(find.text('Ver todos os hinos'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), 'amparar');
      await t.pumpAndSettle();
      await t.tap(find.text('Trazer'));
      await t.pumpAndSettle();

      await t.enterText(find.byType(TextField), 'promessas firmes');
      await t.pumpAndSettle();
      expect(find.text('Título quinze'), findsOneWidget);
      expect(find.text('Título sessenta e cinco'), findsNothing);
    });

    testWidgets('as letras ficam no aparelho: na próxima vez não pergunta',
        (t) async {
      final b = await _montar(t);
      await t.tap(find.text('Ver todos os hinos'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), 'amparar');
      await t.pumpAndSettle();
      await t.tap(find.text('Trazer'));
      await t.pumpAndSettle();

      // Reabre a tela com o MESMO armazenamento (outro provider, como numa
      // nova abertura do app).
      await t.pumpWidget(const SizedBox.shrink());
      await t.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: _Auth('ana')),
            ChangeNotifierProvider<SongsProvider>(
                create: (_) => SongsProvider()),
            ChangeNotifierProvider<ScaleProvider>(
                create: (_) => ScaleProvider()),
            ChangeNotifierProvider<BibliotecaProvider>.value(
                value: b.provider()),
          ],
          child: const MaterialApp(
            home: Scaffold(body: HinoPorNumeroScreen(embutida: true)),
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Ver todos os hinos'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), 'amparar');
      await t.pumpAndSettle();

      expect(find.text('Trazer'), findsNothing);
      expect(find.textContaining('não deixa de amparar'), findsOneWidget);
      expect(b.leiturasDeLetras, 1, reason: 'não baixou de novo');
    });

    testWidgets('sem internet: o motivo aparece, e a lista segue por nome',
        (t) async {
      final b = _Banco()..erroDasLetras = 'Sem internet para trazer as letras.';
      await _montar(t, banco: b);
      await t.tap(find.text('Ver todos os hinos'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), 'grande');
      await t.pumpAndSettle();
      await t.tap(find.text('Trazer'));
      await t.pumpAndSettle();

      expect(find.text('Sem internet para trazer as letras.'), findsOneWidget);
      expect(find.text('Grande é o nome'), findsOneWidget);
    });

    testWidgets('só dígitos nunca oferecem baixar: é busca por número',
        (t) async {
      await _montar(t);
      await t.tap(find.text('Ver todos os hinos'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), '65');
      await t.pumpAndSettle();
      expect(find.text('Trazer'), findsNothing);
      expect(find.text('Título sessenta e cinco'), findsOneWidget);
    });
  });

  group('sem rolagem nem corte a 375 px', () {
    for (final escuro in [false, true]) {
      final tema = escuro ? 'escuro' : 'claro';
      testWidgets('o teclado, no tema $tema', (t) async {
        await _montar(t, escuro: escuro);
        expect(tester(t), isNull); // nenhuma exceção de layout
      });
      testWidgets('a lista, com a organização aberta, no tema $tema', (t) async {
        await _montar(t, escuro: escuro);
        await t.tap(find.text('Mudar a ordem'));
        await t.pumpAndSettle();
        await t.tap(find.text('Ver todos os hinos'));
        await t.pumpAndSettle();
        await t.enterText(find.byType(TextField), 'amparar');
        await t.pumpAndSettle();
        expect(tester(t), isNull);
      });
    }
  });

  group('dedo e teclado juntos (um iPad com teclado)', () {
    testWidgets('depois do primeiro toque nas teclas, o teclado de verdade '
        'continua o número', (t) async {
      await _montar(t);
      await t.tap(find.text('6'));
      await t.pump();
      await t.sendKeyDownEvent(LogicalKeyboardKey.digit5, character: '5');
      await t.pump(const Duration(milliseconds: 700));
      await t.pumpAndSettle();
      expect(find.text('HC 65'), findsOneWidget);
    });

    testWidgets('Backspace apaga o último dígito e Esc limpa', (t) async {
      await _montar(t);
      await t.tap(find.text('1'));
      await t.pump();
      await t.sendKeyDownEvent(LogicalKeyboardKey.digit5, character: '5');
      await t.pump();
      expect(find.text('HC 15'), findsOneWidget);
      await t.sendKeyEvent(LogicalKeyboardKey.backspace);
      await t.pump();
      expect(find.text('HC 1'), findsOneWidget);
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pump();
      expect(find.text('Digite o número'), findsOneWidget);
    });
  });

  group('no computador (mouse e teclado)', () {
    const monitor = Size(1280, 800);

    testWidgets('sem toque, NÃO há teclado na tela: vai direto para a lista',
        (t) async {
      await _montar(t, tela: monitor, dedo: false);
      expect(find.text('Digitar o número'), findsNothing);
      expect(find.text('Digite o número'), findsNothing);
      expect(find.text('Título quinze'), findsOneWidget);
    });

    testWidgets('o cursor já está na busca: digitar o número e Enter abre',
        (t) async {
      await _montar(t, tela: monitor, dedo: false);
      final campo = t.widget<TextField>(find.byType(TextField));
      expect(campo.focusNode!.hasFocus, isTrue);

      await t.enterText(find.byType(TextField), '65');
      await t.testTextInput.receiveAction(TextInputAction.search);
      await t.pumpAndSettle();
      expect(find.text('HC 65'), findsOneWidget);
    });

    testWidgets('"/" leva o cursor para a busca', (t) async {
      await _montar(t, tela: monitor, dedo: false);
      bool naBusca() =>
          t.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus;

      // Um clique fora do campo tira o cursor dele...
      await t.tap(find.text('Ordem'));
      await t.pump();
      expect(naBusca(), isFalse);

      // ...e "/" o traz de volta, sem escrever a barra.
      await t.sendKeyEvent(LogicalKeyboardKey.slash);
      await t.pump();
      expect(naBusca(), isTrue);
      expect(t.widget<TextField>(find.byType(TextField)).controller!.text, '');
    });

    testWidgets('digitar um número, com o cursor FORA da busca, cai na busca',
        (t) async {
      await _montar(t, tela: monitor, dedo: false);
      await t.tap(find.text('Ordem'));
      await t.pump();

      await t.sendKeyDownEvent(LogicalKeyboardKey.digit6, character: '6');
      await t.pump();
      final campo = t.widget<TextField>(find.byType(TextField));
      expect(campo.focusNode!.hasFocus, isTrue);
      expect(campo.controller!.text, '6');
      // Só dígitos: a lista mostra os hinos que COMEÇAM com 6.
      expect(find.text('Título sessenta e cinco'), findsOneWidget);
      expect(find.text('Título quinze'), findsNothing);
    });

    testWidgets('Esc, com a busca vazia, fecha o hino aberto ao lado',
        (t) async {
      // Sem painel (a tela está sozinha), Esc não faz nada — e não quebra.
      await _montar(t, tela: monitor, dedo: false);
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pump();
      expect(find.text('Título quinze'), findsOneWidget);
    });

    testWidgets('Esc limpa a busca', (t) async {
      await _montar(t, tela: monitor, dedo: false);
      await t.enterText(find.byType(TextField), 'grande');
      await t.pumpAndSettle();
      expect(find.text('Título quinze'), findsNothing);

      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pumpAndSettle();
      expect(find.text('Título quinze'), findsOneWidget);
    });

    testWidgets('tocou na tela com o dedo: volta o teclado numérico',
        (t) async {
      await _montar(t, tela: monitor, dedo: false);
      expect(find.text('Digitar o número'), findsNothing);
      EntradaDoUsuario.definir(true);
      await t.pumpAndSettle();
      expect(find.text('Digitar o número'), findsOneWidget);
    });
  });
}

/// A exceção de layout que o teste de widget guardou, se houve.
Object? tester(WidgetTester t) => t.takeException();
