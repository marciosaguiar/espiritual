import 'package:flutter_test/flutter_test.dart';
import 'package:levitasync/data/models/scale_model.dart';
import 'package:levitasync/presentation/providers/scale_provider.dart';

/// "Minhas próximas músicas": o que EU vou tocar nos próximos sete dias.
///
/// Conta de data, e conta de data quebra na virada do dia — por isso `agora`
/// entra como parâmetro.
const EU = 'eu';
const OUTRO = 'outro';

ScaleSong musica(String id) => ScaleSong(songId: id);

ScaleLevita escalado(String quem, {String funcao = 'bass'}) =>
    ScaleLevita(userId: quem, userName: '', instrument: funcao);

ScaleModel culto(
  DateTime quando, {
  List<ScaleLevita> levitas = const [],
  List<ScaleSong> songs = const [],
  bool cancelado = false,
}) =>
    ScaleModel(
      id: ScaleModel.idPara(quando),
      date: quando,
      createdAt: DateTime(2026),
      levitas: levitas,
      songs: songs,
      canceled: cancelado,
    );

void main() {
  final agora = DateTime(2026, 11, 16, 20, 0); // segunda, 20h

  group('o que entra na lista', () {
    test('as músicas do culto em que eu estou escalado', () {
      final lista = ScaleProvider.minhasProximasMusicas(
        cultos: [
          culto(DateTime(2026, 11, 18, 8),
              levitas: [escalado(EU)],
              songs: [musica('a'), musica('b')]),
        ],
        userId: EU,
        agora: agora,
      );
      expect(lista.map((m) => m.ref.songId).toList(), ['a', 'b']);
      expect(lista.first.instrumento, 'bass');
    });

    test('culto em que eu NÃO estou escalado fica fora', () {
      final lista = ScaleProvider.minhasProximasMusicas(
        cultos: [
          culto(DateTime(2026, 11, 18, 8),
              levitas: [escalado(OUTRO)], songs: [musica('a')]),
        ],
        userId: EU,
        agora: agora,
      );
      expect(lista, isEmpty);
    });

    test('culto CANCELADO fica fora', () {
      // O culto cancelado continua existindo no banco de propósito, para o
      // gerador não recriá-lo. Mas ninguém ensaia para um culto cancelado.
      final lista = ScaleProvider.minhasProximasMusicas(
        cultos: [
          culto(DateTime(2026, 11, 18, 8),
              levitas: [escalado(EU)],
              songs: [musica('a')],
              cancelado: true),
        ],
        userId: EU,
        agora: agora,
      );
      expect(lista, isEmpty);
    });

    test('culto além dos sete dias fica fora', () {
      final lista = ScaleProvider.minhasProximasMusicas(
        cultos: [
          culto(DateTime(2026, 11, 22, 19),
              levitas: [escalado(EU)], songs: [musica('perto')]),
          culto(DateTime(2026, 11, 29, 19),
              levitas: [escalado(EU)], songs: [musica('longe')]),
        ],
        userId: EU,
        agora: agora,
      );
      expect(lista.map((m) => m.ref.songId).toList(), ['perto']);
    });

    test('culto que já passou fica fora, mas o que está acontecendo FICA', () {
      // Quem abre o app no meio do culto precisa da música que está sendo
      // tocada — é a mesma janela de duas horas do "próximo culto".
      final lista = ScaleProvider.minhasProximasMusicas(
        cultos: [
          culto(DateTime(2026, 11, 16, 19),
              levitas: [escalado(EU)], songs: [musica('agora')]),
          culto(DateTime(2026, 11, 15, 19),
              levitas: [escalado(EU)], songs: [musica('ontem')]),
        ],
        userId: EU,
        agora: agora,
      );
      expect(lista.map((m) => m.ref.songId).toList(), ['agora']);
    });

    test('culto sem música nenhuma não entra com linha vazia', () {
      final lista = ScaleProvider.minhasProximasMusicas(
        cultos: [culto(DateTime(2026, 11, 18, 8), levitas: [escalado(EU)])],
        userId: EU,
        agora: agora,
      );
      expect(lista, isEmpty);
    });
  });

  group('a ordem e a função', () {
    test('sai em ordem de culto, mesmo recebendo fora de ordem', () {
      final lista = ScaleProvider.minhasProximasMusicas(
        cultos: [
          culto(DateTime(2026, 11, 20, 19),
              levitas: [escalado(EU)], songs: [musica('sexta')]),
          culto(DateTime(2026, 11, 18, 8),
              levitas: [escalado(EU)], songs: [musica('quarta')]),
        ],
        userId: EU,
        agora: agora,
      );
      expect(lista.map((m) => m.ref.songId).toList(), ['quarta', 'sexta']);
    });

    test('a ordem das músicas DENTRO do culto é a do repertório', () {
      // O líder monta a ordem do culto; a tela não pode reordenar.
      final lista = ScaleProvider.minhasProximasMusicas(
        cultos: [
          culto(DateTime(2026, 11, 18, 8),
              levitas: [escalado(EU)],
              songs: [musica('terceira'), musica('primeira')]),
        ],
        userId: EU,
        agora: agora,
      );
      expect(
          lista.map((m) => m.ref.songId).toList(), ['terceira', 'primeira']);
    });

    test('a função é a DAQUELE culto, e pode mudar de um para o outro', () {
      // Quem canta num domingo e toca baixo no outro precisa abrir a música
      // no modo certo em cada um.
      final lista = ScaleProvider.minhasProximasMusicas(
        cultos: [
          culto(DateTime(2026, 11, 18, 8),
              levitas: [escalado(EU, funcao: 'vocalist')],
              songs: [musica('quarta')]),
          culto(DateTime(2026, 11, 22, 19),
              levitas: [escalado(EU, funcao: 'keyboard')],
              songs: [musica('domingo')]),
        ],
        userId: EU,
        agora: agora,
      );
      expect(lista[0].instrumento, 'vocalist');
      expect(lista[1].instrumento, 'keyboard');
    });
  });

  group('casos que derrubariam a tela', () {
    test('sem id de pessoa, lista vazia em vez de tudo', () {
      // `userId` vazio chegaria aqui se a sessão ainda não tivesse carregado.
      // Devolver tudo mostraria a escala de outra pessoa.
      final lista = ScaleProvider.minhasProximasMusicas(
        cultos: [
          culto(DateTime(2026, 11, 18, 8),
              levitas: [escalado(EU)], songs: [musica('a')]),
        ],
        userId: '',
        agora: agora,
      );
      expect(lista, isEmpty);
    });

    test('nenhum culto, nenhuma música', () {
      expect(
          ScaleProvider.minhasProximasMusicas(
              cultos: const [], userId: EU, agora: agora),
          isEmpty);
    });
  });
}
