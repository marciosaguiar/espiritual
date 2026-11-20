// A tela cheia para projetar a letra, de verdade: abrir, avançar, sair.
//
// O que se confere é o que a igreja vê: a letra grande, uma estrofe por vez,
// sem cifra, e os botões sumindo para não ficarem na frente do telão.
//
// TODO o texto é inventado.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:levitasync/presentation/screens/songs/projetar_letra_screen.dart';

import 'utilitarios/app_inventado.dart';
import 'utilitarios/fontes.dart';

const _letra = '1 Primeira linha da estrofe um\n'
    'segunda linha da estrofe um\n'
    '\n'
    'REFRÃO\n'
    'Linha do refrão, uma\n'
    'linha do refrão, duas\n'
    '\n'
    '2 Primeira linha da estrofe dois\n'
    'segunda linha da estrofe dois';

Future<void> _abrir(WidgetTester t, {String letra = _letra, Size? tela}) async {
  final s = tela ?? const Size(1280, 720);
  t.view.physicalSize = s;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    home: ProjetarLetraScreen(
      titulo: 'Hino de teste',
      subtitulo: 'Hinário de teste, hino 1',
      letra: letra,
    ),
  ));
  await t.pump(const Duration(milliseconds: 400));
}

Future<void> _fechar(WidgetTester t) async {
  // Desmonta, para o relógio que esconde os botões não ficar pendente.
  await t.pumpWidget(const SizedBox.shrink());
}

void main() {
  setUpAll(carregarFontesDoApp);

  testWidgets('abre na PRIMEIRA estrofe, sem número de estrofe no verso',
      (t) async {
    await _abrir(t);
    expect(find.text('Primeira linha da estrofe um'), findsOneWidget);
    expect(find.text('segunda linha da estrofe um'), findsOneWidget);
    expect(find.text('Linha do refrão, uma'), findsNothing);
    expect(find.text('1'), findsOneWidget, reason: 'o rótulo da estrofe');
    expect(find.textContaining('1 de 3'), findsOneWidget);
    await _fechar(t);
  });

  testWidgets('espaço avança, Shift+espaço volta', (t) async {
    await _abrir(t);
    await t.sendKeyEvent(LogicalKeyboardKey.space);
    await t.pump();
    expect(find.text('Linha do refrão, uma'), findsOneWidget);
    expect(find.text('REFRÃO'), findsOneWidget);

    await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.space);
    await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await t.pump();
    expect(find.text('Primeira linha da estrofe um'), findsOneWidget);
    await _fechar(t);
  });

  testWidgets('as setas e o Enter também avançam; não passa do último',
      (t) async {
    await _abrir(t);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await t.pump();
    expect(find.textContaining('3 de 3'), findsOneWidget);
    expect(find.text('Primeira linha da estrofe dois'), findsOneWidget);
    await _fechar(t);
  });

  testWidgets('Home volta ao começo e End vai ao fim', (t) async {
    await _abrir(t);
    await t.sendKeyEvent(LogicalKeyboardKey.end);
    await t.pump();
    expect(find.textContaining('3 de 3'), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.home);
    await t.pump();
    expect(find.textContaining('1 de 3'), findsOneWidget);
    await _fechar(t);
  });

  testWidgets('a letra é GRANDE: o maior verso ocupa boa parte da largura',
      (t) async {
    await _abrir(t);
    final r = t.getRect(find.text('Primeira linha da estrofe um'));
    expect(r.width, greaterThan(1280 * 0.45));
    final fonte = t
        .widget<Text>(find.text('Primeira linha da estrofe um'))
        .style!
        .fontSize!;
    expect(fonte, greaterThan(40));
    await _fechar(t);
  });

  testWidgets('clicar à direita avança, no terço da esquerda volta', (t) async {
    await _abrir(t);
    await t.tapAt(const Offset(900, 360));
    await t.pump();
    expect(find.text('Linha do refrão, uma'), findsOneWidget);
    await t.tapAt(const Offset(100, 360));
    await t.pump();
    expect(find.text('Primeira linha da estrofe um'), findsOneWidget);
    await _fechar(t);
  });

  testWidgets('os botões SOMEM depois de 3 s parados — nada na frente do telão',
      (t) async {
    await _abrir(t);
    expect(t.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity, 1);
    await t.pump(const Duration(seconds: 4));
    expect(t.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity, 0);
    // E voltam quando a pessoa mexe.
    await t.sendKeyEvent(LogicalKeyboardKey.space);
    await t.pump();
    expect(t.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity, 1);
    await _fechar(t);
  });

  testWidgets('Esc sai da tela', (t) async {
    t.view.physicalSize = const Size(1280, 720);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => ProjetarLetraScreen.abrir(ctx,
                  titulo: 'Hino', letra: _letra),
              child: const Text('projetar'),
            ),
          ),
        ),
      ),
    ));
    await t.tap(find.text('projetar'));
    await t.pumpAndSettle();
    expect(find.text('Primeira linha da estrofe um'), findsOneWidget);

    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(find.text('Primeira linha da estrofe um'), findsNothing);
    expect(find.text('projetar'), findsOneWidget);
  });

  testWidgets('sem letra, a tela DIZ — em vez de ficar preta', (t) async {
    await _abrir(t, letra: '   ');
    expect(find.textContaining('ainda não tem letra'), findsOneWidget);
    // E as teclas não quebram.
    await t.sendKeyEvent(LogicalKeyboardKey.space);
    await t.sendKeyEvent(LogicalKeyboardKey.end);
    await t.pump();
    expect(t.takeException(), isNull);
    await _fechar(t);
  });

  testWidgets('a letra com acordes nunca mostra os acordes', (t) async {
    await _abrir(t, letra: 'G        D\nAmazing grace, how sweet\nC      G\nthe sound');
    expect(find.text('Amazing grace, how sweet'), findsOneWidget);
    expect(find.text('G        D'), findsNothing);
    await _fechar(t);
  });

  testWidgets('cabe a 375 px e a 1920 px, sem estourar', (t) async {
    for (final s in const [Size(375, 812), Size(1920, 1080)]) {
      await _abrir(t, tela: s);
      await t.sendKeyEvent(LogicalKeyboardKey.space);
      await t.pump();
      expect(t.takeException(), isNull, reason: '$s');
      await _fechar(t);
    }
  });

  group('os lugares de onde se projeta', () {
    testWidgets('a música do repertório: ⋯ → "Projetar a letra"', (t) async {
      addTearDown(t.view.reset);
      await montarApp(t, tam: const Tamanho(375, 812, 2), aba: 1);
      await t.tap(find.text('Grande é a tua fidelidade').first);
      await assentar(t);
      await t.tap(find.byTooltip('Mais opções'));
      await t.pumpAndSettle();
      await t.tap(find.text('Projetar a letra (tela cheia)'));
      // O menu fecha e só então a tela nova entra: duas animações.
      await t.pumpAndSettle();

      expect(find.byType(ProjetarLetraScreen), findsOneWidget);
      // O primeiro verso da letra inventada, sem o "1 " da estrofe.
      expect(find.textContaining('nos acompanha'), findsOneWidget);
      await _fechar(t);
    });
  });
}
