// A tela de importar hinário, montada de verdade num celular de 375 px.
//
// O que se confere aqui é o que só aparece com a tela de pé: estouro de
// layout (o Flutter o relata como exceção, e o teste falha), o que a pessoa
// lê em cada estado e se "Importar" só aparece depois de conferir. A gravação
// em si não é testada aqui — depende do Firebase —, e sim nas regras e nas
// funções puras.
//
// TODO o texto é inventado.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:levitasync/data/models/user_model.dart';
import 'package:levitasync/presentation/providers/auth_provider.dart';
import 'package:levitasync/presentation/providers/biblioteca_provider.dart';
import 'package:levitasync/presentation/screens/profile/importar_hinario_screen.dart';

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

String _hino(int n) => '$n - Título $n\n'
    '1. palavras inventadas da estrofe um do hino $n de teste\n\n'
    '2. palavras inventadas da estrofe dois do hino $n de teste\n';

Future<void> _montar(
  WidgetTester t, {
  bool lider = true,
  String copiado = '',
}) async {
  // Um celular de 375 x 812, como o app é usado na igreja.
  t.view.physicalSize = const Size(375 * 3, 812 * 3);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'Clipboard.getData') {
      return <String, dynamic>{'text': copiado};
    }
    return null;
  });
  addTearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, null));

  await t.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(
            value: _AuthDeTeste(lider: lider)),
        ChangeNotifierProvider<BibliotecaProvider>(
            create: (_) => BibliotecaProvider()),
      ],
      child: const MaterialApp(home: ImportarHinarioScreen()),
    ),
  );
  await t.pump();
}

Future<void> _colar(WidgetTester t) async {
  await t.tap(find.text('Colar o texto copiado'));
  // A tela lê a área de transferência, espera um instante (para mostrar
  // "Lendo o texto…") e só então faz a conta. `pumpAndSettle` avança o
  // relógio simulado até a tela parar — e o "Lendo…" some quando termina.
  await t.pumpAndSettle();
}

void main() {
  group('quem pode', () {
    testWidgets('quem não é líder não importa', (t) async {
      await _montar(t, lider: false);
      expect(find.text('Só os líderes importam hinários.'), findsOneWidget);
      expect(find.text('Colar o texto copiado'), findsNothing);
    });

    testWidgets('o líder vê os dois primeiros passos, e só eles', (t) async {
      await _montar(t);
      expect(find.text('Qual hinário?'), findsOneWidget);
      expect(find.text('Cole o texto'), findsOneWidget);
      expect(find.text('Confira'), findsNothing);
      expect(find.text('Importe'), findsNothing);
    });

    testWidgets('os dois hinários aparecem para escolher', (t) async {
      await _montar(t);
      expect(find.text('Harpa Cristã'), findsOneWidget);
      expect(find.text('Cantor Cristão'), findsOneWidget);
    });
  });

  group('colar e conferir', () {
    testWidgets('texto de hinário: mostra o que achou e libera Importar',
        (t) async {
      await _montar(t, copiado: [_hino(1), _hino(2), _hino(3)].join('\n'));
      await _colar(t);

      expect(find.text('Achei 3 hinos, do 1 ao 3.'), findsOneWidget);
      expect(find.text('Confira'), findsOneWidget);
      expect(find.text('Importe'), findsOneWidget);
      expect(find.text('Importar 3 hinos'), findsOneWidget);
    });

    testWidgets('a prévia mostra a letra, para conferir se está certa',
        (t) async {
      await _montar(t, copiado: [_hino(1), _hino(2), _hino(3)].join('\n'));
      await _colar(t);

      expect(find.text('Veja se a letra está certa:'), findsOneWidget);
      expect(find.text('2 · Título 2'), findsOneWidget);
      expect(find.textContaining('estrofe um do hino 2'), findsOneWidget);
    });

    testWidgets('diz como entendeu o texto', (t) async {
      await _montar(t, copiado: [_hino(1), _hino(2)].join('\n'));
      await _colar(t);
      expect(find.textContaining('começando assim: 15 - Título'),
          findsOneWidget);
    });

    testWidgets('o que falta aparece, em frase', (t) async {
      await _montar(t, copiado: [_hino(1), _hino(4)].join('\n'));
      await _colar(t);
      expect(find.text('Achei 2 hinos, do 1 ao 4. Faltam o 2 e o 3.'),
          findsOneWidget);
    });

    testWidgets('hino sem letra é avisado, e não entra', (t) async {
      await _montar(t, copiado: '1 - Título 1\n\n${_hino(2)}');
      await _colar(t);
      expect(find.textContaining('Sem letra, por isso NÃO entram: o 1.'),
          findsOneWidget);
      expect(find.text('Importar 1 hino'), findsOneWidget);
    });

    testWidgets('texto que não é hinário: avisa e NÃO oferece Importar',
        (t) async {
      await _montar(t, copiado: 'só uma conversa qualquer, sem hino nenhum');
      await _colar(t);
      expect(find.text('Não achei nenhum hino neste texto.'), findsOneWidget);
      expect(find.text('Importe'), findsNothing);
      // O título da barra também diz "Importar": o botão é o que tem número.
      expect(find.textContaining(RegExp(r'^Importar \d+ hino')), findsNothing);
    });

    testWidgets('nada copiado: diz o que fazer', (t) async {
      await _montar(t, copiado: '   ');
      await _colar(t);
      expect(find.textContaining('Não achei nada copiado'), findsOneWidget);
      expect(find.text('Confira'), findsNothing);
    });

    testWidgets('depois de colar, o botão vira "Colar de novo" e há Limpar',
        (t) async {
      await _montar(t, copiado: _hino(1));
      await _colar(t);
      expect(find.text('Colar de novo'), findsOneWidget);
      expect(find.text('Limpar'), findsOneWidget);

      await t.tap(find.text('Limpar'));
      await t.pump();
      expect(find.text('Colar o texto copiado'), findsOneWidget);
      expect(find.text('Confira'), findsNothing);
    });
  });

  group('o hinário escolhido vale', () {
    testWidgets('o mesmo número vale na Harpa e não no Cantor', (t) async {
      // O hino 600 existe na Harpa (até 640) e não no Cantor (até 581).
      await _montar(t, copiado: _hino(600));
      await _colar(t);
      expect(find.text('Achei 1 hino: o 600.'), findsOneWidget);

      // A tela já rolou até a conferência: volta ao topo, como a pessoa faria.
      await t.ensureVisible(find.text('Cantor Cristão'));
      await t.tap(find.text('Cantor Cristão'));
      await t.pumpAndSettle();
      expect(find.text('Não achei nenhum hino neste texto.'), findsOneWidget);
    });
  });

  group('a confirmação', () {
    testWidgets('Importar pergunta antes, e Cancelar não grava nada',
        (t) async {
      await _montar(t, copiado: [_hino(1), _hino(2)].join('\n'));
      await _colar(t);

      await t.ensureVisible(find.text('Importar 2 hinos'));
      await t.tap(find.text('Importar 2 hinos'));
      await t.pumpAndSettle();

      expect(find.text('Importar 2 hinos?'), findsOneWidget);
      expect(find.textContaining('O repertório do ministério não muda.'),
          findsOneWidget);

      await t.tap(find.text('Cancelar'));
      await t.pumpAndSettle();
      expect(find.text('Importar 2 hinos?'), findsNothing);
      // Continua na conferência, com o botão de volta.
      expect(find.text('Importar 2 hinos'), findsOneWidget);
      expect(find.textContaining('Gravando'), findsNothing);
    });
  });

  group('colar à mão', () {
    testWidgets('o campo é de várias linhas, para não perder as quebras',
        (t) async {
      // No navegador, campo de uma linha vira <input> e descarta as quebras
      // de linha do que se cola — o hinário viraria um parágrafo só.
      await _montar(t);
      await t.ensureVisible(find.text('Colar à mão'));
      await t.tap(find.text('Colar à mão'));
      await t.pump();
      final campo = t.widget<TextField>(find.byType(TextField));
      expect(campo.keyboardType, TextInputType.multiline);
    });

    testWidgets('texto colado no campo é lido do mesmo jeito', (t) async {
      await _montar(t);
      await t.ensureVisible(find.text('Colar à mão'));
      await t.tap(find.text('Colar à mão'));
      await t.pump();
      await t.enterText(find.byType(TextField), [_hino(1), _hino(2)].join('\n'));
      await t.ensureVisible(find.text('Ler este texto'));
      await t.tap(find.text('Ler este texto'));
      await t.pumpAndSettle();
      expect(find.text('Achei 2 hinos, do 1 ao 2.'), findsOneWidget);
    });
  });

  group('o hinário inteiro', () {
    testWidgets('640 hinos colados: acha tudo e a tela aguenta', (t) async {
      final tudo = [for (var n = 1; n <= 640; n++) _hino(n)].join('\n');
      await _montar(t, copiado: tudo);
      await _colar(t);
      expect(find.text('Achei 640 hinos, do 1 ao 640.'), findsOneWidget);
      expect(find.text('Importar 640 hinos'), findsOneWidget);
    });
  });
}
