// A lista de TODOS os hinos de um hinário: juntar repertório e biblioteca,
// procurar por nome ou trecho, e pôr em ordem.
//
// É a parte que erra em silêncio — uma lista fora de ordem, ou uma busca que
// não acha o hino que está lá, não dá erro nenhum: a pessoa só não encontra o
// hino com a igreja esperando.
//
// TODO o texto é inventado.

import 'package:flutter_test/flutter_test.dart';
import 'package:levitasync/core/constants/hinarios.dart';
import 'package:levitasync/core/utils/lista_de_hinos.dart';
import 'package:levitasync/data/models/hino_da_biblioteca.dart';
import 'package:levitasync/data/models/song_model.dart';

SongModel _hino(int n, String nome, {String letra = '', String id = ''}) =>
    SongModel(
      id: id.isEmpty ? 'h$n' : id,
      name: 'HC $n · $nome',
      artist: 'Harpa Cristã',
      lyrics: letra,
      originalKey: 'G',
      createdAt: DateTime(2026),
      hinario: 'harpa',
      numero: n,
    );

IndiceDoHinario _indice(Map<int, String> titulos) =>
    IndiceDoHinario(hinario: 'harpa', titulos: titulos);

void main() {
  group('juntar o repertório e a biblioteca', () {
    test('um hino que está nos dois aparece UMA vez, como o do repertório', () {
      final itens = itensDoHinario(
        hinario: 'harpa',
        repertorio: [_hino(15, 'Manhã de paz')],
        indice: _indice({15: 'Manhã de paz', 16: 'Rocha firme'}),
      );
      expect(itens.map((i) => i.numero), [15, 16]);
      expect(itens.first.musica, isNotNull);
      expect(itens.last.musica, isNull);
    });

    test('o título sai SEM o "HC 15 · " que o app grava', () {
      final itens = itensDoHinario(
        hinario: 'harpa',
        repertorio: [_hino(15, 'Manhã de paz')],
        indice: _indice({}),
      );
      expect(itens.single.titulo, 'Manhã de paz');
    });

    test('hino de outro hinário não entra', () {
      final cantor = SongModel(
        id: 'c1',
        name: 'CC 1 · Outro',
        artist: '',
        lyrics: '',
        originalKey: 'C',
        createdAt: DateTime(2026),
        hinario: 'cantor',
        numero: 1,
      );
      final itens = itensDoHinario(
        hinario: 'harpa',
        repertorio: [cantor, _hino(2, 'Dois')],
        indice: _indice({}),
      );
      expect(itens.map((i) => i.numero), [2]);
    });

    test('música sem número (a comum do repertório) nunca entra', () {
      final comum = SongModel(
        id: 'm1',
        name: 'Qualquer',
        artist: '',
        lyrics: '',
        originalKey: 'C',
        createdAt: DateTime(2026),
      );
      expect(
        itensDoHinario(
            hinario: 'harpa', repertorio: [comum], indice: _indice({})),
        isEmpty,
      );
    });

    test('a letra baixada serve à busca dos hinos que só estão na biblioteca',
        () {
      final itens = itensDoHinario(
        hinario: 'harpa',
        repertorio: const [],
        indice: _indice({7: 'Sete'}),
        letras: {7: 'firmes na promessa'},
      );
      expect(itens.single.letra, 'firmes na promessa');
    });

    test('a letra do repertório vale mais que a baixada', () {
      final itens = itensDoHinario(
        hinario: 'harpa',
        repertorio: [_hino(7, 'Sete', letra: 'letra do repertório')],
        indice: _indice({7: 'Sete'}),
        letras: {7: 'letra baixada'},
      );
      expect(itens.single.letra, 'letra do repertório');
    });

    test('vem em ordem de número, mesmo com tudo embaralhado', () {
      final itens = itensDoHinario(
        hinario: 'harpa',
        repertorio: [_hino(30, 'C'), _hino(2, 'B')],
        indice: _indice({10: 'A', 1: 'D'}),
      );
      expect(itens.map((i) => i.numero), [1, 2, 10, 30]);
    });
  });

  group('procurar por nome, número ou trecho', () {
    final itens = itensDoHinario(
      hinario: 'harpa',
      repertorio: [
        _hino(15, 'Manhã de paz',
            letra: '1 Firmes nas promessas do Senhor,\nem toda a jornada.'),
      ],
      indice: _indice({
        150: 'Rocha firme',
        151: 'Descanso nas águas',
        65: 'Jardim da esperança',
      }),
      letras: {
        65: 'Quem guarda o seu povo\nnão deixa de amparar',
        151: '1 Se vier a noite escura,\nnão vamos desanimar',
      },
    );

    test('busca vazia mostra todos', () {
      expect(filtrarItens(itens, '').length, itens.length);
      expect(filtrarItens(itens, '   ').length, itens.length);
    });

    test('pelo nome, sem acento e sem maiúscula', () {
      expect(filtrarItens(itens, 'manha').map((i) => i.numero), [15]);
      expect(filtrarItens(itens, 'DESCANSO').map((i) => i.numero), [151]);
    });

    test('por um trecho da letra, mesmo sem lembrar o nome', () {
      expect(filtrarItens(itens, 'noite escura').map((i) => i.numero), [151]);
      expect(filtrarItens(itens, 'amparar').map((i) => i.numero), [65]);
    });

    test('as palavras podem vir fora de ordem', () {
      // "firme nas promessas" é como a pessoa lembra; a letra diz "Firmes".
      expect(
          filtrarItens(itens, 'promessas firmes').map((i) => i.numero), [15]);
    });

    test('todas as palavras têm de aparecer', () {
      expect(filtrarItens(itens, 'firmes jardim'), isEmpty);
    });

    test('só dígitos procuram pelo NÚMERO, não dentro das letras', () {
      // "1" apareceria como estrofe em quase toda letra ("1 Firmes…") e a
      // lista inteira viraria resultado.
      expect(filtrarItens(itens, '15').map((i) => i.numero), [15, 150, 151]);
      expect(filtrarItens(itens, '1').map((i) => i.numero), [15, 150, 151]);
      expect(filtrarItens(itens, '6').map((i) => i.numero), [65]);
    });

    test('número que não existe não acha nada', () {
      expect(filtrarItens(itens, '999'), isEmpty);
    });
  });

  group('o trecho que a busca mostra embaixo do título', () {
    const letra = '1 Firmes nas promessas do Senhor,\n'
        'em toda a jornada;\n\n'
        'REFRÃO\n'
        'Quem guarda o seu povo\n'
        'não deixa de amparar.';

    test('é a linha em que a busca apareceu, sem o número da estrofe', () {
      expect(trechoDaBusca(letra, 'promessas'),
          'Firmes nas promessas do Senhor,');
      expect(trechoDaBusca(letra, 'amparar'), 'não deixa de amparar.');
    });

    test('ignora acento e maiúscula', () {
      expect(trechoDaBusca(letra, 'JORNADA'), 'em toda a jornada;');
      expect(trechoDaBusca(letra, 'refrao'), 'REFRÃO');
    });

    test('com várias palavras, vale a linha que tem todas; senão a primeira',
        () {
      expect(trechoDaBusca(letra, 'firmes promessas'),
          'Firmes nas promessas do Senhor,');
      // As palavras estão em linhas diferentes: mostra onde a primeira está.
      expect(trechoDaBusca(letra, 'jornada amparar'), 'em toda a jornada;');
    });

    test('sem letra, sem busca ou sem achar: nada', () {
      expect(trechoDaBusca(null, 'x'), isNull);
      expect(trechoDaBusca(letra, ''), isNull);
      expect(trechoDaBusca(letra, 'zzz'), isNull);
    });

    test('só dígitos não mostram trecho (a busca foi pelo número)', () {
      expect(trechoDaBusca(letra, '15'), isNull);
    });

    test('linha comprida é cortada com reticências', () {
      final longa = 'palavra ${'muito ' * 40}fim';
      final t = trechoDaBusca(longa, 'palavra')!;
      expect(t.length, lessThanOrEqualTo(80));
      expect(t.endsWith('…'), isTrue);
    });
  });

  group('as ordens', () {
    final itens = itensDoHinario(
      hinario: 'harpa',
      repertorio: [
        _hino(300, 'Ó vem, Senhor', id: 'a'),
        _hino(20, 'Zelo e fé', id: 'b'),
      ],
      indice: _indice({
        5: 'Amor sem fim',
        100: 'Bendito seja',
        20: 'Zelo e fé',
        300: 'Ó vem, Senhor',
      }),
    );

    List<int> ordem(OrdemDosHinos o,
            {Map<String, int> vezes = const {}, Set<String> fav = const {}}) =>
        ordenarItens(itens, o, vezesTocadas: vezes, favoritas: fav)
            .map((i) => i.numero)
            .toList();

    test('pelo número, crescente', () {
      expect(ordem(OrdemDosHinos.numero), [5, 20, 100, 300]);
    });

    test('pelo nome A–Z, sem acento atrapalhar', () {
      // "Ó vem" tem de cair no O, e não depois do Z.
      expect(ordem(OrdemDosHinos.nome), [5, 100, 300, 20]);
    });

    test('pelo nome Z–A é o inverso exato', () {
      expect(ordem(OrdemDosHinos.nomeDescendente), [20, 300, 100, 5]);
    });

    test('mais tocados primeiro; o número desempata', () {
      expect(ordem(OrdemDosHinos.maisTocados, vezes: {'b': 5, 'a': 2}),
          [20, 300, 5, 100]);
    });

    test('hino só da biblioteca conta zero vezes tocado', () {
      expect(ordem(OrdemDosHinos.maisTocados), [5, 20, 100, 300]);
    });

    test('favoritos primeiro; o número desempata', () {
      expect(ordem(OrdemDosHinos.favoritos, fav: {'a'}), [300, 5, 20, 100]);
    });

    test('ordenar não perde nem repete ninguém', () {
      for (final o in OrdemDosHinos.values) {
        expect(ordem(o).toSet(), {5, 20, 100, 300}, reason: o.id);
        expect(ordem(o).length, 4, reason: o.id);
      }
    });

    test('não mexe na lista de entrada', () {
      final antes = itens.map((i) => i.numero).toList();
      ordenarItens(itens, OrdemDosHinos.nomeDescendente);
      expect(itens.map((i) => i.numero).toList(), antes);
    });
  });
}
