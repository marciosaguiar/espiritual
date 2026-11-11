import 'package:flutter_test/flutter_test.dart';
import 'package:levitasync/data/models/arrangement_model.dart';
import 'package:levitasync/data/models/scale_model.dart';
import 'package:levitasync/data/models/song_model.dart';

void main() {
  group('links da música', () {
    test('o nome do link vem do site quando não é informado', () {
      expect(const SongLink(url: 'https://www.youtube.com/watch?v=x').displayLabel,
          'YouTube');
      expect(const SongLink(url: 'https://youtu.be/x').displayLabel, 'YouTube');
      expect(const SongLink(url: 'https://www.cifraclub.com.br/a/b').displayLabel,
          'Cifra Club');
      expect(const SongLink(url: 'https://open.spotify.com/track/x').displayLabel,
          'Spotify');
      expect(const SongLink(url: 'https://exemplo.com.br/x').displayLabel,
          'exemplo.com.br');
    });

    test('nome escrito à mão tem prioridade', () {
      expect(
        const SongLink(url: 'https://youtube.com/x', label: 'Ao vivo 2024')
            .displayLabel,
        'Ao vivo 2024',
      );
    });

    test('endereço quebrado não derruba a tela', () {
      expect(const SongLink(url: 'nao é url').displayLabel, isNotEmpty);
      expect(const SongLink(url: '').displayLabel, isNotEmpty);
    });

    test('videoUrl encontra o primeiro vídeo entre os links', () {
      final song = SongModel(
        id: 's1',
        name: 'Digno és',
        artist: 'Hillsong',
        lyrics: 'a',
        originalKey: 'G',
        links: const [
          SongLink(url: 'https://cifraclub.com.br/x'),
          SongLink(url: 'https://youtube.com/watch?v=abc'),
        ],
        createdAt: DateTime(2026),
      );
      expect(song.videoUrl, 'https://youtube.com/watch?v=abc');
    });

    test('música sem vídeo devolve null', () {
      final song = SongModel(
        id: 's1',
        name: 'x',
        artist: '',
        lyrics: '',
        originalKey: 'C',
        createdAt: DateTime(2026),
      );
      expect(song.videoUrl, isNull);
    });

    test('música antiga com youtubeUrl vira um link', () {
      final song = SongModel.fromJson({
        'id': 's1',
        'name': 'Antiga',
        'originalKey': 'D',
        'youtubeUrl': 'https://youtube.com/watch?v=zzz',
        'createdAt': DateTime(2026).toIso8601String(),
      });
      expect(song.links.length, 1);
      expect(song.videoUrl, 'https://youtube.com/watch?v=zzz');
    });

    test('a música não carrega mais a cifra', () {
      final json = SongModel(
        id: 's1',
        name: 'x',
        artist: '',
        lyrics: 'letra',
        originalKey: 'C',
        createdAt: DateTime(2026),
      ).toFirestore();
      // A cifra é do arranjo: não pode voltar para o documento da música,
      // senão abrir a lista baixa o repertório inteiro outra vez.
      expect(json.containsKey('chords'), isFalse);
    });
  });

  group('escala guarda só referências', () {
    test('ida e volta preserva as referências', () {
      const ref = ScaleSong(
          songId: 's1', arrangementId: 'a1', keyOverride: 'E');
      final volta = ScaleSong.fromMap(ref.toMap());
      expect(volta.songId, 's1');
      expect(volta.arrangementId, 'a1');
      expect(volta.keyOverride, 'E');
    });

    test('não guarda nome nem artista copiados', () {
      final map = const ScaleSong(songId: 's1').toMap();
      expect(map.containsKey('songName'), isFalse);
      expect(map.containsKey('artist'), isFalse);
    });

    test('escala antiga com "key" copiado é lida como tom do culto', () {
      final volta = ScaleSong.fromMap({
        'songId': 's1',
        'songName': 'Nome velho',
        'artist': 'Artista velho',
        'key': 'A',
      });
      expect(volta.songId, 's1');
      expect(volta.keyOverride, 'A');
    });

    test('sem tom próprio, keyOverride fica vazio', () {
      expect(ScaleSong.fromMap({'songId': 's1'}).keyOverride, isEmpty);
    });
  });

  group('arranjo da igreja', () {
    test('ida e volta pelo JSON preserva os campos', () {
      final arr = ArrangementModel(
        id: 'a1',
        songId: 's1',
        name: 'Acústico',
        churchKey: 'G',
        chords: '[G]Digno és',
        structure: const ['intro', 'verso'],
        bpm: 72,
        notes: 'entra só com violão',
        updatedAt: DateTime(2026, 5, 1),
      );
      final volta = ArrangementModel.fromJson(arr.toJson());
      expect(volta.name, 'Acústico');
      expect(volta.churchKey, 'G');
      expect(volta.chords, '[G]Digno és');
      expect(volta.structure, ['intro', 'verso']);
      expect(volta.bpm, 72);
      expect(volta.notes, 'entra só com violão');
      expect(volta.updatedAt, DateTime(2026, 5, 1));
    });

    test('arranjo sem cifra é reconhecido', () {
      final vazio = ArrangementModel(
        id: 'a1',
        songId: 's1',
        churchKey: 'C',
        updatedAt: DateTime(2026),
      );
      expect(vazio.hasChords, isFalse);
      expect(vazio.copyWith(chords: '   ').hasChords, isFalse);
      expect(vazio.copyWith(chords: '[C]x').hasChords, isTrue);
    });
  });

  group('preferência pessoal', () {
    test('preferência vazia é descartável', () {
      final pref = SongPrefModel(songId: 's1', updatedAt: DateTime(2026));
      expect(pref.isEmpty, isTrue);
      expect(pref.copyWith(semitones: 2).isEmpty, isFalse);
      expect(pref.copyWith(notes: 'segunda voz').isEmpty, isFalse);
      expect(pref.copyWith(notes: '   ').isEmpty, isTrue);
      expect(pref.copyWith(capo: 2).isEmpty, isFalse);
    });

    test('copyWith mantém o que não foi passado', () {
      final pref = SongPrefModel(
        songId: 's1',
        semitones: 2,
        notes: 'minha nota',
        updatedAt: DateTime(2026),
      );
      final so_tom = pref.copyWith(semitones: -1);
      expect(so_tom.notes, 'minha nota');
      expect(so_tom.semitones, -1);
    });

    test('ida e volta pelo Firestore', () {
      final pref = SongPrefModel(
        songId: 's1',
        semitones: -2,
        notes: 'capotraste na 2ª',
        capo: 2,
        updatedAt: DateTime(2026, 7, 7),
      );
      final volta = SongPrefModel.fromFirestore(pref.toFirestore());
      expect(volta.songId, 's1');
      expect(volta.semitones, -2);
      expect(volta.notes, 'capotraste na 2ª');
      expect(volta.capo, 2);
    });
  });
}
