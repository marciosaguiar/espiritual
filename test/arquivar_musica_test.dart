import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:levitasync/data/models/song_model.dart';

/// Tirar do repertório não pode virar "sumiu".
///
/// A regra que não pode quebrar: a música arquivada continua existindo e
/// continua resolvendo pelo id, porque é isso que mantém o nome dela nos
/// cultos em que foi tocada. O que muda é só onde ela aparece.
void main() {
  SongModel musica({bool archived = false}) => SongModel(
        id: 's1',
        name: 'Sou Grato Pelo Seu Amor',
        artist: 'Morada',
        lyrics: 'a',
        originalKey: 'D',
        createdAt: DateTime(2026, 1, 1),
        archived: archived,
        archivedAt: archived ? DateTime(2026, 11, 15, 9, 30) : null,
        archivedBy: archived ? 'uid-lider' : null,
      );

  group('o carimbo de arquivamento', () {
    test('vai e volta do Firestore', () {
      final lida = SongModel.fromFirestore(musica(archived: true).toFirestore());
      expect(lida.archived, isTrue);
      expect(lida.archivedAt, DateTime(2026, 11, 15, 9, 30));
      expect(lida.archivedBy, 'uid-lider');
      // O que importa: o nome continua lá.
      expect(lida.name, 'Sou Grato Pelo Seu Amor');
    });

    test('vai e volta do aparelho sem Timestamp no caminho', () {
      // jsonEncode sobre um Timestamp lança — ver CLAUDE.md.
      final json = musica(archived: true).toJson();
      expect(json['archivedAt'], isA<String>());
      expect(SongModel.fromJson(json).archived, isTrue);
    });

    test('música gravada antes do arquivamento está no repertório', () {
      final dados = musica().toFirestore()
        ..remove('archived')
        ..remove('archivedAt')
        ..remove('archivedBy');
      expect(SongModel.fromFirestore(dados).archived, isFalse);
    });

    test('devolver ao repertório limpa o carimbo', () {
      final devolvida = musica(archived: true).copyWith(limparArquivamento: true);
      expect(devolvida.archived, isFalse);
      expect(devolvida.archivedAt, isNull);
      expect(devolvida.archivedBy, isNull);
    });

    test('copyWith comum não desarquiva sem querer', () {
      final corrigida = musica(archived: true).copyWith(name: 'Outro nome');
      expect(corrigida.archived, isTrue);
      expect(corrigida.archivedBy, 'uid-lider');
    });

    test('o Timestamp do Firestore sobrevive à ida e volta', () {
      final dados = musica(archived: true).toFirestore();
      expect(dados['archivedAt'], isA<Timestamp>());
    });
  });

  group('onde a música arquivada aparece', () {
    final repertorio = [
      musica(),
      SongModel(
        id: 's2',
        name: 'Digno',
        artist: 'x',
        lyrics: '',
        originalKey: 'G',
        createdAt: DateTime(2026, 1, 1),
        archived: true,
      ),
    ];

    test('some da lista que se pode escolher', () {
      final visiveis = repertorio.where((s) => !s.archived).toList();
      expect(visiveis.map((s) => s.id), ['s1']);
    });

    test('continua achável por id, que é o que salva o culto antigo', () {
      // Se sumisse daqui, o culto voltaria a mostrar "Música removida" —
      // exatamente o que o arquivamento existe para evitar.
      final achada = repertorio.firstWhere((s) => s.id == 's2');
      expect(achada.name, 'Digno');
    });
  });
}
