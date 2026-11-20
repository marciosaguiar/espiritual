// Projetar a letra no culto: dividir em slides e entender as teclas.
//
// Quem projeta está de pé, com a igreja olhando para a tela: slide que corta
// uma estrofe ao meio, ou tecla que não faz o que se espera, aparece para
// todo mundo. A conta é pura e tem teste por isso.
//
// TODO o texto é inventado.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:levitasync/core/utils/projetar_letra.dart';

void main() {
  group('dividir a letra em slides', () {
    const letra = '1 Primeira linha da estrofe um\n'
        'segunda linha da estrofe um\n'
        '\n'
        'REFRÃO\n'
        'Linha do refrão, uma\n'
        'linha do refrão, duas\n'
        '\n'
        '2 Primeira linha da estrofe dois\n'
        'segunda linha da estrofe dois';

    test('um slide por estrofe, na ordem', () {
      final s = dividirEmSlides(letra);
      expect(s.length, 3);
      expect(s[0].linhas, ['Primeira linha da estrofe um', 'segunda linha da estrofe um']);
      expect(s[2].linhas.first, 'Primeira linha da estrofe dois');
    });

    test('o número da estrofe sai do texto e vira o rótulo', () {
      final s = dividirEmSlides(letra);
      expect(s[0].rotulo, '1');
      expect(s[2].rotulo, '2');
      expect(s[0].linhas.any((l) => l.startsWith('1 ')), isFalse);
    });

    test('REFRÃO (e [côro]) vira rótulo, não linha cantada', () {
      final s = dividirEmSlides(letra);
      expect(s[1].rotulo, 'Refrão');
      expect(s[1].linhas, ['Linha do refrão, uma', 'linha do refrão, duas']);
      final c = dividirEmSlides('[côro]\nExultai!\nVinde todos');
      expect(c.single.rotulo, 'Côro');
      expect(c.single.linhas, ['Exultai!', 'Vinde todos']);
    });

    test('marcadores [1] [2] do hinário viram rótulo', () {
      final s = dividirEmSlides('[1]\nEis a primeira\nlinha\n[2]\nEis a segunda');
      expect(s.map((e) => e.rotulo), ['1', '2']);
      expect(s[0].linhas, ['Eis a primeira', 'linha']);
    });

    test('estrofe comprida é partida em slides menores, sem cortar verso',
        () {
      final longa = List.generate(12, (i) => 'verso número ${i + 1}').join('\n');
      final s = dividirEmSlides(longa, maximoDeLinhas: 4);
      expect(s.length, 3);
      expect(s.every((e) => e.linhas.length <= 4), isTrue);
      expect(s.expand((e) => e.linhas).toList(),
          List.generate(12, (i) => 'verso número ${i + 1}'));
    });

    test('não perde nem repete nenhuma linha', () {
      final todas = dividirEmSlides(letra, maximoDeLinhas: 2)
          .expand((e) => e.linhas)
          .toList();
      expect(todas, [
        'Primeira linha da estrofe um',
        'segunda linha da estrofe um',
        'Linha do refrão, uma',
        'linha do refrão, duas',
        'Primeira linha da estrofe dois',
        'segunda linha da estrofe dois',
      ]);
    });

    test('linhas em branco sobrando e espaços não viram slide vazio', () {
      final s = dividirEmSlides('\n\n  Um verso  \n\n\n\n  Outro  \n\n');
      expect(s.length, 2);
      expect(s[0].linhas, ['Um verso']);
    });

    test('letra vazia: nenhum slide (a tela avisa, em vez de ficar preta)',
        () {
      expect(dividirEmSlides(''), isEmpty);
      expect(dividirEmSlides('   \n\n  '), isEmpty);
    });

    test('a letra com ACORDES sai sem eles: projetar nunca mostra cifra', () {
      const cifra = 'G        D\nAmazing grace, how sweet\nC      G\nthe sound';
      final s = dividirEmSlides(cifra);
      expect(s.expand((e) => e.linhas).any((l) => l.trim() == 'G        D'),
          isFalse);
      expect(s.expand((e) => e.linhas), contains('Amazing grace, how sweet'));
    });
  });

  group('as teclas', () {
    AcaoDoPalco? a(LogicalKeyboardKey k, {bool shift = false}) =>
        acaoDaTecla(k, shift: shift);

    test('espaço e setas para a frente avançam; para trás, voltam', () {
      for (final k in [
        LogicalKeyboardKey.space,
        LogicalKeyboardKey.arrowRight,
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.pageDown,
      ]) {
        expect(a(k), AcaoDoPalco.proxima, reason: k.keyLabel);
      }
      for (final k in [
        LogicalKeyboardKey.arrowLeft,
        LogicalKeyboardKey.arrowUp,
        LogicalKeyboardKey.pageUp,
        LogicalKeyboardKey.backspace,
      ]) {
        expect(a(k), AcaoDoPalco.anterior, reason: k.keyLabel);
      }
    });

    test('Shift+espaço volta (como todo apresentador de slides)', () {
      expect(a(LogicalKeyboardKey.space, shift: true), AcaoDoPalco.anterior);
    });

    test('Home e End vão ao começo e ao fim', () {
      expect(a(LogicalKeyboardKey.home), AcaoDoPalco.primeira);
      expect(a(LogicalKeyboardKey.end), AcaoDoPalco.ultima);
    });

    test('Esc sai; F alterna tela cheia', () {
      expect(a(LogicalKeyboardKey.escape), AcaoDoPalco.sair);
      expect(a(LogicalKeyboardKey.keyF), AcaoDoPalco.telaCheia);
    });

    test('Enter também avança (o botão do apresentador costuma ser Enter)',
        () {
      expect(a(LogicalKeyboardKey.enter), AcaoDoPalco.proxima);
    });

    test('tecla qualquer não faz nada', () {
      expect(a(LogicalKeyboardKey.keyQ), isNull);
      expect(a(LogicalKeyboardKey.digit5), isNull);
    });

    test('Shift+→ e Shift+← trocam de música no Modo ao vivo', () {
      expect(acaoDaTecla(LogicalKeyboardKey.arrowRight, shift: true),
          AcaoDoPalco.proximaMusica);
      expect(acaoDaTecla(LogicalKeyboardKey.arrowLeft, shift: true),
          AcaoDoPalco.musicaAnterior);
    });
  });

  group('o tamanho da letra', () {
    test('cabe na largura: linha comprida usa fonte menor', () {
      final curta = tamanhoDaFonte(
          linhas: ['Amém'], largura: 1280, altura: 720);
      final longa = tamanhoDaFonte(
          linhas: ['uma linha muito comprida que precisa caber inteira na tela sem quebrar'],
          largura: 1280,
          altura: 720);
      expect(longa, lessThan(curta));
    });

    test('mais linhas, fonte menor — todas cabem na altura', () {
      final duas = tamanhoDaFonte(
          linhas: ['um verso', 'outro verso'], largura: 1280, altura: 720);
      final oito = tamanhoDaFonte(
          linhas: List.filled(8, 'um verso'), largura: 1280, altura: 720);
      expect(oito, lessThan(duas));
    });

    test('nunca passa dos limites, em telas de qualquer tamanho', () {
      for (final w in [320.0, 1280.0, 3840.0]) {
        final f = tamanhoDaFonte(linhas: ['Amém'], largura: w, altura: w / 2);
        expect(f, inInclusiveRange(18, 200));
      }
    });
  });
}
