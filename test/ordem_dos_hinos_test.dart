import 'package:flutter_test/flutter_test.dart';
import 'package:levitasync/core/constants/hinarios.dart';
import 'package:levitasync/data/models/scale_model.dart';
import 'package:levitasync/data/models/song_model.dart';
import 'package:levitasync/presentation/providers/scale_provider.dart';
import 'package:levitasync/presentation/providers/songs_provider.dart';

/// A ordem dos hinos e a ordem dos hinários.
///
/// Lista fora de ordem NÃO DÁ ERRO: ela só faz a pessoa não achar o hino que
/// o dirigente acabou de anunciar, com a igreja de pé. Por isso tudo aqui é
/// função pura, e o que os testes guardam é principalmente o que a lista
/// nunca pode fazer — dançar entre duas aberturas, perder um hinário novo, ou
/// dizer "mais tocado" sobre o que ninguém tocou.

final agora = DateTime(2026, 11, 19, 10, 0);

SongModel hino(int numero, String nome,
        {String hinario = 'harpa', String id = ''}) =>
    SongModel(
      id: id.isEmpty ? '$hinario-$numero' : id,
      name: nome,
      artist: 'Harpa Cristã',
      lyrics: '',
      originalKey: 'D',
      createdAt: DateTime(2026),
      hinario: hinario,
      numero: numero,
    );

ScaleModel culto(DateTime quando, List<String> musicas,
        {bool cancelado = false}) =>
    ScaleModel(
      id: ScaleModel.idPara(quando),
      date: quando,
      createdAt: DateTime(2026),
      canceled: cancelado,
      songs: musicas.map((s) => ScaleSong(songId: s)).toList(),
    );

List<int> numerosDe(List<SongModel> hinos) =>
    hinos.map((h) => h.numero ?? 0).toList();

void main() {
  group('ordem dos hinos', () {
    final lista = [
      hino(15, 'Sou Grato'),
      hino(3, 'Zelo Pela Casa'),
      hino(200, 'Átrios do Senhor'),
      hino(42, 'Bendito Seja'),
    ];

    test('pelo número é a ordem de abrir o hinário na mão', () {
      final r = SongsProvider.hinosOrdenados(lista, OrdemDosHinos.numero);
      expect(numerosDe(r), [3, 15, 42, 200]);
    });

    test('pelo nome ignora acento', () {
      // "Átrios" tem de vir ANTES de "Bendito". Comparando o texto cru, o
      // código do "Á" é maior que o de qualquer letra comum e ele cairia no
      // fim da lista — depois até de "Zelo".
      final r = SongsProvider.hinosOrdenados(lista, OrdemDosHinos.nome);
      expect(r.map((h) => h.name).toList(),
          ['Átrios do Senhor', 'Bendito Seja', 'Sou Grato', 'Zelo Pela Casa']);
    });

    test('mais tocados: o número desempata, para a lista não dançar', () {
      // Com todos em zero, sem desempate a ordem sairia indefinida e a lista
      // mudaria a cada abertura — o jeito mais rápido de a pessoa tocar na
      // linha errada.
      final r = SongsProvider.hinosOrdenados(
        lista,
        OrdemDosHinos.maisTocados,
        vezesTocadas: const {},
      );
      expect(numerosDe(r), [3, 15, 42, 200]);
    });

    test('mais tocados põe o mais cantado em cima', () {
      final r = SongsProvider.hinosOrdenados(
        lista,
        OrdemDosHinos.maisTocados,
        vezesTocadas: const {'harpa-200': 5, 'harpa-15': 2},
      );
      expect(numerosDe(r), [200, 15, 3, 42]);
    });

    test('favoritos primeiro, e o resto continua por número', () {
      final r = SongsProvider.hinosOrdenados(
        lista,
        OrdemDosHinos.favoritos,
        favoritas: const {'harpa-42', 'harpa-200'},
      );
      expect(numerosDe(r), [42, 200, 3, 15]);
    });

    test('sem favorita nenhuma, a ordem não muda', () {
      final r = SongsProvider.hinosOrdenados(lista, OrdemDosHinos.favoritos);
      expect(numerosDe(r), [3, 15, 42, 200]);
    });

    test('não mexe na lista que recebeu', () {
      // Ordenar no lugar bagunçaria o repertório do provider, que é a mesma
      // lista que outras telas estão lendo.
      final original = numerosDe(lista);
      SongsProvider.hinosOrdenados(lista, OrdemDosHinos.nome);
      expect(numerosDe(lista), original);
    });

    test('lista vazia não quebra', () {
      expect(
          SongsProvider.hinosOrdenados(const [], OrdemDosHinos.nome), isEmpty);
    });
  });

  group('a chave gravada no aparelho', () {
    test('cada ordem tem um id, e eles são diferentes', () {
      final ids = OrdemDosHinos.values.map((o) => o.id).toSet();
      expect(ids.length, OrdemDosHinos.values.length);
    });

    test('valor desconhecido cai no padrão, nunca lança', () {
      // A chave vem do aparelho: pode ter sobrado de uma versão futura do app
      // ou ter sido mexida à mão.
      expect(ordemPorId('inventado'), OrdemDosHinos.numero);
      expect(ordemPorId(null), OrdemDosHinos.numero);
      expect(ordemPorId(''), OrdemDosHinos.numero);
    });

    test('ida e volta', () {
      for (final o in OrdemDosHinos.values) {
        expect(ordemPorId(o.id), o);
      }
    });
  });

  group('vezes tocadas', () {
    test('conta um culto por vez', () {
      final cultos = [
        culto(agora.subtract(const Duration(days: 7)), ['a', 'b']),
        culto(agora.subtract(const Duration(days: 14)), ['a']),
      ];
      final r = ScaleProvider.vezesTocadas(cultos, agora);
      expect(r['a'], 2);
      expect(r['b'], 1);
    });

    test('culto FUTURO não conta', () {
      // A pergunta é o que já foi tocado, não o que está marcado.
      final cultos = [
        culto(agora.add(const Duration(days: 2)), ['a'])
      ];
      expect(ScaleProvider.vezesTocadas(cultos, agora), isEmpty);
    });

    test('culto CANCELADO não conta', () {
      final cultos = [
        culto(agora.subtract(const Duration(days: 2)), ['a'], cancelado: true),
      ];
      expect(ScaleProvider.vezesTocadas(cultos, agora), isEmpty);
    });

    test('a mesma música duas vezes no mesmo culto conta UMA', () {
      // Foi um culto. Contar duas premiaria um repertório gravado com engano.
      final cultos = [
        culto(agora.subtract(const Duration(days: 1)), ['a', 'a'])
      ];
      expect(ScaleProvider.vezesTocadas(cultos, agora)['a'], 1);
    });

    test('sem culto nenhum, mapa vazio — e é isso que a tela avisa', () {
      expect(ScaleProvider.vezesTocadas(const [], agora), isEmpty);
    });
  });

  group('ordem dos hinários', () {
    test('sem nada gravado, vale a ordem de fábrica', () {
      expect(hinariosNaOrdem(const []).map((h) => h.id).toList(),
          hinariosDisponiveis.map((h) => h.id).toList());
    });

    test('a ordem gravada manda', () {
      expect(hinariosNaOrdem(const ['cantor', 'harpa']).map((h) => h.id),
          ['cantor', 'harpa']);
    });

    test('HINÁRIO NOVO aparece, mesmo com ordem antiga gravada', () {
      // Este é o teste que importa: quem arrastou os cartões uma vez tem uma
      // lista gravada com os hinários daquele dia. Se esta função devolvesse
      // só o que está gravado, um hinário acrescentado depois simplesmente
      // não apareceria — e ninguém ligaria uma coisa à outra.
      final r = hinariosNaOrdem(const ['cantor']);
      expect(r.map((h) => h.id).toList(), ['cantor', 'harpa']);
      expect(r.length, hinariosDisponiveis.length);
    });

    test('id que não existe mais é descartado', () {
      final r = hinariosNaOrdem(const ['hinario_que_saiu', 'cantor']);
      expect(r.map((h) => h.id).toList(), ['cantor', 'harpa']);
    });

    test('id repetido não duplica o cartão', () {
      final r = hinariosNaOrdem(const ['harpa', 'harpa']);
      expect(r.where((h) => h.id == 'harpa').length, 1);
    });
  });

  group('mover para cima e para baixo', () {
    const ordem = ['a', 'b', 'c'];

    test('desce um', () => expect(movido(ordem, 'a', 1), ['b', 'a', 'c']));
    test('sobe um', () => expect(movido(ordem, 'c', -1), ['a', 'c', 'b']));

    test('subir o primeiro não dá a volta', () {
      // Dar a volta mandaria o primeiro para o fim — o contrário do que a
      // pessoa pediu, e sem nada na tela para explicar.
      expect(movido(ordem, 'a', -1), ordem);
    });

    test('descer o último não dá a volta', () {
      expect(movido(ordem, 'c', 1), ordem);
    });

    test('id que não está na lista devolve a lista intacta', () {
      expect(movido(ordem, 'z', 1), ordem);
    });

    test('não mexe na lista que recebeu', () {
      final original = List<String>.from(ordem);
      movido(ordem, 'a', 1);
      expect(ordem, original);
    });
  });
}
