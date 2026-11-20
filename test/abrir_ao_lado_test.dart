// Tocar num item de uma lista, em tela larga, abre o detalhe AO LADO.
//
// O defeito que isto cobre: no Repertório, a 2.400 px, a música abria em tela
// cheia e o painel da direita continuava dizendo "Escolha uma música". Vinha
// da faixa "Sugestão de repertório", que abria a música por `Navigator.push`
// — o único caminho que não passava pelo painel. O teste de antes tocava na
// PRIMEIRA música da tela, que era da lista comum, e por isso nunca viu.
//
// Por isso o teste de agora toca em CADA lugar de onde uma música pode ser
// aberta: a sugestão e a lista.
//
// TODO o texto é inventado.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:levitasync/data/models/scale_model.dart';
import 'package:levitasync/presentation/providers/scale_provider.dart';
import 'package:levitasync/presentation/screens/scale/scale_screen.dart';
import 'package:levitasync/presentation/widgets/songs/sugestoes_do_dia.dart';
import 'package:table_calendar/table_calendar.dart';

import 'utilitarios/app_inventado.dart';
import 'utilitarios/dados_inventados.dart';
import 'utilitarios/fontes.dart';

const _monitor = Tamanho(1280, 800, 1);
const _monitorGrande = Tamanho(1920, 1080, 1);

/// Um provider de cultos que "cria" na memória, sem banco.
class _EscalaQueCria extends ScaleProvider {
  @override
  Future<String?> createScale(ScaleModel scale) async {
    carregarParaTeste([...scales, scale]);
    return null;
  }
}

/// O painel da direita está mostrando alguma coisa, e não o "escolha um item"?
void _abriuAoLado(WidgetTester t, {required String lista}) {
  expect(find.text('Escolha uma música'), findsNothing,
      reason: 'o painel ainda diz "escolha"');
  expect(find.textContaining(lista), findsWidgets,
      reason: 'a lista tem de continuar na tela');
}

void main() {
  setUpAll(carregarFontesDoApp);

  for (final tam in [_monitor, _monitorGrande]) {
    group('Repertório a ${tam.largura} px', () {
      testWidgets('a sugestão vem FECHADA, e a lista tem título e contagem',
          (t) async {
        addTearDown(t.view.reset);
        await montarApp(t, tam: tam, aba: 1);
        expect(find.text('Sugestão de repertório'), findsOneWidget);
        expect(find.textContaining('Escolhidas pelo dia'), findsNothing,
            reason: 'fechada: as quatro músicas não repetem a lista');
        expect(find.textContaining('Todas as músicas ('), findsOneWidget);
      });

      testWidgets('abrir a sugestão mostra quatro músicas e diz que também '
          'estão na lista', (t) async {
        addTearDown(t.view.reset);
        await montarApp(t, tam: tam, aba: 1);
        await t.tap(find.text('Sugestão de repertório'));
        await assentar(t);
        expect(find.textContaining('Escolhidas pelo dia'), findsOneWidget);
        expect(
          find.descendant(
              of: find.byType(SugestoesDoDia), matching: find.byIcon(Icons.music_note_rounded)),
          findsNWidgets(4),
        );
      });

      testWidgets('tocar numa música da SUGESTÃO abre ao lado', (t) async {
        addTearDown(t.view.reset);
        await montarApp(t, tam: tam, aba: 1);
        await t.tap(find.text('Sugestão de repertório'));
        await assentar(t);

        final linhas = find.descendant(
            of: find.byType(SugestoesDoDia),
            matching: find.byIcon(Icons.music_note_rounded));
        expect(linhas, findsNWidgets(4));
        // CADA uma das quatro, não só a primeira.
        for (var i = 0; i < 4; i++) {
          await t.tap(linhas.at(i));
          await assentar(t);
          _abriuAoLado(t, lista: 'Todas as músicas');
          expect(
            t.getRect(find.text('Todas as músicas (16)')).right,
            lessThan(t.getRect(find.textContaining('Tom').first).left),
            reason: 'o detalhe tem de estar À DIREITA da lista',
          );
        }
      });

      testWidgets('tocar nas músicas da LISTA abre ao lado', (t) async {
        addTearDown(t.view.reset);
        await montarApp(t, tam: tam, aba: 1);
        await t.tap(find.text('Aliança eterna').first);
        await assentar(t);
        _abriuAoLado(t, lista: 'Todas as músicas');
      });
    });
  }

  group('o que só um navegador de verdade mostrou', () {
    testWidgets('clicar no ESPAÇO VAZIO da linha da sugestão também abre',
        (t) async {
      addTearDown(t.view.reset);
      await montarApp(t, tam: _monitor, aba: 1);
      await t.tap(find.text('Sugestão de repertório'));
      await assentar(t);

      // O espaço à direita do nome curto, onde não há texto nem ícone: com o
      // `GestureDetector` do jeito antigo o clique caía no vazio.
      final nome = find.descendant(
          of: find.byType(SugestoesDoDia), matching: find.text('Aliança eterna'));
      final r = t.getRect(nome);
      await t.tapAt(Offset(r.right + 60, r.center.dy));
      await assentar(t);
      expect(find.text('Escolha uma música'), findsNothing,
          reason: 'o clique no vazio da linha não abriu nada');
    });

    testWidgets('com a música aberta ao lado, a lista e a navegação seguem '
        'na árvore de acessibilidade', (t) async {
      addTearDown(t.view.reset);
      final semantica = t.ensureSemantics();
      await montarApp(t, tam: _monitor, aba: 1);
      await t.tap(find.text('Aliança eterna').first);
      await assentar(t);

      // O `Navigator` do painel põe uma barreira que bloqueia a semântica de
      // tudo o que veio antes dela. Sem a fronteira, a lista e a barra
      // lateral deixavam de existir para quem usa leitor de tela.
      expect(find.bySemanticsLabel(RegExp('Todas as músicas')), findsWidgets,
          reason: 'a lista sumiu para o leitor de tela');
      expect(find.bySemanticsLabel(RegExp('^Escala')), findsWidgets,
          reason: 'a navegação sumiu para o leitor de tela');
      semantica.dispose();
    });
  });

  group('Esc fecha o detalhe', () {
    testWidgets('na música aberta ao lado, volta ao "escolha uma música"',
        (t) async {
      addTearDown(t.view.reset);
      await montarApp(t, tam: _monitor, aba: 1);
      await t.tap(find.text('Aliança eterna').first);
      await assentar(t);
      expect(find.text('Escolha uma música'), findsNothing);

      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await assentar(t);
      expect(find.text('Escolha uma música'), findsOneWidget);
    });

    testWidgets('sem nada aberto, o Esc não faz nada', (t) async {
      addTearDown(t.view.reset);
      await montarApp(t, tam: _monitor, aba: 1);
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await assentar(t);
      expect(find.text('Escolha uma música'), findsOneWidget);
    });

    testWidgets('só age na aba que está à vista', (t) async {
      addTearDown(t.view.reset);
      await montarApp(t, tam: _monitor, aba: 2);
      // Abre um culto na Escala...
      await t.tap(find.textContaining('Culto de quarta').first);
      await assentar(t);
      expect(find.text('Escolha um culto'), findsNothing);

      // ...vai para as Músicas, abre uma música e fecha com o Esc.
      await t.tap(find.text('Músicas').first);
      await assentar(t);
      await t.tap(find.text('Aliança eterna').first);
      await assentar(t);
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await assentar(t);
      expect(find.text('Escolha uma música'), findsOneWidget);

      // O culto da outra aba NÃO foi fechado pelo mesmo Esc.
      await t.tap(find.text('Escala').first);
      await assentar(t);
      expect(find.text('Escolha um culto'), findsNothing,
          reason: 'o Esc da aba Músicas fechou o culto da aba Escala');
    });
  });

  group('Escala', () {
    testWidgets('o culto recém-criado abre AO LADO do calendário', (t) async {
      addTearDown(t.view.reset);
      await montarApp(t, tam: _monitor, aba: 2, escala: _EscalaQueCria());

      // Escolhe um dia sem culto, pelo próprio calendário (clicar no número
      // do dia seria frágil: o mês mostra dias de fora repetidos).
      final calendario =
          t.widget<TableCalendar<dynamic>>(find.byType(TableCalendar<dynamic>));
      final dia = DateTime.now().add(const Duration(days: 40));
      calendario.onDaySelected!(dia, dia);
      await assentar(t);

      await t.tap(find.byIcon(Icons.add_rounded));
      await assentar(t);
      await t.tap(find.text('Criar'));
      await assentar(t);

      expect(find.text('Escolha um culto'), findsNothing,
          reason: 'o culto criado abriu em tela cheia, não no painel');
      expect(find.text('Observações do culto'), findsWidgets);
      expect(find.text('Escala'), findsWidgets,
          reason: 'o calendário continua na tela');
    });

    testWidgets('o toque num aviso abre o culto AO LADO', (t) async {
      addTearDown(t.view.reset);
      final pedido = ValueNotifier<PedidoDeCulto?>(null);
      await montarApp(
        t,
        tam: _monitor,
        casa: Scaffold(body: ScaleScreen(pedido: pedido)),
      );
      expect(find.text('Escolha um culto'), findsOneWidget);

      pedido.value = PedidoDeCulto(cultosInventados().first);
      await assentar(t);
      expect(find.text('Escolha um culto'), findsNothing);
      expect(find.text('Observações do culto'), findsWidgets);
    });

    testWidgets('no celular o aviso abre o culto por cima, como sempre',
        (t) async {
      addTearDown(t.view.reset);
      final pedido = ValueNotifier<PedidoDeCulto?>(null);
      await montarApp(
        t,
        tam: const Tamanho(375, 812, 2),
        casa: Scaffold(body: ScaleScreen(pedido: pedido)),
      );
      pedido.value = PedidoDeCulto(cultosInventados().first);
      await assentar(t);
      expect(find.text('Observações do culto'), findsWidgets);
    });
  });
}
