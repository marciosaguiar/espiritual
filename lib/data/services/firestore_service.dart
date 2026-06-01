import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/song_model.dart';
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

  static Future<bool> addSong(SongModel song) async {
    try {
      await _db.collection(_songs).doc(song.id).set(song.toFirestore());
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> updateSong(SongModel song) async {
    try {
      await _db.collection(_songs).doc(song.id).update(song.toFirestore());
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> deleteSong(String songId) async {
    try {
      await _db.collection(_songs).doc(songId).delete();
      return true;
    } catch (_) {
      return false;
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
    required String chords,
    required String originalKey,
    String? youtubeUrl,
    String? addedBy,
  }) {
    return SongModel(
      id: CryptoUtils.generateId(),
      name: name,
      artist: artist,
      lyrics: lyrics,
      chords: chords,
      originalKey: originalKey,
      youtubeUrl: youtubeUrl,
      addedBy: addedBy,
      createdAt: DateTime.now(),
    );
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

  static Future<bool> createScale(ScaleModel scale) async {
    try {
      await _db.collection(_scales).doc(scale.id).set(scale.toFirestore());
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> updateScale(ScaleModel scale) async {
    try {
      await _db.collection(_scales).doc(scale.id).update(scale.toFirestore());
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> deleteScale(String scaleId) async {
    try {
      await _db.collection(_scales).doc(scaleId).delete();
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> confirmPresence(
      String scaleId, String userId, bool confirmed) async {
    try {
      final scale = await _db.collection(_scales).doc(scaleId).get();
      if (!scale.exists) return false;

      final data = scale.data()!;
      final levitas = (data['levitas'] as List<dynamic>).map((l) {
        final levita = Map<String, dynamic>.from(l as Map);
        if (levita['userId'] == userId) {
          levita['confirmed'] = confirmed;
        }
        return levita;
      }).toList();

      await _db
          .collection(_scales)
          .doc(scaleId)
          .update({'levitas': levitas});
      return true;
    } catch (_) {
      return false;
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

  static Future<bool> sendMessage(MessageModel message) async {
    try {
      await _db
          .collection(_messages)
          .doc(message.id)
          .set(message.toFirestore());
      return true;
    } catch (_) {
      return false;
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
