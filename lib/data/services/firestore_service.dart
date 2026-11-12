import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/song_model.dart';
import '../models/arrangement_model.dart';
import '../models/scale_model.dart';
import '../models/message_model.dart';
import '../../core/utils/crypto_utils.dart';

class FirestoreService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ─── Collections ──────────────────────────────────────────────────────────
  static const String _songs = 'songs';
  static const String _scales = 'scales';
  static const String _messages = 'messages';

  // ─── SONGS ────────────────────────────────────────────────────────────────

  static Stream<List<SongModel>> watchSongs() {
    return _db
        .collection(_songs)
        .orderBy('name')
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => SongModel.fromFirestore(doc.data()))
            .toList());
  }

  static Future<List<SongModel>> getSongs() async {
    final snap = await _db.collection(_songs).orderBy('name').get();
    return snap.docs.map((doc) => SongModel.fromFirestore(doc.data())).toList();
  }

  static Future<SongModel?> getSongById(String id) async {
    try {
      final doc = await _db.collection(_songs).doc(id).get();
      if (!doc.exists) return null;
      return SongModel.fromFirestore(doc.data()!);
    } catch (_) {
      return null;
    }
  }

  static Future<({bool success, String? error})> addSong(SongModel song) async {
    try {
      await _db.collection(_songs).doc(song.id).set(song.toFirestore());
      return (success: true, error: null);
    } on FirebaseException catch (e) {
      return (success: false, error: _describe(e, 'salvar a música'));
    } catch (e) {
      return (success: false, error: 'Não foi possível salvar a música: $e');
    }
  }

  static Future<({bool success, String? error})> updateSong(
      SongModel song) async {
    try {
      await _db.collection(_songs).doc(song.id).update(song.toFirestore());
      return (success: true, error: null);
    } on FirebaseException catch (e) {
      return (success: false, error: _describe(e, 'alterar a música'));
    } catch (e) {
      return (success: false, error: 'Não foi possível alterar a música: $e');
    }
  }

  static Future<({bool success, String? error})> deleteSong(
      String songId) async {
    try {
      await _db.collection(_songs).doc(songId).delete();
      return (success: true, error: null);
    } on FirebaseException catch (e) {
      return (success: false, error: _describe(e, 'apagar a música'));
    } catch (e) {
      return (success: false, error: 'Não foi possível apagar a música: $e');
    }
  }

  static Future<List<SongModel>> searchSongs(String query) async {
    if (query.isEmpty) return getSongs();
    final q = query.toLowerCase();
    final all = await getSongs();
    return all.where((s) {
      return s.name.toLowerCase().contains(q) ||
          s.artist.toLowerCase().contains(q);
    }).toList();
  }

  static SongModel createSongModel({
    required String name,
    required String artist,
    required String lyrics,
    required String originalKey,
    List<SongLink> links = const [],
    String? addedBy,
  }) {
    return SongModel(
      id: CryptoUtils.generateId(),
      name: name,
      artist: artist,
      lyrics: lyrics,
      originalKey: originalKey,
      links: links,
      addedBy: addedBy,
      createdAt: DateTime.now(),
    );
  }

  // ─── ARRANGEMENTS ─────────────────────────────────────────────────────────
  // How this church plays a song. A subcollection of the song, so the chart is
  // fetched only when somebody opens that song.

  static CollectionReference<Map<String, dynamic>> _arrangementsOf(
          String songId) =>
      _db.collection(_songs).doc(songId).collection('arrangements');

  static Future<List<ArrangementModel>> getArrangements(String songId) async {
    try {
      final snap = await _arrangementsOf(songId).get();
      return snap.docs
          .map((d) => ArrangementModel.fromFirestore(d.data()))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// The arrangement to show: the one asked for, else the first available.
  static Future<ArrangementModel?> getArrangement(
    String songId, {
    String arrangementId = '',
  }) async {
    try {
      if (arrangementId.isNotEmpty) {
        final doc = await _arrangementsOf(songId).doc(arrangementId).get();
        if (doc.exists) return ArrangementModel.fromFirestore(doc.data()!);
      }
      final snap = await _arrangementsOf(songId).limit(1).get();
      if (snap.docs.isEmpty) return null;
      return ArrangementModel.fromFirestore(snap.docs.first.data());
    } catch (_) {
      return null;
    }
  }

  static Future<({bool success, String? error, ArrangementModel? arrangement})>
      saveArrangement(ArrangementModel arrangement) async {
    try {
      await _arrangementsOf(arrangement.songId)
          .doc(arrangement.id)
          .set(arrangement.toFirestore());
      return (success: true, error: null, arrangement: arrangement);
    } on FirebaseException catch (e) {
      return (
        success: false,
        error: _describe(e, 'salvar o arranjo'),
        arrangement: null
      );
    }
  }

  static ArrangementModel createArrangementModel({
    required String songId,
    required String churchKey,
    String name = 'Padrão',
    String chords = '',
    int bpm = 0,
    String notes = '',
    String? approvedBy,
  }) {
    return ArrangementModel(
      id: CryptoUtils.generateId(),
      songId: songId,
      name: name,
      churchKey: churchKey,
      chords: chords,
      bpm: bpm,
      notes: notes,
      approvedBy: approvedBy,
      updatedAt: DateTime.now(),
    );
  }

  // ─── PERSONAL PREFERENCES ─────────────────────────────────────────────────
  // users/{userId}/songPrefs/{songId} — private to each musician.

  static CollectionReference<Map<String, dynamic>> _prefsOf(String userId) =>
      _db.collection('users').doc(userId).collection('songPrefs');

  static Future<SongPrefModel?> getSongPref(String userId, String songId) async {
    try {
      final doc = await _prefsOf(userId).doc(songId).get();
      if (!doc.exists) return null;
      return SongPrefModel.fromFirestore(doc.data()!);
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, SongPrefModel>> getAllSongPrefs(
      String userId) async {
    try {
      final snap = await _prefsOf(userId).get();
      return {
        for (final d in snap.docs)
          d.id: SongPrefModel.fromFirestore(d.data()),
      };
    } catch (_) {
      return {};
    }
  }

  static Future<({bool success, String? error})> saveSongPref(
    String userId,
    SongPrefModel pref,
  ) async {
    try {
      if (pref.isEmpty) {
        await _prefsOf(userId).doc(pref.songId).delete();
      } else {
        await _prefsOf(userId).doc(pref.songId).set(pref.toFirestore());
      }
      return (success: true, error: null);
    } on FirebaseException catch (e) {
      return (success: false, error: _describe(e, 'salvar sua preferência'));
    }
  }

  /// Turns a Firebase failure into a sentence a person can act on.
  static String _describe(FirebaseException e, String acao) {
    switch (e.code) {
      case 'permission-denied':
        return 'Você não tem permissão para $acao.';
      case 'unavailable':
        return 'Sem conexão. Não foi possível $acao.';
      case 'not-found':
        return 'O item não existe mais.';
      default:
        return 'Não foi possível $acao: ${e.message ?? e.code}';
    }
  }

  // ─── SCALES ───────────────────────────────────────────────────────────────

  static Stream<List<ScaleModel>> watchScales() {
    return _db
        .collection(_scales)
        .orderBy('date')
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => ScaleModel.fromFirestore(doc.data()))
            .toList());
  }

  static Future<List<ScaleModel>> getScales() async {
    final snap = await _db.collection(_scales).orderBy('date').get();
    return snap.docs
        .map((doc) => ScaleModel.fromFirestore(doc.data()))
        .toList();
  }

  static Future<ScaleModel?> getScaleForDate(DateTime date) async {
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));
    final snap = await _db
        .collection(_scales)
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('date', isLessThan: Timestamp.fromDate(end))
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return ScaleModel.fromFirestore(snap.docs.first.data());
  }

  static Future<List<ScaleModel>> getUpcomingScales({int limit = 5}) async {
    final now = DateTime.now();
    final snap = await _db
        .collection(_scales)
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(now))
        .orderBy('date')
        .limit(limit)
        .get();
    return snap.docs
        .map((doc) => ScaleModel.fromFirestore(doc.data()))
        .toList();
  }

  static Future<({bool success, String? error})> createScale(
      ScaleModel scale) async {
    try {
      await _db.collection(_scales).doc(scale.id).set(scale.toFirestore());
      return (success: true, error: null);
    } on FirebaseException catch (e) {
      return (success: false, error: _describe(e, 'criar o culto'));
    } catch (e) {
      return (success: false, error: 'Não foi possível criar o culto: $e');
    }
  }

  static Future<({bool success, String? error})> deleteScale(
      String scaleId) async {
    try {
      await _db.collection(_scales).doc(scaleId).delete();
      return (success: true, error: null);
    } on FirebaseException catch (e) {
      return (success: false, error: _describe(e, 'apagar o culto'));
    } catch (e) {
      return (success: false, error: 'Não foi possível apagar o culto: $e');
    }
  }

  /// Confirms or cancels one person's presence, inside a transaction.
  ///
  /// This used to read the whole `levitas` list, change one entry and write
  /// the list back. Between the read and the write anybody else's confirmation
  /// was lost — on a Sunday morning, with several people confirming at once,
  /// which is exactly when the screen is used. The transaction re-reads inside
  /// the write and Firestore retries it if the document changed meanwhile, so
  /// only this person's entry moves.
  static Future<({bool success, String? error})> confirmPresence(
    String scaleId,
    String userId,
    bool confirmed,
  ) async {
    final ref = _db.collection(_scales).doc(scaleId);
    try {
      await _db.runTransaction((tx) async {
        final snap = await tx.get(ref);
        if (!snap.exists) {
          throw FirebaseException(
            plugin: 'levitasync',
            code: 'not-found',
            message: 'culto não encontrado',
          );
        }

        final scale = ScaleModel.fromFirestore(snap.data()!);
        if (!scale.isUserInScale(userId)) {
          throw FirebaseException(
            plugin: 'levitasync',
            code: 'not-scheduled',
            message: 'você não está nesta escala',
          );
        }

        final levitas = scale.levitas
            .map((l) => l.userId == userId
                ? l.copyWith(confirmed: confirmed)
                : l)
            .map((l) => l.toMap())
            .toList();

        // Only this field is written, so nothing else in the service is
        // touched, and the security rules allow it for a levita.
        tx.update(ref, {'levitas': levitas});
      });
      return (success: true, error: null);
    } on FirebaseException catch (e) {
      if (e.code == 'not-scheduled') {
        return (success: false, error: 'Você não está escalado neste culto.');
      }
      return (success: false, error: _describe(e, 'confirmar sua presença'));
    }
  }

  /// Replaces the song list of a service, inside a transaction.
  ///
  /// Writes only `songs`, so a leader rearranging the repertoire no longer
  /// overwrites confirmations somebody is giving at the same moment.
  static Future<({bool success, String? error})> setScaleSongs(
    String scaleId,
    List<ScaleSong> songs,
  ) async {
    return _updateScaleField(
      scaleId,
      'o repertório do culto',
      (_) => {'songs': songs.map((s) => s.toMap()).toList()},
    );
  }

  /// Adds one song to the end of a service's list, inside a transaction.
  ///
  /// Used by the chat's "add to the service". Reading the list inside the
  /// transaction is what makes two leaders adding at the same time end up with
  /// both songs instead of one.
  static Future<({bool success, String? error})> addSongToScale(
    String scaleId,
    ScaleSong song,
  ) async {
    return _updateScaleField(scaleId, 'adicionar a música ao culto', (scale) {
      if (scale.songs.any((s) => s.songId == song.songId)) {
        // Already there: nothing to write.
        return null;
      }
      final songs = [...scale.songs, song];
      return {'songs': songs.map((s) => s.toMap()).toList()};
    });
  }

  /// Replaces who is scheduled, inside a transaction.
  ///
  /// Confirmations already given are kept: somebody who stays on the list
  /// keeps their answer instead of being reset to "not confirmed".
  static Future<({bool success, String? error})> setScaleLevitas(
    String scaleId,
    List<ScaleLevita> levitas,
  ) async {
    return _updateScaleField(scaleId, 'a escala de levitas', (scale) {
      final previous = {for (final l in scale.levitas) l.userId: l.confirmed};
      final merged = levitas
          .map((l) => l.copyWith(confirmed: previous[l.userId] ?? l.confirmed))
          .map((l) => l.toMap())
          .toList();
      return {'levitas': merged};
    });
  }

  /// Changes the service's own fields (date, type, notes), inside a
  /// transaction, without touching the song or levita lists.
  static Future<({bool success, String? error})> updateScaleDetails(
    String scaleId, {
    DateTime? date,
    String? serviceType,
    String? observations,
  }) async {
    return _updateScaleField(scaleId, 'os dados do culto', (_) {
      final data = <String, dynamic>{};
      if (date != null) data['date'] = Timestamp.fromDate(date);
      if (serviceType != null) data['serviceType'] = serviceType;
      if (observations != null) data['observations'] = observations;
      return data.isEmpty ? null : data;
    });
  }

  /// Shared shape of every change above: read the service inside the
  /// transaction, work out the fields to write from what is actually stored,
  /// and write only those.
  ///
  /// [build] returning null means "nothing to do".
  static Future<({bool success, String? error})> _updateScaleField(
    String scaleId,
    String acao,
    Map<String, dynamic>? Function(ScaleModel current) build,
  ) async {
    final ref = _db.collection(_scales).doc(scaleId);
    try {
      await _db.runTransaction((tx) async {
        final snap = await tx.get(ref);
        if (!snap.exists) {
          throw FirebaseException(
            plugin: 'levitasync',
            code: 'not-found',
            message: 'culto não encontrado',
          );
        }
        final data = build(ScaleModel.fromFirestore(snap.data()!));
        if (data == null || data.isEmpty) return;
        tx.update(ref, data);
      });
      return (success: true, error: null);
    } on FirebaseException catch (e) {
      return (success: false, error: _describe(e, acao));
    }
  }

  static ScaleModel createScaleModel({
    required DateTime date,
    String serviceType = 'Culto',
    String? createdBy,
  }) {
    return ScaleModel(
      id: CryptoUtils.generateId(),
      date: date,
      serviceType: serviceType,
      createdBy: createdBy,
      createdAt: DateTime.now(),
    );
  }

  // ─── CHAT ─────────────────────────────────────────────────────────────────

  static Stream<List<MessageModel>> watchMessages({int limit = 50}) {
    return _db
        .collection(_messages)
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => MessageModel.fromFirestore(doc.data()))
            .toList()
            .reversed
            .toList());
  }

  static Future<({bool success, String? error})> sendMessage(
      MessageModel message) async {
    try {
      await _db
          .collection(_messages)
          .doc(message.id)
          .set(message.toFirestore());
      return (success: true, error: null);
    } on FirebaseException catch (e) {
      return (success: false, error: _describe(e, 'enviar a mensagem'));
    } catch (e) {
      return (success: false, error: 'Não foi possível enviar: $e');
    }
  }

  static MessageModel createMessage({
    required String userId,
    required String userName,
    required String text,
    String? linkedSongId,
    String? linkedSongName,
  }) {
    return MessageModel(
      id: CryptoUtils.generateId(),
      userId: userId,
      userName: userName,
      text: text,
      type: linkedSongId != null ? MessageType.song : MessageType.text,
      linkedSongId: linkedSongId,
      linkedSongName: linkedSongName,
      timestamp: DateTime.now(),
    );
  }

  // ─── TYPING (presence) ──────────────────────────────────────────────────────

  static const String _typing = 'typing';

  /// Broadcasts whether [userId] is currently typing in the group chat.
  static Future<void> setTyping({
    required String userId,
    required String userName,
    required bool typing,
  }) async {
    try {
      await _db.collection(_typing).doc(userId).set({
        'userId': userId,
        'userName': userName,
        'typing': typing,
        'updatedAt': Timestamp.now(),
      });
    } catch (_) {
      // Presence is best-effort; ignore failures.
    }
  }

  static Stream<List<({String userId, String userName, DateTime updatedAt})>>
      watchTyping() {
    return _db
        .collection(_typing)
        .where('typing', isEqualTo: true)
        .snapshots()
        .map((snap) => snap.docs.map((doc) {
              final data = doc.data();
              return (
                userId: data['userId'] as String? ?? doc.id,
                userName: data['userName'] as String? ?? '',
                updatedAt:
                    (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
              );
            }).toList());
  }
}
