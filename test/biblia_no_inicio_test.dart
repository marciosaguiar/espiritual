// A Bíblia está na tela principal.
//
// Ela tinha ido para a aba Músicas na rodada "menos é mais", e quem lê a Bíblia
// antes do culto não a achava. O que o teste guarda: o atalho está NO INÍCIO, em
// todos os tamanhos, abre a Bíblia ao toque, e não empurra o cartão do culto nem
// as pendências para fora do primeiro olhar (a razão de ela ter saído).
//
// TODO o texto é inventado.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:levitasync/presentation/screens/biblia/biblia_screen.dart';
import 'package:levitasync/presentation/screens/home/home_screen.dart';

import 'utilitarios/app_inventado.dart';
import 'utilitarios/fontes.dart';

void main() {
  // A fonte de teste é mais larga que a Poppins e faz sobrar linha onde, no
  // celular, cabe: sem a do app, o teste de layout reprova o que está certo.
  setUpAll(carregarFontesDoApp);

  for (final largura in const [375, 768, 1280]) {
    final tam = tamanhos[largura]!;
    group('a $largura px', () {
      testWidgets('o Início tem o atalho da Bíblia, e ele está à vista',
          (t) async {
        addTearDown(t.view.reset);
        await montarApp(t, tam: tam);
        final atalho = find.descendant(
            of: find.byType(HomeScreen), matching: find.text('Bíblia'));
        expect(atalho, findsOneWidget);
        final r = t.getRect(atalho);
        expect(r.bottom, lessThan(tam.altura),
            reason: 'o atalho tem de caber na primeira tela, sem rolar');
      });

      testWidgets('tocar nele abre a Bíblia', (t) async {
        addTearDown(t.view.reset);
        await montarApp(t, tam: tam);
        await t.tap(find.descendant(
            of: find.byType(HomeScreen), matching: find.text('Bíblia')));
        await assentar(t);
        expect(find.byType(BibliaScreen), findsOneWidget);
      });

      testWidgets('fica na barra de cima, ao lado do avatar, sem empurrar o culto',
          (t) async {
        addTearDown(t.view.reset);
        await montarApp(t, tam: tam);
        final atalho = find.descendant(
            of: find.byType(HomeScreen), matching: find.text('Bíblia'));
        final avatar = find.descendant(
            of: find.byType(HomeScreen), matching: find.byType(CircleAvatar));
        final r = t.getRect(atalho);
        // Na faixa do topo (a barra tem 120 px de altura quando aberta)...
        expect(r.top, lessThan(120));
        // ...e à ESQUERDA do avatar, na mesma linha.
        expect(r.right, lessThan(t.getRect(avatar).left));
        expect((r.center.dy - t.getRect(avatar).center.dy).abs(), lessThan(8));
      });

      testWidgets('o toque é grande o bastante para um dedo (44 px de altura)',
          (t) async {
        addTearDown(t.view.reset);
        await montarApp(t, tam: tam);
        final caixa = find
            .ancestor(
                of: find.descendant(
                    of: find.byType(HomeScreen), matching: find.text('Bíblia')),
                matching: find.byType(Container))
            .first;
        expect(t.getSize(caixa).height, greaterThanOrEqualTo(40));
      });
    });
  }

  testWidgets('a Bíblia continua também dentro da aba Músicas', (t) async {
    addTearDown(t.view.reset);
    await montarApp(t, tam: tamanhos[375]!, aba: 1);
    expect(find.text('Bíblia'), findsOneWidget);
  });
}
