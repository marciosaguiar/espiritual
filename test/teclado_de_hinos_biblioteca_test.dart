// O teclado de hinos com a biblioteca: digitar o número e o hino abrir.
//
// É o caminho que o usuário faz de verdade, no meio do culto: o dirigente
// anuncia "hino 65", a pessoa digita, o hino aparece. O que se confere aqui é
// o que só aparece com a tela de pé, num celular de 375 px — e os estados que
// a pessoa lê quando o hino NÃO abre, que têm de dizer a verdade.
//
// TODO o texto é inventado.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:levitasync/data/models/hino_da_biblioteca.dart';
import 'package:levitasync/data/models/song_model.dart';
import 'package:levitasync/data/models/user_model.dart';
import 'package:levitasync/data/services/local_storage_service.dart';
import 'package:levitasync/presentation/providers/auth_provider.dart';
import 'package:levitasync/presentation/providers/biblioteca_provider.dart';
import 'package:levitasync/presentation/providers/scale_provider.dart';
import 'package:levitasync/presentation/providers/songs_provider.dart';
import 'package:levitasync/presentation/screens/songs/hino_por_numero_screen.dart';

class _AuthDeTeste extends AuthProvider {
  final bool lider;
  _AuthDeTeste({required this.lider});

  @override
  bool get isAdmin => lider;

  @override
  UserModel? get user => UserModel(
        id: 'uid-teste',
        name: 'Teste',
        role: lider ? UserRole.admin : UserRole.levita,
        createdAt: DateTime(2026),
      );
}

class _Banco {
  String? erroDoIndice;
  String? erroAoGravar;
  int leiturasDeHino = 0;
  final List<SongModel> gravadas = [];
  final titulos = <int, String>{
    15: 'Título quinze',
    65: 'Título sessenta e cinco',
    66: 'Grande é o nome',
    150: 'Título cento e cinquenta',
  };

  Future<({IndiceDoHinario? indice, String? error})> lerIndice(String id) async {
    if (erroDoIndice != null) return (indice: null, error: erroDoIndice);
    // Só a Harpa tem hinos nesta biblioteca de mentira.
    final meus = id == 'harpa' ? titulos : const <int, String>{};
    return (
      indice: IndiceDoHinario(hinario: id, titulos: Map.of(meus)),
      error: null
    );
  }

  Future<({HinoDaBiblioteca? hino, String? error})> lerHino(
      String id, int n) async {
    leiturasDeHino++;
    final t = titulos[n];
    if (id != 'harpa' || t == null) return (hino: null, error: null);
    return (
      hino: HinoDaBiblioteca(
          hinario: id,
          numero: n,
          titulo: t,
          letra: 'Primeira estrofe inventada do $n\n\nSegunda estrofe do $n'),
      error: null
    );
  }
}

Future<_Banco> _montar(
  WidgetTester t, {
  bool lider = true,
  bool paraEscolher = false,
  void Function(Object?)? aoDevolver,
  _Banco? banco,
}) async {
  t.view.physicalSize = const Size(375 * 3, 812 * 3);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);

  SharedPreferences.setMockInitialValues({});
  await LocalStorageService.init();

  final b = banco ?? _Banco();
  final biblioteca = BibliotecaProvider(
    lerIndice: b.lerIndice,
    lerHino: b.lerHino,
    gravarMusica: (m) async {
      if (b.erroAoGravar != null) {
        return (success: false, error: b.erroAoGravar);
      }
      b.gravadas.add(m);
      return (success: true, error: null);
    },
  );

  await t.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(
            value: _AuthDeTeste(lider: lider)),
        ChangeNotifierProvider<SongsProvider>(create: (_) => SongsProvider()),
        ChangeNotifierProvider<ScaleProvider>(create: (_) => ScaleProvider()),
        ChangeNotifierProvider<BibliotecaProvider>.value(value: biblioteca),
      ],
      child: MaterialApp(
        home: paraEscolher
            ? Builder(
                builder: (ctx) => Scaffold(
                  body: Center(
                    child: ElevatedButton(
                      onPressed: () async {
                        final r = await Navigator.push<SongModel>(
                          ctx,
                          MaterialPageRoute(
                              builder: (_) => const HinoPorNumeroScreen(
                                  paraEscolher: true)),
                        );
                        aoDevolver?.call(r);
                      },
                      child: const Text('abrir teclado'),
                    ),
                  ),
                ),
              )
            : const HinoPorNumeroScreen(),
      ),
    ),
  );
  await t.pumpAndSettle();
  return b;
}

Future<void> _digitar(WidgetTester t, String numero) async {
  for (final d in numero.split('')) {
    await t.tap(find.text(d).first);
    await t.pump();
  }
}

void main() {
  group('digitar o número abre o hino da biblioteca', () {
    testWidgets('"65" não pode crescer na Harpa: abre na hora', (t) async {
      await _montar(t);
      await _digitar(t, '65');
      await t.pumpAndSettle();

      expect(find.text('Título sessenta e cinco'), findsOneWidget);
      expect(find.textContaining('Primeira estrofe inventada do 65'),
          findsOneWidget);
      expect(find.text('HC 65'), findsOneWidget, reason: 'título da barra');
    });

    testWidgets('"15" pode virar 150: espera um instante antes de abrir',
        (t) async {
      await _montar(t);
      await _digitar(t, '15');
      // Ainda esperando o possível terceiro dígito.
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('Título quinze'), findsNothing);

      await t.pump(const Duration(milliseconds: 400));
      await t.pumpAndSettle();
      expect(find.text('Título quinze'), findsOneWidget);
    });

    testWidgets('"150" abre o 150, não o 15', (t) async {
      await _montar(t);
      await _digitar(t, '150');
      await t.pumpAndSettle();
      expect(find.text('Título cento e cinquenta'), findsOneWidget);
      expect(find.text('Título quinze'), findsNothing);
    });

    testWidgets('a letra aparece com as estrofes', (t) async {
      await _montar(t);
      await _digitar(t, '65');
      await t.pumpAndSettle();
      expect(find.textContaining('Segunda estrofe do 65'), findsOneWidget);
    });
  });

  group('o que a pessoa lê quando o hino NÃO abre', () {
    testWidgets('número que a biblioteca não tem: "ainda não está", e o líder '
        'pode cadastrar', (t) async {
      await _montar(t);
      await _digitar(t, '77');
      await t.pumpAndSettle();
      expect(find.text('O hino 77 ainda não está no repertório.'),
          findsOneWidget);
      expect(find.text('Cadastrar agora'), findsOneWidget);
    });

    testWidgets('levita lê para pedir a um líder, e não vê o botão', (t) async {
      await _montar(t, lider: false);
      await _digitar(t, '77');
      await t.pumpAndSettle();
      expect(find.text('O hino 77 ainda não está no repertório.'),
          findsOneWidget);
      expect(find.text('Cadastrar agora'), findsNothing);
      expect(find.textContaining('Peça a um líder'), findsOneWidget);
    });

    testWidgets('número que o hinário não tem: "não existe"', (t) async {
      await _montar(t);
      await _digitar(t, '700');
      await t.pumpAndSettle();
      expect(find.text('Não existe o hino 700 na Harpa Cristã.'),
          findsOneWidget);
    });

    // Roda como líder E como levita: "Peça a um líder" só aparece para o
    // levita, e "Cadastrar agora" só para o líder. Testar um papel só deixaria
    // a metade das duas checagens passar sem provar nada.
    for (final lider in [true, false]) {
      testWidgets(
          'sem internet (${lider ? 'líder' : 'levita'}): diz o MOTIVO, sem '
          '"Cadastrar agora" nem "Peça a um líder"', (t) async {
        // Ao lado de "Sem conexão", esses dois mandariam a pessoa fazer algo
        // que não resolve — e "ainda não está no repertório" seria mentira.
        final b = _Banco()
          ..erroDoIndice = 'Sem conexão. Não foi possível ler a lista de hinos.';
        await _montar(t, banco: b, lider: lider);
        await _digitar(t, '65');
        await t.pumpAndSettle();
        expect(find.textContaining('Sem conexão'), findsWidgets);
        expect(find.text('Cadastrar agora'), findsNothing);
        expect(find.textContaining('Peça a um líder'), findsNothing);
        expect(find.textContaining('ainda não está no repertório'),
            findsNothing);
      });
    }

    testWidgets('biblioteca vazia do Cantor: o mesmo "ainda não está"',
        (t) async {
      await _montar(t);
      await t.tap(find.text('Cantor Cristão'));
      await t.pumpAndSettle();
      await _digitar(t, '65');
      await t.pumpAndSettle();
      expect(find.text('O hino 65 ainda não está no repertório.'),
          findsOneWidget);
    });
  });

  group('procurar pelo nome', () {
    Future<void> procurar(WidgetTester t, String texto) async {
      await t.ensureVisible(find.byType(TextField));
      await t.enterText(find.byType(TextField), texto);
      await t.pumpAndSettle();
    }

    testWidgets('acha pelo título, ignorando acento', (t) async {
      await _montar(t);
      await procurar(t, 'NOME');
      expect(find.text('Na biblioteca'), findsOneWidget);
      expect(find.text('Grande é o nome'), findsOneWidget);
    });

    testWidgets('tocar no resultado abre o hino', (t) async {
      await _montar(t);
      await procurar(t, 'grande');
      await t.tap(find.text('Grande é o nome'));
      await t.pumpAndSettle();
      expect(find.text('HC 66'), findsOneWidget);
      expect(find.textContaining('Primeira estrofe inventada do 66'),
          findsOneWidget);
    });

    testWidgets('sem busca, não despeja a biblioteca: só diz quantos há',
        (t) async {
      await _montar(t);
      expect(find.text('Na biblioteca'), findsNothing);
      expect(find.textContaining('Na biblioteca há 4 hinos da Harpa Cristã'),
          findsOneWidget);
    });

    testWidgets('busca sem resultado diz que não achou, e não "cadastre"',
        (t) async {
      await _montar(t);
      await procurar(t, 'zzzz');
      expect(find.text('Nenhum hino da Harpa Cristã com "zzzz".'),
          findsOneWidget);
    });

    testWidgets('repertório vazio mas biblioteca cheia NÃO manda cadastrar '
        'o que já existe', (t) async {
      await _montar(t);
      expect(find.textContaining('Nenhum hino da Harpa Cristã no repertório ainda'),
          findsOneWidget);
      expect(find.textContaining('Eles entram pelo cadastro de música'),
          findsNothing);
    });

    testWidgets('sem nada na biblioteca, o texto de antes continua', (t) async {
      await _montar(t);
      await t.tap(find.text('Cantor Cristão'));
      await t.pumpAndSettle();
      expect(find.textContaining('Eles entram pelo cadastro de música'),
          findsOneWidget);
    });
  });

  group('a tela de leitura', () {
    testWidgets('líder vê "Pôr no repertório"', (t) async {
      await _montar(t);
      await _digitar(t, '65');
      await t.pumpAndSettle();
      expect(find.text('Pôr no repertório'), findsOneWidget);
    });

    testWidgets('levita lê, mas não vê o botão — vê o que fazer', (t) async {
      await _montar(t, lider: false);
      await _digitar(t, '65');
      await t.pumpAndSettle();
      expect(find.text('Título sessenta e cinco'), findsOneWidget);
      expect(find.text('Pôr no repertório'), findsNothing);
      expect(find.textContaining('peça a um líder'), findsOneWidget);
    });

    testWidgets('a letra cresce e diminui, para ler de longe', (t) async {
      await _montar(t);
      await _digitar(t, '65');
      await t.pumpAndSettle();

      double tamanho() => t
          .widget<Text>(find.textContaining('Primeira estrofe inventada do 65'))
          .style!
          .fontSize!;

      final inicial = tamanho();
      await t.tap(find.byTooltip('Letra maior'));
      await t.pump();
      expect(tamanho(), greaterThan(inicial));

      await t.tap(find.byTooltip('Letra menor'));
      await t.tap(find.byTooltip('Letra menor'));
      await t.pump();
      expect(tamanho(), lessThan(inicial));
    });

    testWidgets('a letra tem limite: no máximo o botão desliga', (t) async {
      await _montar(t);
      await _digitar(t, '65');
      await t.pumpAndSettle();
      for (var i = 0; i < 20; i++) {
        await t.tap(find.byTooltip('Letra maior'), warnIfMissed: false);
        await t.pump();
      }
      final botao = t.widget<IconButton>(find.widgetWithIcon(
          IconButton, Icons.text_increase_rounded));
      expect(botao.onPressed, isNull);
    });

    testWidgets('erro ao pôr no repertório aparece, e a pessoa continua '
        'lendo', (t) async {
      final b = _Banco()..erroAoGravar = 'Você não tem permissão para salvar a música.';
      await _montar(t, banco: b);
      await _digitar(t, '65');
      await t.pumpAndSettle();

      await t.tap(find.text('Pôr no repertório'));
      await t.pumpAndSettle();
      expect(find.textContaining('Você não tem permissão'), findsOneWidget);
      expect(find.text('Título sessenta e cinco'), findsOneWidget,
          reason: 'continua na leitura');
      expect(b.gravadas, isEmpty);
    });
  });

  group('escolher o hino para um culto', () {
    testWidgets('o hino da biblioteca vira música ANTES de voltar, porque o '
        'culto guarda o id da música', (t) async {
      Object? devolvido;
      final b = await _montar(t,
          paraEscolher: true, aoDevolver: (r) => devolvido = r);
      await t.tap(find.text('abrir teclado'));
      await t.pumpAndSettle();

      await _digitar(t, '65');
      await t.pumpAndSettle();

      expect(b.gravadas.length, 1);
      expect(devolvido, isA<SongModel>());
      final m = devolvido as SongModel;
      expect(m.name, 'HC 65 · Título sessenta e cinco');
      expect(m.hinario, 'harpa');
      expect(m.numero, 65);
      expect(m.id, b.gravadas.single.id);
    });

    testWidgets('se não conseguir gravar, NÃO devolve música fantasma',
        (t) async {
      Object? devolvido = 'intocado';
      final b = _Banco()..erroAoGravar = 'Você não tem permissão para salvar a música.';
      await _montar(t,
          paraEscolher: true, banco: b, aoDevolver: (r) => devolvido = r);
      await t.tap(find.text('abrir teclado'));
      await t.pumpAndSettle();

      await _digitar(t, '65');
      await t.pumpAndSettle();

      expect(devolvido, 'intocado', reason: 'a tela não fechou');
      expect(find.textContaining('Você não tem permissão'), findsOneWidget);
      expect(find.text('Cadastrar agora'), findsNothing);
    });
  });

  group('o custo', () {
    testWidgets('número que não está na biblioteca não lê letra nenhuma',
        (t) async {
      final b = await _montar(t);
      await _digitar(t, '77');
      await t.pumpAndSettle();
      expect(b.leiturasDeHino, 0);
    });

    testWidgets('abrir um hino lê UMA letra', (t) async {
      final b = await _montar(t);
      await _digitar(t, '65');
      await t.pumpAndSettle();
      expect(b.leiturasDeHino, 1);
    });
  });
}
