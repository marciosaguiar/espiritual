import 'package:flutter_test/flutter_test.dart';
import 'package:levitasync/core/platform/armazem.dart';
import 'package:levitasync/core/utils/snapshot_local.dart';
import 'package:levitasync/core/utils/uso_de_leituras.dart';
import 'package:levitasync/data/models/scale_model.dart';
import 'package:levitasync/data/models/song_model.dart';
import 'package:levitasync/data/services/modo_economia.dart';
import 'package:levitasync/presentation/providers/songs_provider.dart';

/// O repertório é lido POR NECESSIDADE, e o Início resolve as músicas de um
/// culto pelo id.
///
/// Antes, o app lia o repertório inteiro (uma leitura por música) a cada
/// abertura. Com 42 músicas isso passa despercebido; com 300, seis aberturas de
/// domingo gastam sozinhas 1.800 leituras por pessoa. O que estes testes contam
/// é CHAMADA AO BANCO: provar o custo, em vez de acreditar na leitura do código.
///
/// E o que NÃO pode acontecer: uma música de culto aparecer como "removida"
/// só porque o repertório ainda não foi baixado, ou uma lista de três músicas
/// passar por repertório inteiro e esconder as outras por doze horas.

SongModel _m(String id, String nome) => SongModel(
      id: id,
      name: nome,
      artist: 'Artista',
      lyrics: 'letra inventada',
      originalKey: 'G',
      createdAt: DateTime(2026, 1, 1),
    );

ScaleSong _ref(String id) => ScaleSong(songId: id, arrangementId: '');

void main() {
  late int lidasInteiras;
  late List<String> lidasPorId;
  late Map<String, SongModel> banco;
  late bool semSinal;

  SongsProvider criar() {
    return SongsProvider(
      lerRepertorio: () async {
        lidasInteiras++;
        if (semSinal) return null;
        return (
          itens: banco.values.toList()
            ..sort((a, b) => a.name.compareTo(b.name)),
          doServidor: true,
        );
      },
      lerPorId: (id) async {
        lidasPorId.add(id);
        if (semSinal) return (musica: null, respondeu: false);
        return (musica: banco[id], respondeu: true);
      },
    );
  }

  setUp(() {
    Armazem.esvaziar();
    ModoEconomia.instancia.definirParaTeste(null);
    lidasInteiras = 0;
    lidasPorId = [];
    semSinal = false;
    banco = {
      'a': _m('a', 'Aliança'),
      'b': _m('b', 'Bondade'),
      'c': _m('c', 'Cordeiro'),
    };
  });

  tearDown(() => ModoEconomia.instancia.definirParaTeste(null));

  group('abrir o app NÃO lê o repertório', () {
    test('ligar as escutas (o que o app faz na abertura) não lê nada', () async {
      final p = criar()..listenToSongs();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(lidasInteiras, 0);
      expect(lidasPorId, isEmpty);
      expect(p.allSongs, isEmpty);
      p.dispose();
    });
  });

  group('a lista inteira, quando alguém a pede', () {
    test('a primeira vez lê uma vez e mostra', () async {
      final p = criar();
      await p.atualizarSeVelho();
      expect(lidasInteiras, 1);
      expect(p.allSongs.map((s) => s.id), ['a', 'b', 'c']);
      expect(p.repertorioCompleto, isTrue);
      p.dispose();
    });

    test('pedir de novo dentro do prazo NÃO lê de novo', () async {
      final p = criar();
      final t = DateTime(2026, 11, 21, 8);
      await p.atualizarSeVelho(agora: t);
      await p.atualizarSeVelho(agora: t.add(const Duration(hours: 11, minutes: 59)));
      expect(lidasInteiras, 1);
      p.dispose();
    });

    test('passado o prazo (12 h) lê de novo', () async {
      final p = criar();
      final t = DateTime(2026, 11, 21, 8);
      await p.atualizarSeVelho(agora: t);
      await p.atualizarSeVelho(agora: t.add(const Duration(hours: 12, minutes: 1)));
      expect(lidasInteiras, 2);
      p.dispose();
    });

    test('"Atualizar a lista" ignora o prazo — é a pessoa pedindo', () async {
      final p = criar();
      await p.atualizarSeVelho();
      banco['d'] = _m('d', 'Dádiva');
      await p.atualizarSeVelho(forcar: true);
      expect(lidasInteiras, 2);
      expect(p.allSongs.map((s) => s.id), contains('d'));
      p.dispose();
    });

    test('em modo de economia, com músicas na tela, a lista inteira espera', () async {
      final p = criar();
      await p.atualizarSeVelho(); // já tem a lista
      ModoEconomia.instancia.definirParaTeste(const UsoDoDia(leituras: 41000));
      await p.atualizarSeVelho(agora: DateTime.now().add(const Duration(days: 2)));
      expect(lidasInteiras, 1);
      p.dispose();
    });

    test('em modo de economia mas SEM nada na tela, lê: tela vazia é pior', () async {
      ModoEconomia.instancia.definirParaTeste(const UsoDoDia(leituras: 41000));
      final p = criar();
      await p.atualizarSeVelho();
      expect(lidasInteiras, 1);
      expect(p.allSongs, hasLength(3));
      p.dispose();
    });

    test('sem sinal e sem cópia vira erro; com cópia fica com a cópia', () async {
      semSinal = true;
      final p = criar();
      await p.atualizarSeVelho();
      expect(p.error, isNotNull);

      final q = criar()..carregarParaTeste([_m('a', 'Aliança')]);
      // `carregarParaTeste` desliga o banco: nada é lido nas telas de teste.
      await q.atualizarSeVelho(forcar: true);
      expect(lidasInteiras, 1); // só a do `p`
      expect(q.allSongs, hasLength(1));
      p.dispose();
      q.dispose();
    });
  });

  group('uma música de culto é resolvida pelo id', () {
    test('música que falta: pede UMA vez e diz "Carregando…" enquanto isso', () async {
      final p = criar();
      expect(p.nameOf(_ref('b')), 'Carregando…');
      // Pedir de novo, no mesmo quadro ou no seguinte, não pede de novo.
      p.nameOf(_ref('b'));
      p.getSongById('b');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(lidasPorId, ['b']);
      expect(p.nameOf(_ref('b')), 'Bondade');
      expect(lidasInteiras, 0); // e o repertório inteiro NÃO foi lido
      p.dispose();
    });

    test('depois de chegar, não pede de novo', () async {
      final p = criar();
      p.getSongById('b');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      p.getSongById('b');
      p.nameOf(_ref('b'));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(lidasPorId, ['b']);
      p.dispose();
    });

    test('só vira "Música removida" quando o banco CONFIRMA que não existe', () async {
      final p = criar();
      expect(p.nameOf(_ref('x')), 'Carregando…');
      expect(p.exists(_ref('x')), isTrue); // "ainda não sei" não é "faltando"
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(p.nameOf(_ref('x')), 'Música removida');
      expect(p.exists(_ref('x')), isFalse);
      // E não insiste.
      p.getSongById('x');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(lidasPorId, ['x']);
      p.dispose();
    });

    test('sem sinal NÃO é "removida": diz "ainda não baixada" e tenta de novo mais tarde', () async {
      semSinal = true;
      final p = criar();
      p.getSongById('b');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(p.nameOf(_ref('b')), 'Música ainda não baixada');
      expect(p.exists(_ref('b')), isTrue);
      // Dentro da espera, não martela o banco.
      p.getSongById('b');
      p.getSongById('b');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(lidasPorId, ['b']);
      p.dispose();
    });

    test('garantirMusicas pede só as que faltam', () async {
      final p = criar();
      p.registrarLocal(_m('a', 'Aliança'));
      await p.garantirMusicas(['a', 'b', 'c']);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(lidasPorId..sort(), ['b', 'c']);
      p.dispose();
    });

    test('nas telas de teste (sem banco) nada é lido e o texto é o de sempre', () {
      final p = criar()..carregarParaTeste([_m('a', 'Aliança')]);
      expect(p.nameOf(_ref('zzz')), 'Música removida');
      expect(p.exists(_ref('zzz')), isFalse);
      expect(lidasPorId, isEmpty);
      p.dispose();
    });
  });

  group('três músicas soltas NÃO são o repertório', () {
    test('trazer músicas por id não faz a lista passar por completa', () async {
      final p = criar();
      p.getSongById('a');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(p.allSongs, hasLength(1));
      expect(p.repertorioCompleto, isFalse);
      // A lista inteira ainda é lida quando alguém a pede.
      await p.atualizarSeVelho();
      expect(lidasInteiras, 1);
      expect(p.allSongs, hasLength(3));
      expect(p.repertorioCompleto, isTrue);
      p.dispose();
    });

    test('a música cadastrada à mão entra na lista, sem estender o prazo dela', () async {
      final p = criar();
      final t = DateTime(2026, 11, 21, 8);
      await p.atualizarSeVelho(agora: t);
      p.registrarLocal(_m('z', 'Zelo'));
      expect(p.allSongs.map((s) => s.id), contains('z'));
      // Onze horas e meia depois: ainda vale. Treze: vence — a música que OUTRA
      // pessoa cadastrou não pode ficar escondida por causa de uma local.
      await p.atualizarSeVelho(agora: t.add(const Duration(hours: 13)));
      expect(lidasInteiras, 2);
      p.dispose();
    });
  });

  group('a cópia no aparelho', () {
    test('a lista inteira é guardada com a hora da LEITURA, não a de agora', () async {
      final p = criar();
      final t = DateTime(2026, 11, 21, 8);
      await p.atualizarSeVelho(agora: t);
      p.registrarLocal(_m('z', 'Zelo')); // regrava a cópia
      await Future<void>.delayed(const Duration(milliseconds: 2200));
      final quando = await SnapshotLocal.quando('songs');
      expect(quando, isNotNull);
      expect(quando!.toUtc(), t.toUtc());
      p.dispose();
    });

    test('só músicas soltas vão para a cópia "avulsas", nunca para a inteira', () async {
      final p = criar();
      p.getSongById('a');
      await Future<void>.delayed(const Duration(milliseconds: 2400));
      expect(await SnapshotLocal.ler('songs'), isNull);
      expect(await SnapshotLocal.ler('songs-avulsas'), hasLength(1));
      p.dispose();
    });

    test('abrir de novo: a cópia inteira vale pelo prazo; a avulsa não vale como inteira', () async {
      final p = criar();
      final t = DateTime.now();
      await p.atualizarSeVelho(agora: t);
      await Future<void>.delayed(const Duration(milliseconds: 2200));
      p.dispose();

      final q = criar();
      expect(await q.restaurarDoAparelho(), 3);
      expect(q.repertorioCompleto, isTrue);
      await q.atualizarSeVelho(); // dentro do prazo: não lê
      expect(lidasInteiras, 1);
      q.dispose();

      Armazem.esvaziar();
      final avulsa = criar();
      avulsa.getSongById('a');
      await Future<void>.delayed(const Duration(milliseconds: 2400));
      avulsa.dispose();
      final r = criar();
      expect(await r.restaurarDoAparelho(), 1);
      expect(r.repertorioCompleto, isFalse);
      await r.atualizarSeVelho();
      expect(lidasInteiras, 2); // lê a lista inteira, porque a cópia não era
      r.dispose();
    });
  });
}
