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

  // ── A FORMA de um hinário de verdade ───────────────────────────────────────
  //
  // Colado o texto real da Harpa (640 hinos), a prévia saiu errada: "Achei 347
  // hinos, faltam o 8 ao 13 e mais 287". Os testes acima usavam o formato que
  // EU previ ("15 - Título"); o texto de verdade era outro, e só um texto com a
  // mesma forma mostra isso. Aqui o texto é todo inventado — só a FORMA é a
  // real: cabeçalho "N. TÍTULO EM MAIÚSCULAS", estrofes numeradas SEM ponto
  // ("1 palavras…"), coro em maiúsculas sem número e as iniciais do autor
  // coladas no fim. E os defeitos da fonte: do hino 200 em diante as estrofes
  // vêm numeradas COM ponto ("1. palavras…"), alguns cabeçalhos não têm ponto,
  // um tem aspas, um tem letra minúscula por erro de digitação, e um tem o
  // número errado.
  group('a forma de um hinário de verdade', () {
    /// Um hino de mentira com a forma do texto real. [extra] acrescenta
    /// estrofes, para a letra ficar mais comprida.
    String real(
      int n, {
      String? numeroEscrito,
      String titulo = '',
      String? cabecalho,
      bool estrofesComPonto = false,
      int extra = 0,
    }) {
      final t = titulo.isEmpty ? 'TÍTULO $n' : titulo;
      final c = cabecalho ?? '${numeroEscrito ?? n}. $t';
      final m = estrofesComPonto ? '.' : '';
      final sb = StringBuffer('$c\n')
        ..writeln('1$m palavras inventadas da estrofe um do hino $n de teste')
        ..writeln('com mais uma linha inventada')
        ..writeln()
        ..writeln('CORO INVENTADO EM MAIÚSCULAS DO HINO $n')
        ..writeln('SEGUNDA LINHA DO CORO')
        ..writeln()
        ..writeln('2$m palavras inventadas da estrofe dois do hino $n de teste');
      for (var e = 0; e < extra; e++) {
        sb
          ..writeln()
          ..writeln('${3 + e}$m outra estrofe inventada qualquer do hino $n');
      }
      sb.writeln('com mais uma linha inventada    X.Y.Z.');
      return sb.toString();
    }

    /// A letra do hino [n] fala só do hino [n]: não engoliu o seguinte nem
    /// perdeu o começo para o anterior.
    void soDele(ResultadoDaLeitura r, int n) {
      final h = r.hinos.firstWhere((h) => h.numero == n,
          orElse: () => throw TestFailure('o hino $n não foi achado'));
      expect(h.letra, contains('estrofe um do hino $n de teste'));
      expect(h.letra, contains('estrofe dois do hino $n de teste'));
      for (final outro in r.hinos) {
        if (outro.numero == n) continue;
        expect(h.letra, isNot(contains('do hino ${outro.numero} de teste')),
            reason: 'a letra do $n levou texto do ${outro.numero}');
      }
    }

    test('cabeçalho "N. TÍTULO" com estrofes sem ponto: acha todos', () {
      final texto = [for (var n = 1; n <= 30; n++) real(n)].join('\n');
      final r = ImportarHinario.analisar(texto, harpaCrista);
      expect(r.formato, FormatoDoHinario.caixaAlta);
      expect(r.hinos.length, 30);
      expect(r.faltando, isEmpty);
      expect(r.curtos, isEmpty);
      expect(r.hinos[6].titulo, 'Título 7');
      for (final h in r.hinos) {
        soDele(r, h.numero);
      }
    });

    test('estrofe numerada com ponto (1. palavras) NÃO vira hino', () {
      // É o que deixava o cabeçalho com a letra vazia: a primeira estrofe "1."
      // era lida como começo do hino 1 e cortava o hino de verdade ao meio.
      final texto = [
        for (var n = 198; n <= 203; n++) real(n, estrofesComPonto: n >= 200),
      ].join('\n');
      final r = ImportarHinario.analisar(texto, harpaCrista);
      expect(r.hinos.map((h) => h.numero), [198, 199, 200, 201, 202, 203]);
      expect(r.curtos, isEmpty);
      for (final h in r.hinos) {
        soDele(r, h.numero);
      }
      expect(r.hinos.last.letra, startsWith('1. palavras'));
    });

    test('cabeçalho sem o ponto no meio dos que têm', () {
      final texto = [
        real(5),
        real(6),
        real(7, cabecalho: '7 TÍTULO 7'),
        real(8),
        real(9),
      ].join('\n');
      final r = ImportarHinario.analisar(texto, harpaCrista);
      expect(r.hinos.map((h) => h.numero), [5, 6, 7, 8, 9]);
      for (final h in r.hinos) {
        soDele(r, h.numero);
      }
    });

    test('título que começa com aspas não some e não é engolido', () {
      // Se o cabeçalho não for reconhecido, o hino anterior ENGOLE o texto
      // dele inteiro — e a prévia mostra um hino só, comprido, sem erro.
      final texto = [
        real(300),
        real(301, cabecalho: '301. "TÍTULO ENTRE ASPAS"  '),
        real(302, cabecalho: '302. “TÍTULO COM ASPAS CURVAS”'),
        real(303),
      ].join('\n');
      final r = ImportarHinario.analisar(texto, harpaCrista);
      expect(r.hinos.map((h) => h.numero), [300, 301, 302, 303]);
      for (final h in r.hinos) {
        soDele(r, h.numero);
      }
    });

    test('tabulação e espaço em volta do número não atrapalham', () {
      final texto = [
        real(27, cabecalho: '\t27.  TÍTULO 27'),
        real(51, cabecalho: '51.\tTÍTULO 51'),
        real(303, cabecalho: '   303.   TÍTULO 303'),
      ].join('\n');
      final r = ImportarHinario.analisar(texto, harpaCrista);
      expect(r.hinos.map((h) => h.numero), [27, 51, 303]);
      for (final h in r.hinos) {
        soDele(r, h.numero);
      }
    });

    test('uma letra minúscula por erro de digitação no título não esconde o hino',
        () {
      // "CRElO", com L minúsculo no lugar do I: o hino 48 engoliria o 49.
      final texto = [
        real(48),
        real(49, cabecalho: '49. ALELUIA! JA CRElO'),
        real(50),
      ].join('\n');
      final r = ImportarHinario.analisar(texto, harpaCrista);
      expect(r.hinos.map((h) => h.numero), [48, 49, 50]);
      for (final h in r.hinos) {
        soDele(r, h.numero);
      }
      // E o título não grita no meio da lista.
      expect(r.hinos[1].titulo, 'Aleluia! Ja Crelo');
    });

    test('texto antes do primeiro hino (cabeçalho do site) é ignorado', () {
      final texto = 'LIVRO INVENTADO\n*****************\n'
          'hinos do livro do 001 a 640\nVisite: http://exemplo.invalido/\n\n'
          '${[for (var n = 1; n <= 3; n++) real(n)].join('\n')}';
      final r = ImportarHinario.analisar(texto, harpaCrista);
      expect(r.hinos.map((h) => h.numero), [1, 2, 3]);
      expect(r.hinos.first.letra, isNot(contains('LIVRO INVENTADO')));
    });

    test('as iniciais do autor, coladas no fim, ficam na letra', () {
      // De propósito: é a autoria, e tirá-la às cegas apagaria informação que
      // o líder pode querer. Fica visível na prévia.
      final r = ImportarHinario.analisar(real(1), harpaCrista);
      expect(r.hinos.single.letra, endsWith('X.Y.Z.'));
    });

    test('um candidato gigante não derruba o hino de verdade', () {
      // Havia um "5." mais adiante cujo texto ia até o fim: com a regra "fica a
      // mais comprida" ele ganhava, passava de 6000 e o hino 5 SUMIA da
      // importação (virava "grande demais"). Letra que serve ganha de letra
      // que não serve.
      final gigante = List.filled(400, 'uma linha inventada de teste que enche')
          .join('\n');
      final texto = '${[real(4), real(5), real(6)].join('\n')}\n'
          '5. LISTA GIGANTE INVENTADA\n$gigante\n';
      final r = ImportarHinario.analisar(texto, harpaCrista);
      expect(r.hinos.map((h) => h.numero), [4, 5, 6]);
      expect(r.grandes, isEmpty);
      soDele(r, 5);
    });

    test('o número escrito errado NÃO apaga o hino de verdade', () {
      // O 542 está digitado "442". Como tem mais estrofes, a regra "fica a mais
      // comprida" o poria no lugar do 442 de verdade, TROCANDO a letra sem
      // nenhum erro. Quem está na ordem certa ganha.
      final texto = [
        real(440),
        real(441),
        real(442),
        real(443),
        real(540),
        real(541),
        real(542, numeroEscrito: '442', titulo: 'HISTÓRIA INVENTADA', extra: 3),
        real(543),
        real(544),
      ].join('\n');
      final r = ImportarHinario.analisar(texto, harpaCrista);
      final h442 = r.hinos.firstWhere((h) => h.numero == 442);
      expect(h442.letra, contains('do hino 442 de teste'));
      expect(h442.letra, isNot(contains('do hino 542')));
      expect(h442.titulo, 'Título 442');
      expect(r.repetidos, [442]);
      // O 542 não entra, e a tela diz que falta...
      expect(r.hinos.any((h) => h.numero == 542), isFalse);
      expect(r.faltando, contains(542));
      // ...e diz ONDE está o erro, para a pessoa consertar a linha: o app não
      // troca o número sozinho.
      final s = r.suspeitos.single;
      expect(s.escrito, 442);
      expect(s.provavel, 542);
      expect(s.titulo, 'História Inventada');
    });

    test('o suspeito só aparece quando o número de verdade não foi achado', () {
      // O 542 existe de verdade em outro lugar: o "442" é só uma cópia
      // repetida, não um erro de digitação a consertar.
      final texto = [
        real(440),
        real(441),
        real(442),
        real(443),
        real(541),
        real(542),
        real(542, numeroEscrito: '442', titulo: 'OUTRA CÓPIA', extra: 3),
        real(543),
      ].join('\n');
      final r = ImportarHinario.analisar(texto, harpaCrista);
      expect(r.suspeitos, isEmpty);
    });

    test('duas cópias do mesmo trecho: entra uma de cada, sem acusar erro', () {
      // A fonte repete o 200 e o 201. Ficam os dois, e a tela avisa que
      // apareceram duas vezes.
      final texto =
          [real(199), real(200), real(201), real(200), real(201), real(202)]
              .join('\n');
      final r = ImportarHinario.analisar(texto, harpaCrista);
      expect(r.hinos.map((h) => h.numero), [199, 200, 201, 202]);
      expect(r.repetidos, [200, 201]);
      expect(r.faltando, isEmpty);
      // Cópia não é erro de digitação: nada a consertar.
      expect(r.suspeitos, isEmpty);
    });

    test('ponto colado no título ("584.TÍTULO") também é cabeçalho', () {
      // Na fonte de verdade, "584.O PILOTO". O leitor exigia espaço depois do
      // ponto, e o hino 584 INTEIRO entrou na letra do 583, sem nenhum erro.
      final texto = [
        real(583),
        real(584, cabecalho: '584.TÍTULO COLADO'),
        real(585),
      ].join('\n');
      final r = ImportarHinario.analisar(texto, harpaCrista);
      expect(r.hinos.map((h) => h.numero), [583, 584, 585]);
      expect(r.faltando, isEmpty);
      expect(r.perdidos, isEmpty);
      for (final h in r.hinos) {
        soDele(r, h.numero);
      }
      expect(r.hinos[1].titulo, 'Título Colado');
    });

    test('cabeçalho que não foi reconhecido é APONTADO, com a linha e o hino '
        'que o engoliu', () {
      // Título em minúsculas no meio de um livro em maiúsculas: não é
      // reconhecido, o 583 leva o texto do 584, e a frase sozinha só diria
      // "Falta o 584". Tem de dizer ONDE.
      // Estrofes COM ponto, como na fonte: é o que faz o formato de maiúsculas
      // vencer. (Com estrofes sem ponto, o formato "N. Título" leria o 584
      // direitinho, e não haveria defeito nenhum a apontar.)
      final texto = [
        real(582, estrofesComPonto: true),
        real(583, estrofesComPonto: true),
        real(584,
            cabecalho: '584. Título em minúsculas', estrofesComPonto: true),
        real(585, estrofesComPonto: true),
      ].join('\n');
      final r = ImportarHinario.analisar(texto, harpaCrista);
      expect(r.faltando, [584]);
      final p = r.perdidos.single;
      expect(p.numero, 584);
      expect(p.dentroDe, 583);
      expect(p.linha, '584. Título em minúsculas');
    });

    test('estrofe numerada de um hino que falta NÃO é acusada de ser ele', () {
      // O hino 4 falta, e o 3 tem estrofes "4. palavras…". Número pequeno é
      // estrofe, não cabeçalho: sem este limite todo hino faltando acusaria a
      // própria estrofe e o aviso perderia o crédito.
      // (Com volume de verdade: num texto de dois hinos, ler as estrofes como
      // hinos renderia mais que ler os cabeçalhos, e o leitor escolheria isso.)
      final texto = [
        for (var n = 1; n <= 12; n++)
          if (n != 4) real(n, estrofesComPonto: n == 3, extra: n == 3 ? 2 : 0),
      ].join('\n');
      expect(texto, contains('\n4. outra estrofe inventada'),
          reason: 'o teste precisa ter a estrofe "4." para provar o limite');
      final r = ImportarHinario.analisar(texto, harpaCrista);
      expect(r.formato, FormatoDoHinario.caixaAlta);
      expect(r.faltando, [4]);
      expect(r.perdidos, isEmpty);
    });

    test('sumário bem na ordem continua perdendo para a letra de verdade', () {
      // O sumário está "na ordem" e a letra de verdade vem depois, "fora da
      // ordem": ordem NÃO pode vencer letra que existe.
      final texto = '1. TÍTULO 1\n2. TÍTULO 2\n3. TÍTULO 3\n\n'
          '${[for (var n = 1; n <= 3; n++) real(n)].join('\n')}';
      final r = ImportarHinario.analisar(texto, harpaCrista);
      expect(r.hinos.length, 3);
      for (final h in r.hinos) {
        soDele(r, h.numero);
      }
    });
  });

  // O texto do Cantor Cristão colado de um site: o nome do site no começo, o
  // mesmo nome e uma lista de endereços no FIM. Sem o corte, tudo isso entrava
  // na letra do último hino — e a prévia, que mostra só o começo de cada
  // amostra, não deixava ver.
  group('rodapé de site no fim do texto', () {
    const nome = 'Site de Mentira - Publicações';
    const rodape = '$nome\n'
        'http://exemplo-um.example/\n'
        'http://exemplo-dois.example/\n'
        'BAIXE AQUI>>>\n'
        'Adicione os sites ao seu favorito [Gmail\n'
        'deve estar aberto]';

    test('o rodapé NÃO entra na letra do último hino', () {
      final texto = '$nome\n[www.exemplo.example/](https://www.exemplo.example/)\n'
          '${_hinario(1, 3)}\n$rodape';
      final r = ImportarHinario.analisar(texto, cantorCristao);

      expect(r.hinos.map((h) => h.numero), [1, 2, 3]);
      final ultima = r.hinos.last.letra;
      expect(ultima, endsWith('deste hino de teste'));
      expect(ultima, isNot(contains('exemplo')));
      expect(ultima, isNot(contains(nome)));
      expect(ultima, isNot(contains('BAIXE')));
    });

    test('o corte é DECLARADO: quantas linhas, a partir de qual, de que hino',
        () {
      final texto = '$nome\n${_hinario(1, 3)}\n$rodape';
      final r = ImportarHinario.analisar(texto, cantorCristao);

      expect(r.rodape, isNotNull);
      expect(r.rodape!.hino, 3);
      expect(r.rodape!.linhas, 6);
      expect(r.rodape!.primeira, nome);
    });

    test('sem o nome do site no começo, o corte começa no primeiro endereço',
        () {
      final texto = '${_hinario(1, 3)}\n$rodape';
      final r = ImportarHinario.analisar(texto, cantorCristao);

      // O nome do site não se repete do começo: não há como saber que aquela
      // linha é rodapé, então só o que é endereço sai — e a linha que sobra
      // aparece na prévia, no fim da letra, em vez de ficar escondida.
      expect(r.rodape!.primeira, 'http://exemplo-um.example/');
      expect(r.rodape!.linhas, 5);
      expect(r.hinos.last.letra, isNot(contains('exemplo')));
      expect(r.hinos.last.letra, isNot(contains('Adicione')));
    });

    test('texto sem rodapé: nada é cortado e nada é declarado', () {
      final r = ImportarHinario.analisar(_hinario(1, 3), cantorCristao);
      expect(r.rodape, isNull);
      expect(r.hinos.last.letra, endsWith('deste hino de teste'));
    });

    test('endereço no MEIO do texto não corta nada: só o fim é rodapé', () {
      final texto = [
        _hino(1),
        '${_hino(2)}http://exemplo-no-meio.example/\n',
        _hino(3),
      ].join('\n');
      final r = ImportarHinario.analisar(texto, cantorCristao);

      expect(r.rodape, isNull);
      expect(r.hinos[1].letra, contains('exemplo-no-meio'));
      expect(r.hinos.last.letra, endsWith('deste hino de teste'));
    });

    test('o corte não derruba o último hino nem muda os outros', () {
      final sem = ImportarHinario.analisar(_hinario(1, 3), cantorCristao);
      final com = ImportarHinario.analisar(
          '$nome\n${_hinario(1, 3)}\n$rodape', cantorCristao);

      expect(com.hinos.length, sem.hinos.length);
      for (var i = 0; i < sem.hinos.length; i++) {
        expect(com.hinos[i].letra, sem.hinos[i].letra);
        expect(com.hinos[i].titulo, sem.hinos[i].titulo);
      }
      expect(com.frase, sem.frase);
    });

    test('hinos 1 a 581, com rodapé: o último fica limpo', () {
      final texto = '$nome\n${_hinario(1, 581)}\n$rodape';
      final r = ImportarHinario.analisar(texto, cantorCristao);

      expect(r.frase, 'Achei 581 hinos, do 1 ao 581.');
      expect(r.hinos.last.letra, isNot(contains('http')));
    });
  });

  // 520 dos 581 hinos do Cantor vêm com a letra TODA EM MAIÚSCULAS. Na tela do
  // culto isso grita, e é difícil de ler de longe.
  group('letra toda em maiúsculas', () {
    /// Um hino de mentira com a letra escrita em maiúsculas, marcadores de
    /// estrofe como a fonte os traz.
    String gritado(int n, String letra) => '$n - Título $n\n$letra\n';

    String converter(String letra) {
      final r = ImportarHinario.analisar(
        gritado(1, letra),
        cantorCristao,
        converterCaixaAlta: true,
      );
      return r.hinos.single.letra;
    }

    test('vira letra normal: inicial só onde a frase começa', () {
      expect(
        converter('[1]\n'
            'A MINHA ALMA CANTA AO SOM,\n'
            'POIS HOJE TEM FESTA NA CASA.\n'
            'TODOS VÃO CANTAR!'),
        '[1]\n'
        'A minha alma canta ao som,\n'
        'pois hoje tem festa na casa.\n'
        'Todos vão cantar!',
      );
    });

    test('os marcadores [1] e [côro] ficam exatamente como estão', () {
      final saida = converter('[1]\nPALAVRAS INVENTADAS DO COMEÇO\n[côro]\n'
          'PALAVRAS INVENTADAS DO REFRÃO\n[2]\nMAIS PALAVRAS INVENTADAS');
      expect(saida, contains('[1]'));
      expect(saida, contains('[côro]'));
      expect(saida, contains('[2]'));
    });

    test('cada estrofe começa com maiúscula, mesmo depois de uma vírgula', () {
      final saida = converter('[1]\nPRIMEIRA PARTE DA ESTROFE,\n'
          'SEGUNDA PARTE\n[2]\nOUTRA ESTROFE INVENTADA');
      expect(saida, contains('[2]\nOutra estrofe inventada'));
      // Vírgula não abre frase: a linha de baixo continua minúscula.
      expect(saida, contains('Primeira parte da estrofe,\nsegunda parte'));
    });

    test('Deus, Jesus, Cristo e Senhor ficam com inicial maiúscula', () {
      final saida = converter('[1]\n'
          'LOUVAI A DEUS E A JESUS CRISTO,\n'
          'POIS O SENHOR É BOM E O SALVADOR NOS GUARDA');
      expect(saida, contains('a Deus e a Jesus Cristo,'));
      expect(saida, contains('pois o Senhor é bom e o Salvador nos guarda'));
    });

    test('nomes de lugar e de gente também', () {
      final saida = converter('[1]\n'
          'A VOZ SAIU DE SIÃO E DE JERUSALÉM,\n'
          'DO BRASIL ATÉ O JORDÃO');
      expect(saida, contains('de Sião e de Jerusalém,'));
      expect(saida, contains('do Brasil até o Jordão'));
    });

    test('Espírito Santo e Todo-Poderoso, só quando são esses nomes', () {
      final saida = converter('[1]\n'
          'VEM, ESPÍRITO SANTO, VEM,\n'
          'DEUS TODO-PODEROSO, VEM\n[2]\n'
          'MEU ESPÍRITO CANTA');
      expect(saida, contains('Vem, Espírito Santo, vem,'));
      expect(saida, contains('Deus Todo-Poderoso, vem'));
      // "espírito" sozinho é a alma de quem canta, não o Espírito Santo.
      expect(saida, contains('Meu espírito canta'));
    });

    test('Filho só é maiúsculo quando é o Filho de Deus', () {
      final saida = converter('[1]\n'
          'A TI, DEUS FILHO, LOUVOR,\n'
          'O FILHO MAU VOLTOU PRA CASA,\n'
          'COM O FILHO DE DEUS SEMPRE,\n'
          'DIZ O FILHO DO SANTO DEUS,\n'
          'O SEU QUERIDO FILHO ME DEU,\n'
          'VEM, FILHO, VEM!');
      expect(saida, contains('A ti, Deus Filho, louvor,'));
      expect(saida, contains('o filho mau voltou pra casa,'));
      expect(saida, contains('com o Filho de Deus sempre,'));
      expect(saida, contains('diz o Filho do santo Deus,'));
      expect(saida, contains('o seu querido Filho me deu,'));
      // O pródigo e o pecador chamado de "filho" não são o Filho.
      expect(saida, contains('vem, filho, vem!'));
    });

    test('"espírito" sozinho é o Espírito Santo — menos em "meu espírito"', () {
      final saida = converter('[1]\n'
          'O DOM DO ESPÍRITO NOS DEU\n'
          'TEU ESPÍRITO DOMINE O CORAÇÃO\n'
          'SEU BOM E SANTO ESPÍRITO\n'
          'MEU ESPÍRITO SE ALEGRA');
      expect(saida, contains('O dom do Espírito nos deu'));
      expect(saida, contains('teu Espírito domine o coração'));
      expect(saida, contains('seu bom e Santo Espírito'));
      // A alma de quem canta não é o Espírito Santo.
      expect(saida, contains('meu espírito se alegra'));
    });

    test('"santo" sozinho é adjetivo e fica minúsculo', () {
      final saida = converter('[1]\nQUE SANTO AMOR, QUE SANTO LAR\n'
          'DEUS DE ISRAEL, O SANTO DE ISRAEL');
      expect(saida, contains('Que santo amor, que santo lar'));
      expect(saida, contains('o Santo de Israel'));
    });

    test('ponto de exclamação e de interrogação abrem frase; reticências não',
        () {
      final saida = converter('[1]\n'
          'ALELUIA! ALELUIA! QUEM SOU EU? SOU FILHO.\n'
          'NOVAS TENHO... DAR-VOS VENHO');
      expect(saida, contains('Aleluia! Aleluia! Quem sou eu? Sou filho.'));
      // O ponto da linha de cima fecha a frase: "Novas" é início de frase.
      expect(saida, contains('Novas tenho... dar-vos venho'));
    });

    test('acento e cedilha: AÇÃO vira ação, e "Ó" no começo continua "Ó"', () {
      final saida = converter('[1]\nÓ AÇÃO DE GRAÇAS, É CERTO');
      expect(saida, '[1]\nÓ ação de graças, é certo');
    });

    test('depois de dois-pontos com aspas, a fala começa com maiúscula', () {
      final saida = converter('[1]\nDISSE O MESTRE: "VEM A MIM"');
      expect(saida, '[1]\nDisse o Mestre: "Vem a mim"');
    });

    test('aspas que fecham com o sinal errado (!“ .“) também fecham a frase',
        () {
      // Na fonte de verdade o fecha-aspas vem como “ (de abrir). Sem tratar,
      // a frase seguinte ficava em minúscula, e a de cima de uma fala também.
      final saida = converter('[1]\n'
          'O MESTRE DIZ:\n'
          '"VEM! VEM, BEBE DESSA ÁGUA!“\n'
          'RESPONDA, POIS, QUEM TEM SEDE:\n'
          '"À FONTE DE CRISTO JÁ VOU.“\n'
          'SIM, A ÁGUA CORRE');
      expect(
        saida,
        '[1]\n'
        'O Mestre diz:\n'
        '"Vem! Vem, bebe dessa água!“\n'
        'Responda, pois, quem tem sede:\n'
        '"À fonte de Cristo já vou.“\n'
        'Sim, a água corre',
      );
    });

    test('hífen no meio da palavra não abre frase', () {
      final saida = converter('[1]\nVEM, BEM-AMADO, DAR-TE-EI LOUVOR');
      expect(saida, '[1]\nVem, bem-amado, dar-te-ei louvor');
    });

    test('hino que já vem em maiúsculas e minúsculas fica EXATAMENTE como veio',
        () {
      // Um "AMÉM!" gritado no fim de um hino normal não é o hino gritando.
      const original = '[1]\nSanto, santo, santo, Deus onipotente!\n'
          'Cedo de manhã cantaremos teu louvor.\nAMÉM! AMÉM!';
      expect(converter(original), original);
    });

    test('linha já em minúsculas, no meio de um hino gritado, não é mexida', () {
      // Cinco linhas gritadas e uma mista: o hino é gritado (passa de 80%), e
      // a linha mista fica como veio.
      final saida = converter('[1]\nPRIMEIRA LINHA INVENTADA DO HINO\n'
          'SEGUNDA LINHA INVENTADA DO HINO\n'
          'Linha Mista Que Já Veio Assim\n'
          'QUARTA LINHA INVENTADA DO HINO\n'
          'QUINTA LINHA INVENTADA DO HINO\n'
          'SEXTA LINHA INVENTADA DO HINO');
      expect(saida, contains('Linha Mista Que Já Veio Assim'));
      expect(saida, contains('Primeira linha inventada do hino'));
      // Sem ponto final na linha de cima, a de baixo não abre frase.
      expect(saida, contains('\nsexta linha inventada do hino'));
    });

    test('converter duas vezes dá o mesmo que converter uma', () {
      const original = '[1]\nLOUVAI A DEUS, TODOS OS POVOS!\n'
          'ELE É O SENHOR DE TUDO.\n[côro]\nALELUIA!';
      final uma = converter(original);
      expect(converter(uma), uma);
    });

    test('o título não é tocado pela conversão da letra', () {
      final r = ImportarHinario.analisar(
        '1 - Cristo, o Bom Pastor\n[1]\nPALAVRAS INVENTADAS DO HINO TODO\n',
        cantorCristao,
        converterCaixaAlta: true,
      );
      expect(r.hinos.single.titulo, 'Cristo, o Bom Pastor');
    });

    test('sem pedir, a letra NÃO é mexida — mas o app conta quantos gritam',
        () {
      final texto = [
        gritado(1, '[1]\nPALAVRAS INVENTADAS DO HINO UM'),
        gritado(2, '[1]\nPALAVRAS INVENTADAS DO HINO DOIS'),
        gritado(3, '[1]\nPalavras inventadas do hino três'),
      ].join('\n');
      final r = ImportarHinario.analisar(texto, cantorCristao);

      expect(r.emCaixaAlta, 2);
      expect(r.convertida, isFalse);
      expect(r.hinos[0].letra, contains('PALAVRAS INVENTADAS DO HINO UM'));
      expect(r.hinos[2].letra, contains('Palavras inventadas do hino três'));
    });

    test('pedindo: converte só os que gritam, e diz que converteu', () {
      final texto = [
        gritado(1, '[1]\nPALAVRAS INVENTADAS DO HINO UM'),
        gritado(2, '[1]\nPalavras inventadas do hino dois'),
      ].join('\n');
      final r = ImportarHinario.analisar(texto, cantorCristao,
          converterCaixaAlta: true);

      expect(r.emCaixaAlta, 1);
      expect(r.convertida, isTrue);
      expect(r.hinos[0].letra, '[1]\nPalavras inventadas do hino um');
      expect(r.hinos[1].letra, '[1]\nPalavras inventadas do hino dois');
    });

    test('nenhum hino gritando: pedir a conversão não muda nada nem avisa', () {
      final r = ImportarHinario.analisar(_hinario(1, 3), cantorCristao,
          converterCaixaAlta: true);
      expect(r.emCaixaAlta, 0);
      expect(r.convertida, isFalse);
    });

    test('a quantidade de hinos e o resto da leitura não dependem da conversão',
        () {
      final texto = [
        for (var n = 1; n <= 20; n++)
          gritado(n, '[1]\nPALAVRAS INVENTADAS DO HINO $n DE TESTE'),
      ].join('\n');
      final a = ImportarHinario.analisar(texto, cantorCristao);
      final b = ImportarHinario.analisar(texto, cantorCristao,
          converterCaixaAlta: true);
      expect(b.hinos.map((h) => h.numero), a.hinos.map((h) => h.numero));
      expect(b.frase, a.frase);
    });
  });
}
