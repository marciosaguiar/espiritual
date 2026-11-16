import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:levitasync/core/utils/texto.dart';
import 'package:levitasync/data/models/scale_model.dart';
import 'package:levitasync/data/models/song_model.dart';
import 'package:levitasync/presentation/providers/scale_provider.dart';
import 'package:levitasync/presentation/widgets/songs/escolher_musicas.dart';

SongModel musica(String id, String nome, {String artista = ''}) => SongModel(
      id: id,
      name: nome,
      artist: artista,
      lyrics: '',
      originalKey: 'G',
      createdAt: DateTime(2026),
    );

ScaleModel culto(DateTime quando, List<String> ids,
        {bool cancelado = false}) =>
    ScaleModel(
      id: ScaleModel.idPara(quando),
      date: quando,
      createdAt: DateTime(2026),
      songs: ids.map((i) => ScaleSong(songId: i)).toList(),
      canceled: cancelado,
    );

void main() {
  // `DateFormat` com locale precisa dos dados carregados, como no `main()` do
  // app. Sem isto o teste da data falha por falta de inicialização, e não por
  // defeito no texto.
  setUpAll(() => initializeDateFormatting('pt_BR', null));

  group('busca sem acento', () {
    test('acha "Coração" digitando "coracao", e o contrário', () {
      // Ninguém digita acento no celular com pressa, e era isso que fazia a
      // busca não achar a música.
      expect(combina('coracao', ['Coração Igual ao Teu']), isTrue);
      expect(combina('CORAÇÃO', ['coracao igual ao teu']), isTrue);
    });

    test('acha pelo artista também', () {
      expect(combina('aline', ['Ruja o Leão', 'Aline Barros']), isTrue);
    });

    test('busca vazia não esconde o repertório', () {
      expect(combina('', ['qualquer coisa']), isTrue);
      expect(combina('   ', ['qualquer coisa']), isTrue);
    });

    test('o que não existe não aparece', () {
      expect(combina('jazz', ['Ruja o Leão', 'Aline Barros']), isFalse);
    });

    test('todo acento do português vira letra simples', () {
      expect(semAcento('ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇÑ'),
          'aaaaaeeeeiiiiooooouuuucn');
    });
  });

  group('quando cada música foi tocada', () {
    final agora = DateTime(2026, 11, 16, 20);

    test('vale o culto mais recente que já passou', () {
      final mapa = ScaleProvider.ultimaVezTocada([
        culto(DateTime(2026, 10, 5, 19), ['a']),
        culto(DateTime(2026, 11, 2, 19), ['a', 'b']),
      ], agora);
      expect(mapa['a'], DateTime(2026, 11, 2, 19));
      expect(mapa['b'], DateTime(2026, 11, 2, 19));
    });

    test('culto FUTURO não conta: ainda não foi tocado', () {
      final mapa = ScaleProvider.ultimaVezTocada([
        culto(DateTime(2026, 11, 22, 19), ['a']),
      ], agora);
      expect(mapa.containsKey('a'), isFalse);
    });

    test('culto CANCELADO não conta: ninguém tocou nele', () {
      final mapa = ScaleProvider.ultimaVezTocada([
        culto(DateTime(2026, 11, 2, 19), ['a'], cancelado: true),
      ], agora);
      expect(mapa.containsKey('a'), isFalse);
    });

    test('sem cultos, mapa vazio', () {
      expect(ScaleProvider.ultimaVezTocada(const [], agora), isEmpty);
    });
  });

  group('o texto da última vez não mente', () {
    test('com data, diz a data', () {
      expect(textoDaUltimaVez(DateTime(2026, 10, 12)), 'tocada em 12/10');
    });

    test('SEM data, NÃO diz "nunca tocada"', () {
      // O app só lê os cultos dos últimos 60 dias. Uma música do ano passado
      // apareceria como nunca tocada, e o líder montaria o culto com base
      // numa informação falsa.
      final texto = textoDaUltimaVez(null);
      expect(texto.toLowerCase().contains('nunca'), isFalse);
      expect(texto, 'não tocada nos últimos 2 meses');
    });
  });

  group('a ordem da lista', () {
    final a = musica('a', 'Aleluia');
    final b = musica('b', 'Bondade de Deus');
    final c = musica('c', 'Canção do Apocalipse');

    test('menos tocadas primeiro, da mais antiga para a mais recente', () {
      final ordem = ordenar([a, b, c], OrdemDaEscolha.menosTocadas, {
        'a': DateTime(2026, 11, 9),
        'b': DateTime(2026, 10, 5),
        'c': DateTime(2026, 11, 2),
      });
      expect(ordem.map((m) => m.id).toList(), ['b', 'c', 'a']);
    });

    test('música SEM registro vem primeiro — é o que o líder procura', () {
      // Música nova, e música que não é tocada há mais tempo que a janela de
      // leitura, caem as duas aqui.
      final ordem = ordenar([a, b], OrdemDaEscolha.menosTocadas, {
        'a': DateTime(2026, 11, 9),
      });
      expect(ordem.map((m) => m.id).toList(), ['b', 'a']);
    });

    test('duas sem registro saem por nome, para a lista não dançar', () {
      final ordem =
          ordenar([c, b, a], OrdemDaEscolha.menosTocadas, const {});
      expect(ordem.map((m) => m.id).toList(), ['a', 'b', 'c']);
    });

    test('A–Z ignora acento na comparação', () {
      final comAcento = musica('z', 'Água Viva');
      final ordem = ordenar(
          [b, comAcento], OrdemDaEscolha.alfabetica, const {});
      // "Água" antes de "Bondade": sem tirar o acento, 'Á' cairia depois de
      // toda letra simples e a lista ficaria em ordem errada.
      expect(ordem.map((m) => m.id).toList(), ['z', 'b']);
    });

    test('ordenar não mexe na lista que recebeu', () {
      final original = [c, a, b];
      ordenar(original, OrdemDaEscolha.alfabetica, const {});
      expect(original.map((m) => m.id).toList(), ['c', 'a', 'b']);
    });
  });
}
