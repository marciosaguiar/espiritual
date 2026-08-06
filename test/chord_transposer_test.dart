import 'package:flutter_test/flutter_test.dart';
import 'package:levitasync/core/utils/chord_transposer.dart';

void main() {
  group('transposeText — preserva a letra', () {
    test('não altera palavras da letra em uma cifra colada da internet', () {
      const chart = 'G              D\n'
          'E o Senhor é bom\n'
          'Em             C\n'
          'A Sua graça me basta';

      expect(
        ChordTransposer.transposeText(chart, 2),
        'A              E\n'
        'E o Senhor é bom\n'
        'F#m             D\n'
        'A Sua graça me basta',
      );
    });

    test('"Em nome de Jesus" não vira acorde', () {
      expect(
        ChordTransposer.transposeText('Em nome de Jesus', 2),
        'Em nome de Jesus',
      );
    });

    test('letra em caixa alta é preservada', () {
      expect(
        ChordTransposer.transposeText('A GRACA DE DEUS', 2),
        'A GRACA DE DEUS',
      );
    });
  });

  group('transposeText — transpõe acordes', () {
    test('linha só de acordes', () {
      expect(ChordTransposer.transposeText('C  Am  F  G7', 2), 'D  Bm  G  A7');
    });

    test('acordes entre colchetes no meio da letra', () {
      expect(
        ChordTransposer.transposeText('[G]Eu te [D]louvarei', 2),
        '[A]Eu te [E]louvarei',
      );
    });

    test('acorde com baixo invertido', () {
      expect(ChordTransposer.transposeText('G/B  C/E', 2), 'A/C#  D/F#');
    });

    test('cifra em bemol continua em bemol', () {
      expect(ChordTransposer.transposeText('Bb  Eb', 2), 'C  F');
    });

    test('barras de compasso e repetição não atrapalham', () {
      expect(
        ChordTransposer.transposeText('| C | Am | x2', 2),
        '| D | Bm | x2',
      );
    });

    test('preserva o espaçamento para os acordes ficarem sobre a sílaba', () {
      expect(
        ChordTransposer.transposeText('C       G', 2),
        'D       A',
      );
    });
  });

  group('transposeText — casos de borda', () {
    test('zero semitons devolve o texto original', () {
      const chart = 'C  G\nEu te louvarei';
      expect(ChordTransposer.transposeText(chart, 0), chart);
    });

    test('texto vazio', () {
      expect(ChordTransposer.transposeText('', 3), '');
    });

    test('valor negativo dá a volta corretamente', () {
      expect(ChordTransposer.transposeText('C  D', -2), 'A#  C');
    });

    test('doze semitons volta ao mesmo tom', () {
      expect(ChordTransposer.transposeText('C  Am  F', 12), 'C  Am  F');
    });

    test('acordes entre parênteses', () {
      expect(ChordTransposer.transposeText('(C)  (G7)', 2), '(D)  (A7)');
    });

    // Um "|" sozinho casa como abertura e como fechamento ao mesmo tempo;
    // sem proteção, recortar o miolo estoura o índice e derruba a tela.
    test('linha só de barras não quebra', () {
      expect(ChordTransposer.transposeText('| | |', 2), '| | |');
    });

    test('linha só de pontuação não quebra', () {
      expect(ChordTransposer.transposeText(':  |  %', 2), ':  |  %');
    });
  });

  group('isChordLine', () {
    test('reconhece linha de acordes', () {
      expect(ChordTransposer.isChordLine('C  Am7  F#m  G/B'), isTrue);
    });

    test('rejeita linha de letra', () {
      expect(ChordTransposer.isChordLine('E o Senhor é bom'), isFalse);
    });

    test('rejeita linha vazia', () {
      expect(ChordTransposer.isChordLine('   '), isFalse);
    });
  });

  group('getKeyName', () {
    test('sobe o tom informado', () {
      expect(ChordTransposer.getKeyName('C', 2), 'D');
      expect(ChordTransposer.getKeyName('G', 1), 'G#/Ab');
    });

    test('tom desconhecido é devolvido sem alteração', () {
      expect(ChordTransposer.getKeyName('H', 2), 'H');
    });
  });

  group('getTransposeDisplay', () {
    test('formata o deslocamento', () {
      expect(ChordTransposer.getTransposeDisplay(0), 'Original');
      expect(ChordTransposer.getTransposeDisplay(3), '+3');
      expect(ChordTransposer.getTransposeDisplay(-3), '-3');
    });
  });
}
