// O tamanho de letra em que as linhas cabem sem quebrar.
//
// TODO o texto é inventado.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:levitasync/core/constants/hinarios.dart';
import 'package:levitasync/core/utils/ajuste_de_fonte.dart';
import 'package:levitasync/data/models/hino_da_biblioteca.dart';
import 'package:levitasync/presentation/screens/songs/hino_da_biblioteca_screen.dart';
import 'package:levitasync/presentation/widgets/common/responsivo.dart';

import 'utilitarios/app_inventado.dart';
import 'utilitarios/fontes.dart';

const _estilo = TextStyle(fontFamily: 'Poppins', height: 1.55);

double _larguraDe(String linha, double fonte) {
  final p = TextPainter(
    text: TextSpan(text: linha, style: _estilo.copyWith(fontSize: fonte)),
    textDirection: TextDirection.ltr,
  )..layout();
  return p.width;
}

const _longa = 'O Senhor é o meu pastor e nada me faltará, em verdes pastos';
const _letra = '1 Firmes na promessa,\n$_longa\nquem guarda o seu povo';

void main() {
  setUpAll(carregarFontesDoApp);

  group('tamanhoQueCabe', () {
    test('texto curto: fica no tamanho pedido', () {
      expect(
        tamanhoQueCabe(
            texto: 'luz no caminho', estilo: _estilo, largura: 600, maximo: 22),
        22,
      );
    });

    test('linha comprida: encolhe até caber, sem passar da largura', () {
      final largura = _larguraDe(_longa, 22) - 80; // não cabe em 22
      final f = tamanhoQueCabe(
          texto: _letra, estilo: _estilo, largura: largura, maximo: 22);
      expect(f, lessThan(22));
      expect(f, greaterThanOrEqualTo(16));
      expect(_larguraDe(_longa, f), lessThanOrEqualTo(largura),
          reason: 'a linha mais comprida ainda quebraria');
    });

    test('é o MAIOR tamanho que cabe: um a mais já quebraria', () {
      final largura = _larguraDe(_longa, 22) - 80;
      final f = tamanhoQueCabe(
          texto: _letra, estilo: _estilo, largura: largura, maximo: 22);
      expect(_larguraDe(_longa, f + 1), greaterThan(largura),
          reason: 'encolheu mais do que o preciso');
    });

    test('não cabe nem no mínimo: fica no tamanho pedido (a quebra é '
        'inevitável)', () {
      expect(
        tamanhoQueCabe(
            texto: _letra, estilo: _estilo, largura: 120, maximo: 22),
        22,
      );
    });

    test('nunca desce do mínimo', () {
      final largura = _larguraDe(_longa, 16) + 1; // cabe só no mínimo
      final f = tamanhoQueCabe(
          texto: _letra, estilo: _estilo, largura: largura, maximo: 30);
      expect(f, greaterThanOrEqualTo(16));
    });

    test('texto vazio, largura inválida ou máximo no mínimo: não mexe', () {
      expect(
          tamanhoQueCabe(texto: '', estilo: _estilo, largura: 100, maximo: 22),
          22);
      expect(
          tamanhoQueCabe(
              texto: _letra, estilo: _estilo, largura: 0, maximo: 22),
          22);
      expect(
          tamanhoQueCabe(
              texto: _letra,
              estilo: _estilo,
              largura: double.infinity,
              maximo: 22),
          22);
      expect(
          tamanhoQueCabe(
              texto: _letra,
              estilo: _estilo,
              largura: 100,
              maximo: 16,
              minimo: 16),
          16);
    });
  });

  group('na tela do hino', () {
    // Seis linhas escritas; se alguma quebrar, o parágrafo fica mais alto.
    final longa = [
      for (var i = 1; i <= 6; i++)
        '$i O Senhor é o meu pastor e nada me faltará, em verdes pastos',
    ].join('\n');

    Future<Finder> abrir(WidgetTester t, Tamanho tam) async {
      await montarApp(
        t,
        tam: tam,
        casa: Scaffold(
          // 640 é perto do que o painel dá a uma letra num monitor de 1280 px.
          body: ColunaCentral(
            largura: 640,
            child: HinoDaBibliotecaScreen(
              hinario: harpaCrista,
              hino: HinoDaBiblioteca(
                hinario: 'harpa',
                numero: 23,
                titulo: 'Pastor de todos',
                letra: longa,
              ),
            ),
          ),
        ),
      );
      return find.textContaining('O Senhor é o meu pastor');
    }

    double fonteDe(WidgetTester t, Finder f) =>
        t.widget<Text>(f).style!.fontSize!;

    testWidgets('tela larga: a letra encolhe e NENHUMA linha quebra', (t) async {
      addTearDown(t.view.reset);
      final letra = await abrir(t, tamanhos[1280]!);
      expect(fonteDe(t, letra), lessThan(22));
      final p = TextPainter(
        text: TextSpan(text: longa, style: t.widget<Text>(letra).style),
        textDirection: TextDirection.ltr,
      )..layout();
      expect(t.getSize(letra).height, closeTo(p.height, 1));
    });

    testWidgets('celular: o tamanho é o de sempre (22), mesmo que quebre',
        (t) async {
      addTearDown(t.view.reset);
      final letra = await abrir(t, tamanhos[375]!);
      expect(fonteDe(t, letra), 22);
    });

    testWidgets('depois do A+ o tamanho é EXATO, o da pessoa', (t) async {
      addTearDown(t.view.reset);
      final letra = await abrir(t, tamanhos[1280]!);
      final encolhida = fonteDe(t, letra);
      expect(encolhida, lessThan(22));

      await t.tap(find.byTooltip('Letra maior'));
      await t.pump();
      expect(fonteDe(t, letra), 24, reason: '22 + 2: o toque tem de valer');
    });
  });
}
