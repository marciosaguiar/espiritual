// A biblioteca de hinários: o texto importado, fora de `songs`.
//
// O texto de teste é INVENTADO. Nada de letra de hino de verdade no repo.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:levitasync/core/constants/hinarios.dart';
import 'package:levitasync/core/utils/importar_hinario.dart';
import 'package:levitasync/data/models/hino_da_biblioteca.dart';
import 'package:levitasync/data/services/firestore_service.dart';

HinoLido _lido(int n, {String titulo = ''}) => HinoLido(
    numero: n,
    titulo: titulo.isEmpty ? 'Título $n' : titulo,
    letra: 'Letra inventada $n');

void main() {
  group('o hino lido do banco', () {
    test('documento certo vira hino', () {
      final h = HinoDaBiblioteca.fromFirestore('harpa', {
        'numero': 15,
        'titulo': 'Título 15',
        'letra': 'Letra inventada',
      });
      expect(h, isNotNull);
      expect(h!.hinario, 'harpa');
      expect(h.numero, 15);
      expect(h.titulo, 'Título 15');
    });

    test('documento que não existe é nulo, não lança', () {
      expect(HinoDaBiblioteca.fromFirestore('harpa', null), isNull);
    });

    test('sem letra é "não está na biblioteca", não uma página em branco', () {
      // Hino com título e sem letra, na tela, parece que o hino não tem letra.
      final h = HinoDaBiblioteca.fromFirestore('harpa',
          {'numero': 15, 'titulo': 'Título 15', 'letra': '   '});
      expect(h, isNull);
    });

    test('campo de tipo errado, mexido no console, não derruba', () {
      expect(
          HinoDaBiblioteca.fromFirestore(
              'harpa', {'numero': '15', 'titulo': 'T', 'letra': 'L'}),
          isNull);
      expect(
          HinoDaBiblioteca.fromFirestore(
              'harpa', {'numero': 15, 'titulo': 7, 'letra': 'L'}),
          isNull);
      expect(HinoDaBiblioteca.fromFirestore('harpa', const {}), isNull);
    });

    test('número gravado como decimal ainda é lido como inteiro', () {
      final h = HinoDaBiblioteca.fromFirestore(
          'harpa', {'numero': 15.0, 'titulo': 'T', 'letra': 'L'});
      expect(h!.numero, 15);
    });
  });

  group('virar música do repertório', () {
    const hino = HinoDaBiblioteca(
        hinario: 'harpa', numero: 15, titulo: 'Título 15', letra: 'Letra\n\nda música');
    final quando = DateTime(2026, 11, 19);

    test('leva a sigla no título, que é o que o reconhece na escala', () {
      final m = hino.comoMusica(harpaCrista,
          id: 'abc', addedBy: 'uid-lider', criadaEm: quando);
      expect(m.name, 'HC 15 · Título 15');
    });

    test('leva os DOIS campos, que é por onde o teclado a acha', () {
      final m = hino.comoMusica(harpaCrista,
          id: 'abc', addedBy: 'uid-lider', criadaEm: quando);
      expect(m.hinario, 'harpa');
      expect(m.numero, 15);
      expect(m.ehHino, isTrue);
    });

    test('o hinário entra como artista, como no cadastro à mão', () {
      final m = hino.comoMusica(harpaCrista,
          id: 'abc', addedBy: 'uid-lider', criadaEm: quando);
      expect(m.artist, 'Harpa Cristã');
    });

    test('a letra vai inteira, com as estrofes separadas', () {
      final m = hino.comoMusica(harpaCrista,
          id: 'abc', addedBy: 'uid-lider', criadaEm: quando);
      expect(m.lyrics, 'Letra\n\nda música');
    });

    test('quem pôs no repertório e quando ficam registrados', () {
      final m = hino.comoMusica(harpaCrista,
          id: 'abc', addedBy: 'uid-lider', criadaEm: quando);
      expect(m.id, 'abc');
      expect(m.addedBy, 'uid-lider');
      expect(m.createdAt, quando);
      expect(m.archived, isFalse);
    });

    test('o documento que vai para o banco passa na validação de hino', () {
      // As regras exigem `hinario` e `numero` JUNTOS e dentro da lista.
      final m = hino.comoMusica(cantorCristao,
          id: 'abc', addedBy: null, criadaEm: quando);
      final doc = m.toFirestore();
      expect(doc['hinario'], 'cantor');
      expect(doc['numero'], 15);
      expect(doc['name'], 'CC 15 · Título 15');
    });
  });

  group('o índice de títulos', () {
    test('lê o mapa do banco: chaves em texto viram número', () {
      final i = IndiceDoHinario.fromFirestore('harpa', {
        'titulos': {'15': 'Título 15', '3': 'Título 3'},
        'total': 2,
      });
      expect(i.total, 2);
      expect(i.tituloDe(15), 'Título 15');
      expect(i.numeros, [3, 15], reason: 'em ordem, não na do banco');
    });

    test('documento que não existe é índice vazio, não erro', () {
      final i = IndiceDoHinario.fromFirestore('harpa', null);
      expect(i.vazio, isTrue);
      expect(i.tem(15), isFalse);
    });

    test('lixo no console some em vez de derrubar a tela', () {
      final i = IndiceDoHinario.fromFirestore('harpa', {
        'titulos': {
          '15': 'Título 15',
          'abc': 'chave que não é número',
          '16': 42,
          '17': '   ',
          '0': 'zero não é hino',
          '-3': 'nem negativo',
        },
      });
      expect(i.numeros, [15]);
    });

    test('titulos que não é mapa vira índice vazio', () {
      expect(
          IndiceDoHinario.fromFirestore('harpa', {'titulos': 'texto'}).vazio,
          isTrue);
      expect(IndiceDoHinario.fromFirestore('harpa', {'titulos': [1, 2]}).vazio,
          isTrue);
    });

    test('hino novo entra e o título velho é trocado (re-importar corrige)', () {
      const antes = IndiceDoHinario(
          hinario: 'harpa', titulos: {1: 'Errado', 2: 'Dois'});
      final depois = antes.comHinos([_lido(1, titulo: 'Certo'), _lido(3)]);
      expect(depois.tituloDe(1), 'Certo');
      expect(depois.tituloDe(2), 'Dois');
      expect(depois.tituloDe(3), 'Título 3');
    });

    test('colar o hinário em partes: a segunda não apaga a primeira', () {
      var i = const IndiceDoHinario.vazio('harpa');
      i = i.comHinos([for (var n = 1; n <= 50; n++) _lido(n)]);
      i = i.comHinos([for (var n = 51; n <= 100; n++) _lido(n)]);
      expect(i.total, 100);
      expect(i.tem(1) && i.tem(50) && i.tem(51) && i.tem(100), isTrue);
    });

    test('não mexe no índice que recebeu', () {
      const antes = IndiceDoHinario(hinario: 'harpa', titulos: {1: 'Um'});
      antes.comHinos([_lido(2)]);
      expect(antes.total, 1);
    });

    test('vai para o banco com chaves em texto, que é o que mapa aceita', () {
      const i = IndiceDoHinario(
          hinario: 'harpa', titulos: {15: 'Quinze', 2: 'Dois'});
      expect(i.paraFirestore(), {'15': 'Quinze', '2': 'Dois'});
    });

    test('ida e volta: o que sai do app é o que a regra confere', () {
      // A regra exige `total == titulos.size()`.
      final i = const IndiceDoHinario.vazio('harpa')
          .comHinos([for (var n = 1; n <= 7; n++) _lido(n)]);
      final doc = {'titulos': i.paraFirestore(), 'total': i.total};
      expect((doc['titulos'] as Map).length, doc['total']);
      expect(IndiceDoHinario.fromFirestore('harpa', doc).numeros,
          [1, 2, 3, 4, 5, 6, 7]);
    });
  });

  group('procurar na biblioteca', () {
    const indice = IndiceDoHinario(hinario: 'harpa', titulos: {
      1: 'Glória a Deus',
      2: 'Grande é o Senhor',
      15: 'Sou Grato',
      150: 'Cantai ao Senhor',
    });

    test('acha pelo título, ignorando acento e maiúscula', () {
      expect(indice.buscar('gloria'), [1]);
      expect(indice.buscar('GRANDE'), [2]);
      expect(indice.buscar('senhor'), [2, 150], reason: 'em ordem de número');
    });

    test('acha pelo número', () {
      expect(indice.buscar('15'), [15, 150]);
      expect(indice.buscar('150'), [150]);
    });

    test('busca vazia não despeja a biblioteca inteira', () {
      expect(indice.buscar(''), isEmpty);
      expect(indice.buscar('   '), isEmpty);
    });

    test('nada que combine devolve lista vazia', () {
      expect(indice.buscar('xyz'), isEmpty);
    });

    test('os que já estão no repertório saem, para não aparecer em dobro', () {
      expect(indice.buscar('senhor', excluir: {2}), [150]);
    });

    test('biblioteca vazia não lança', () {
      expect(const IndiceDoHinario.vazio('harpa').buscar('qualquer'), isEmpty);
    });
  });

  group('o contrato com as regras do banco', () {
    // Os campos que o app grava e os que a regra aceita (`hasOnly`) são duas
    // listas em dois arquivos. Se divergirem, o banco recusa a importação
    // INTEIRA com erro de permissão — que não explica nada, e só acontece
    // depois de o líder colar o hinário e conferir a prévia.
    Set<String> camposDaRegra(String funcao) {
      final regras = File('firestore.rules').readAsStringSync();
      final m = RegExp('function $funcao[^}]*?hasOnly\\(\\[([^\\]]*)\\]',
              dotAll: true)
          .firstMatch(regras);
      expect(m, isNotNull, reason: '$funcao saiu do firestore.rules');
      return RegExp(r"'([^']+)'")
          .allMatches(m!.group(1)!)
          .map((x) => x.group(1)!)
          .toSet();
    }

    test('o documento do hino tem os campos que a regra aceita, nem mais '
        'nem menos', () {
      final doc = HinoDaBiblioteca.paraFirestore(_lido(15), 'uid');
      expect(doc.keys.toSet(), camposDaRegra('_hinoDaBibliotecaValido'));
    });

    test('o documento do índice tem os campos que a regra aceita, nem mais '
        'nem menos', () {
      final doc = const IndiceDoHinario.vazio('harpa')
          .comHinos([_lido(1), _lido(2)]).paraDocumento('uid');
      expect(doc.keys.toSet(), camposDaRegra('_indiceValido'));
    });

    test('o total do índice bate com a lista, que é o que a regra confere', () {
      final doc = const IndiceDoHinario.vazio('harpa')
          .comHinos([for (var n = 1; n <= 9; n++) _lido(n)]).paraDocumento('u');
      expect(doc['total'], 9);
      expect((doc['titulos'] as Map).length, doc['total']);
    });

    test('o hino leva o número, o título e a letra que foram lidos', () {
      final doc = HinoDaBiblioteca.paraFirestore(
          const HinoLido(numero: 15, titulo: 'T', letra: 'L'), 'uid-lider');
      expect(doc['numero'], 15);
      expect(doc['titulo'], 'T');
      expect(doc['letra'], 'L');
      expect(doc['importadoPor'], 'uid-lider');
    });

    test('a hora é do servidor, não do aparelho', () {
      final doc = HinoDaBiblioteca.paraFirestore(_lido(15), 'uid');
      expect(doc['importadoEm'], isA<FieldValue>());
    });
  });

  group('a divisão em lotes', () {
    test('640 hinos viram 400 + 240, sem perder nenhum', () {
      final lista = [for (var n = 1; n <= 640; n++) n];
      final p = emPedacos(lista, 400);
      expect(p.map((x) => x.length), [400, 240]);
      expect(p.expand((x) => x).toList(), lista);
    });

    test('exatamente 400 é um lote só, sem lote vazio atrás', () {
      final p = emPedacos([for (var n = 0; n < 400; n++) n], 400);
      expect(p.length, 1);
    });

    test('401 é 400 + 1', () {
      final p = emPedacos([for (var n = 0; n < 401; n++) n], 400);
      expect(p.map((x) => x.length), [400, 1]);
    });

    test('lista vazia não tem lote nenhum', () {
      expect(emPedacos(<int>[], 400), isEmpty);
    });

    test('lista menor que o lote é um lote só', () {
      expect(emPedacos([1, 2, 3], 400), [
        [1, 2, 3]
      ]);
    });

    test('a ordem é preservada', () {
      final p = emPedacos([5, 4, 3, 2, 1], 2);
      expect(p, [
        [5, 4],
        [3, 2],
        [1]
      ]);
    });

    test('o lote do app cabe nos 500 do Firestore, com o índice junto', () {
      // O teste das regras (test_regras) prova que 400 hinos + o índice passam
      // pela regra. Se alguém subir esta constante sem olhar, aqui avisa antes
      // de o líder descobrir olhando a barra de progresso.
      expect(FirestoreService.hinosPorLote + 1, lessThanOrEqualTo(500));
      expect(FirestoreService.hinosPorLote, lessThanOrEqualTo(400),
          reason: 'só 400 foi provado contra as regras');
    });
  });
}
