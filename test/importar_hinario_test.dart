// Ler um hinário colado: achar onde cada hino começa.
//
// TODO o texto aqui é INVENTADO ("Título 7", "palavras da estrofe"). A regra
// do projeto é não embarcar letra de hino nenhum, nem em teste — e o que se
// testa é a estrutura do texto, não o que ele diz.

import 'package:flutter_test/flutter_test.dart';
import 'package:levitasync/core/constants/hinarios.dart';
import 'package:levitasync/core/utils/importar_hinario.dart';

/// Uma estrofe de mentira, numerada do jeito que hinário numera estrofe.
String _estrofe(int n, {String marca = '.'}) =>
    '$n$marca palavras inventadas da estrofe número $n deste hino de teste';

/// Um hino de mentira no formato "N - TÍTULO": três estrofes numeradas com
/// ponto, que é exatamente o que confunde com o começo de outro hino.
String _hino(int n, {String titulo = '', String cabecalho = ''}) {
  final t = titulo.isEmpty ? 'Título $n' : titulo;
  final c = cabecalho.isEmpty ? '$n - $t' : cabecalho;
  return '$c\n${_estrofe(1)}\n\n${_estrofe(2)}\n\n${_estrofe(3)}\n';
}

String _hinario(int de, int ate) =>
    [for (var n = de; n <= ate; n++) _hino(n)].join('\n');

void main() {
  group('o formato "15 - Título"', () {
    test('acha todos os hinos e separa as letras', () {
      final r = ImportarHinario.analisar(_hinario(1, 3), harpaCrista);
      expect(r.formato, FormatoDoHinario.traco);
      expect(r.hinos.map((h) => h.numero), [1, 2, 3]);
      expect(r.hinos[1].titulo, 'Título 2');
      expect(r.hinos[1].letra, startsWith('1. palavras inventadas'));
      expect(r.hinos[1].letra, endsWith('deste hino de teste'));
    });

    test('a estrofe "2." NÃO vira o hino 2 — é o caso que engana', () {
      // Cada hino tem as estrofes 1., 2. e 3. Lidas como começo de hino,
      // elas dariam hinos 1, 2 e 3 em todo lugar.
      final r = ImportarHinario.analisar(_hinario(1, 5), harpaCrista);
      expect(r.hinos.length, 5);
      for (final h in r.hinos) {
        expect(h.letra.split('\n\n').length, 3,
            reason: 'hino ${h.numero} deveria ter 3 estrofes');
      }
    });

    test('hino na ordem do número, mesmo que o texto venha embaralhado', () {
      final texto = [_hino(3), _hino(1), _hino(2)].join('\n');
      final r = ImportarHinario.analisar(texto, harpaCrista);
      expect(r.hinos.map((h) => h.numero), [1, 2, 3]);
    });
  });

  group('os outros formatos', () {
    test('"HINO 15" com o título na linha de baixo', () {
      const texto = 'HINO 15\nTítulo quinze\n1. uma estrofe inventada qualquer\n'
          '2. outra estrofe inventada qualquer\n\n'
          'HINO 16\nTítulo dezesseis\n1. mais uma estrofe inventada\n'
          '2. e ainda mais uma estrofe inventada\n';
      final r = ImportarHinario.analisar(texto, harpaCrista);
      expect(r.formato, FormatoDoHinario.hino);
      expect(r.hinos.map((h) => h.numero), [15, 16]);
      expect(r.hinos[0].titulo, 'Título quinze');
      expect(r.hinos[0].letra, startsWith('1. uma estrofe'));
    });

    test('"Nº 15 - Título" na mesma linha', () {
      const texto = 'Nº 15 - Título quinze\n1. uma estrofe inventada qualquer\n'
          '2. outra estrofe inventada qualquer\n';
      final r = ImportarHinario.analisar(texto, harpaCrista);
      expect(r.formato, FormatoDoHinario.hino);
      expect(r.hinos.single.numero, 15);
      expect(r.hinos.single.titulo, 'Título quinze');
    });

    test('o número sozinho numa linha', () {
      const texto = '15\nTítulo quinze\numa estrofe inventada qualquer\n'
          'outra linha inventada qualquer\n\n'
          '16\nTítulo dezesseis\numa estrofe inventada qualquer\n'
          'outra linha inventada qualquer\n';
      final r = ImportarHinario.analisar(texto, harpaCrista);
      expect(r.formato, FormatoDoHinario.sozinho);
      expect(r.hinos.map((h) => h.numero), [15, 16]);
      expect(r.hinos[1].titulo, 'Título dezesseis');
    });

    test('"15. Título" quando as estrofes não são numeradas', () {
      const texto = '15. Título quinze\numa estrofe inventada qualquer\n'
          'outra linha inventada qualquer\n\n'
          '16. Título dezesseis\numa estrofe inventada qualquer\n'
          'outra linha inventada qualquer\n';
      final r = ImportarHinario.analisar(texto, harpaCrista);
      expect(r.formato, FormatoDoHinario.ponto);
      expect(r.hinos.map((h) => h.numero), [15, 16]);
    });

    test('"15 TÍTULO" em maiúsculas, sem hífen nenhum', () {
      const texto = '15 TÍTULO QUINZE\numa estrofe inventada qualquer\n'
          'outra linha inventada qualquer\n\n'
          '16 TÍTULO DEZESSEIS\numa estrofe inventada qualquer\n'
          'outra linha inventada qualquer\n';
      final r = ImportarHinario.analisar(texto, harpaCrista);
      expect(r.formato, FormatoDoHinario.caixaAlta);
      expect(r.hinos.map((h) => h.titulo), ['Título Quinze', 'Título Dezesseis']);
    });

    test('formato forçado vale mesmo que outro ache mais hinos', () {
      final texto = _hinario(1, 4);
      final r = ImportarHinario.analisar(texto, harpaCrista,
          formato: FormatoDoHinario.ponto);
      // No formato "ponto" só as estrofes casam, e elas não têm letra que
      // chegue: o app escolheu o que a pessoa mandou e não achou hino.
      expect(r.formato, FormatoDoHinario.ponto);
      expect(r.hinos.length, lessThan(4));
    });
  });

  group('título', () {
    test('todo em maiúsculas vira maiúsculas e minúsculas', () {
      expect(ImportarHinario.tituloLimpo('CHUVAS DE GRAÇA'), 'Chuvas de Graça');
      expect(ImportarHinario.tituloLimpo('GRANDE É O SENHOR'),
          'Grande é o Senhor');
    });

    test('a primeira palavra fica maiúscula mesmo sendo "de", "o"…', () {
      expect(ImportarHinario.tituloLimpo('O SENHOR É MEU PASTOR'),
          'O Senhor é meu Pastor');
    });

    test('título que já tem minúscula fica intacto', () {
      expect(ImportarHinario.tituloLimpo('Sou Grato'), 'Sou Grato');
      expect(ImportarHinario.tituloLimpo('Quão grande és tu'),
          'Quão grande és tu');
    });

    test('sigla curta não é tratada como título gritado', () {
      // "ABC" tem três letras e é maiúscula: vira "Abc". Já "ok" (minúscula)
      // e dois caracteres ficam como estão.
      expect(ImportarHinario.tituloLimpo('Ok'), 'Ok');
    });

    test('pontilhado de sumário e página saem', () {
      expect(ImportarHinario.tituloLimpo('Sou Grato ........ 23'), 'Sou Grato');
      expect(ImportarHinario.tituloLimpo('Sou Grato . . . . 23'), 'Sou Grato');
    });

    test('marcação de texto e ponto final saem', () {
      expect(ImportarHinario.tituloLimpo('**Sou Grato**'), 'Sou Grato');
      expect(ImportarHinario.tituloLimpo('Sou Grato.'), 'Sou Grato');
    });

    test('número no fim do título de verdade fica (Salmo 23)', () {
      expect(ImportarHinario.tituloLimpo('Salmo 23'), 'Salmo 23');
    });

    test('hífen no meio: cada parte começa com maiúscula', () {
      expect(ImportarHinario.tituloLimpo('CASA-GRANDE DO SENHOR'),
          'Casa-Grande do Senhor');
    });
  });

  group('o que atrapalha em texto de verdade', () {
    test('sumário no começo perde para o hino de letra', () {
      // As linhas do sumário parecem hino 1, 2 e 3, mas não têm letra.
      final texto = '1 - Título 1 ..... 5\n2 - Título 2 ..... 6\n'
          '3 - Título 3 ..... 7\n\n${_hinario(1, 3)}';
      final r = ImportarHinario.analisar(texto, harpaCrista);
      expect(r.hinos.length, 3);
      expect(r.hinos.first.letra, startsWith('1. palavras'));
      expect(r.repetidos, [1, 2, 3]);
    });

    test('rodapé com ano (2024 - CPAD) não entra na letra do último hino', () {
      final texto = '${_hinario(1, 2)}\n2024 - Editora de Mentira\n';
      final r = ImportarHinario.analisar(texto, harpaCrista);
      expect(r.hinos.last.letra, isNot(contains('Editora')));
    });

    test('quebra de linha do Windows e espaço invisível não escondem hino', () {
      final texto = _hinario(1, 2)
          .replaceAll('\n', '\r\n')
          .replaceAll('2 - ', '2 -​ ');
      final r = ImportarHinario.analisar('﻿$texto', harpaCrista);
      expect(r.hinos.map((h) => h.numero), [1, 2]);
    });

    test('tabulação no começo da linha não atrapalha', () {
      final texto = _hinario(1, 2).replaceAll('\n1.', '\n\t1.');
      final r = ImportarHinario.analisar(texto, harpaCrista);
      expect(r.hinos.length, 2);
      expect(r.hinos.first.letra, startsWith('1. palavras'));
    });

    test('linhas em branco sobrando viram uma só, e as pontas são aparadas', () {
      const texto = '1 - Título um\n\n\n\n1. uma estrofe inventada qualquer\n'
          '\n\n\n2. outra estrofe inventada qualquer\n\n\n';
      final r = ImportarHinario.analisar(texto, harpaCrista);
      expect(r.hinos.single.letra,
          '1. uma estrofe inventada qualquer\n\n2. outra estrofe inventada qualquer');
    });

    test('verso comprido numerado não é título', () {
      final longa = 'x' * 120;
      final texto = '${_hinario(1, 1)}\n2 - $longa\n';
      final r = ImportarHinario.analisar(texto, harpaCrista);
      expect(r.hinos.length, 1);
      // A linha comprida continua sendo letra do hino 1.
      expect(r.hinos.single.letra, contains(longa));
    });
  });

  group('o que o hinário tem e o que não tem', () {
    test('número acima do último do hinário não é hino', () {
      final texto = '${_hinario(1, 2)}\n${_hino(700)}';
      final r = ImportarHinario.analisar(texto, harpaCrista);
      expect(r.hinos.map((h) => h.numero), [1, 2]);
      expect(r.foraDoLimite, 1);
    });

    test('o mesmo número vale num hinário e não vale em outro', () {
      final texto = _hino(600);
      expect(ImportarHinario.analisar(texto, harpaCrista).hinos.length, 1);
      expect(ImportarHinario.analisar(texto, cantorCristao).hinos, isEmpty);
    });

    test('zero não é hino', () {
      final r = ImportarHinario.analisar(_hino(0), harpaCrista);
      expect(r.hinos, isEmpty);
    });

    test('hino sem letra que chegue não entra, e é avisado', () {
      const texto = '1 - Título um\n\n2 - Título dois\n'
          '1. uma estrofe inventada qualquer de teste\n';
      final r = ImportarHinario.analisar(texto, harpaCrista);
      expect(r.hinos.map((h) => h.numero), [2]);
      expect(r.curtos, [1]);
    });

    test('letra gigante (o hino seguinte não foi reconhecido) fica de fora', () {
      final enorme = List.filled(400, 'uma linha inventada de teste que enche').join('\n');
      final texto = '1 - Título um\n$enorme\n\n${_hino(2)}';
      final r = ImportarHinario.analisar(texto, harpaCrista);
      expect(r.hinos.map((h) => h.numero), [2]);
      expect(r.grandes, [1]);
    });

    test('hino sem título reconhecido entra como "Hino N" e é avisado', () {
      final longa = 'y' * 150;
      final texto = '15\n$longa\numa estrofe inventada qualquer de teste\n';
      final r = ImportarHinario.analisar(texto, harpaCrista);
      expect(r.hinos.single.titulo, 'Hino 15');
      expect(r.semTitulo, [15]);
      // A linha que não coube como título continua sendo letra.
      expect(r.hinos.single.letra, contains(longa));
    });
  });

  group('o que falta', () {
    test('número que falta no meio é avisado', () {
      final texto = [_hino(1), _hino(2), _hino(4), _hino(5)].join('\n');
      final r = ImportarHinario.analisar(texto, harpaCrista);
      expect(r.faltando, [3]);
    });

    test('colar só uma parte não vira "590 faltando"', () {
      final r = ImportarHinario.analisar(_hinario(1, 50), harpaCrista);
      expect(r.faltando, isEmpty);
      expect(r.hinos.length, 50);
    });

    test('colar do 100 ao 120 também não acusa 1 a 99', () {
      final r = ImportarHinario.analisar(_hinario(100, 120), harpaCrista);
      expect(r.faltando, isEmpty);
      expect(r.primeiro, 100);
      expect(r.ultimoAchado, 120);
    });

    test('número repetido fica com a letra mais comprida', () {
      const curto = '5 - Título cinco\numa linha só\n';
      final texto = '$curto\n${_hino(5)}';
      final r = ImportarHinario.analisar(texto, harpaCrista);
      expect(r.hinos.single.letra, contains('estrofe número 3'));
      expect(r.repetidos, [5]);
    });
  });

  group('a frase que a tela mostra', () {
    test('tudo certo', () {
      final r = ImportarHinario.analisar(_hinario(1, 5), harpaCrista);
      expect(r.frase, 'Achei 5 hinos, do 1 ao 5.');
    });

    test('um hino só não é "1 hinos"', () {
      final r = ImportarHinario.analisar(_hino(15), harpaCrista);
      expect(r.frase, 'Achei 1 hino: o 15.');
    });

    test('falta um', () {
      final texto = [_hino(1), _hino(3)].join('\n');
      final r = ImportarHinario.analisar(texto, harpaCrista);
      expect(r.frase, 'Achei 2 hinos, do 1 ao 3. Falta o 2.');
    });

    test('faltam dois', () {
      final texto = [_hino(1), _hino(4)].join('\n');
      final r = ImportarHinario.analisar(texto, harpaCrista);
      expect(r.frase, 'Achei 2 hinos, do 1 ao 4. Faltam o 2 e o 3.');
    });

    test('lista comprida de faltantes é cortada', () {
      expect(
        ResultadoDaLeitura.listaDeNumeros([1, 2, 3, 4, 5, 6, 7, 8, 9]),
        'o 1, o 2, o 3, o 4, o 5, o 6 e mais 3',
      );
      expect(ResultadoDaLeitura.listaDeNumeros([4, 17, 203]),
          'o 4, o 17 e o 203');
      expect(ResultadoDaLeitura.listaDeNumeros([4]), 'o 4');
      expect(ResultadoDaLeitura.listaDeNumeros(const []), '');
    });

    test('nada achado', () {
      final r = ImportarHinario.analisar('só uma conversa qualquer', harpaCrista);
      expect(r.achouAlgo, isFalse);
      expect(r.formato, isNull);
      expect(r.frase, 'Não achei nenhum hino neste texto.');
    });

    test('texto vazio não lança', () {
      expect(ImportarHinario.analisar('', harpaCrista).achouAlgo, isFalse);
      expect(ImportarHinario.analisar('   \n\n  ', harpaCrista).achouAlgo,
          isFalse);
    });
  });

  group('o hinário inteiro', () {
    test('640 hinos de uma vez, em tempo de sobra', () {
      final texto = _hinario(1, 640);
      final relogio = Stopwatch()..start();
      final r = ImportarHinario.analisar(texto, harpaCrista);
      relogio.stop();
      expect(r.hinos.length, 640);
      expect(r.faltando, isEmpty);
      expect(r.frase, 'Achei 640 hinos, do 1 ao 640.');
      // Num celular velho a conta não pode travar a tela por segundos.
      expect(relogio.elapsedMilliseconds, lessThan(3000));
    });
  });
}
