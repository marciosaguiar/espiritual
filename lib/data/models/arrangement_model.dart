import 'package:cloud_firestore/cloud_firestore.dart';

/// How this church plays a song: the middle layer between the work itself and
/// each musician's own preference.
///
/// Lives in `songs/{songId}/arrangements/{arrangementId}`. A song can have
/// more than one — an acoustic version and a full-band version, or the key the
/// church moved to after the original singer left. Before this existed, the
/// only place to put the church's key was a copy inside each service, so the
/// knowledge never accumulated.
///
/// Being a subcollection also keeps the chart out of the song document, so
/// opening the song list no longer downloads every chart in the repertoire.
class ArrangementModel {
  final String id;
  final String songId;

  /// A name for this version: "Padrão", "Acústico", "Tom da Ana".
  final String name;

  /// The key the church actually plays in.
  final String churchKey;

  /// Chord chart, chords inline with the words.
  final String chords;

  /// Running order: intro, verse, chorus, bridge…
  final List<String> structure;

  /// Beats per minute. 0 means nobody set it.
  final int bpm;

  /// Notes for the whole band (not personal — those are in songPrefs).
  final String notes;

  final String? approvedBy;
  final DateTime updatedAt;

  const ArrangementModel({
    required this.id,
    required this.songId,
    this.name = 'Padrão',
    required this.churchKey,
    this.chords = '',
    this.structure = const [],
    this.bpm = 0,
    this.notes = '',
    this.approvedBy,
    required this.updatedAt,
  });

  bool get hasChords => chords.trim().isNotEmpty;

  ArrangementModel copyWith({
    String? name,
    String? churchKey,
    String? chords,
    List<String>? structure,
    int? bpm,
    String? notes,
    String? approvedBy,
    DateTime? updatedAt,
  }) {
    return ArrangementModel(
      id: id,
      songId: songId,
      name: name ?? this.name,
      churchKey: churchKey ?? this.churchKey,
      chords: chords ?? this.chords,
      structure: structure ?? this.structure,
      bpm: bpm ?? this.bpm,
      notes: notes ?? this.notes,
      approvedBy: approvedBy ?? this.approvedBy,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'id': id,
      'songId': songId,
      'name': name,
      'churchKey': churchKey,
      'chords': chords,
      'structure': structure,
      'bpm': bpm,
      'notes': notes,
      'approvedBy': approvedBy,
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  factory ArrangementModel.fromFirestore(Map<String, dynamic> data) {
    return ArrangementModel(
      id: data['id'] as String,
      songId: data['songId'] as String? ?? '',
      name: data['name'] as String? ?? 'Padrão',
      churchKey: data['churchKey'] as String? ?? 'C',
      chords: data['chords'] as String? ?? '',
      structure: List<String>.from(data['structure'] ?? const []),
      bpm: (data['bpm'] as num?)?.toInt() ?? 0,
      notes: data['notes'] as String? ?? '',
      approvedBy: data['approvedBy'] as String?,
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      ...toFirestore(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory ArrangementModel.fromJson(Map<String, dynamic> data) {
    return ArrangementModel(
      id: data['id'] as String,
      songId: data['songId'] as String? ?? '',
      name: data['name'] as String? ?? 'Padrão',
      churchKey: data['churchKey'] as String? ?? 'C',
      chords: data['chords'] as String? ?? '',
      structure: List<String>.from(data['structure'] ?? const []),
      bpm: (data['bpm'] as num?)?.toInt() ?? 0,
      notes: data['notes'] as String? ?? '',
      approvedBy: data['approvedBy'] as String?,
      updatedAt:
          DateTime.tryParse(data['updatedAt'] as String? ?? '') ?? DateTime.now(),
    );
  }
}

/// One musician's own settings for one song.
///
/// Lives in `users/{userId}/songPrefs/{songId}` — private, so not even the
/// leader reads someone else's notes. It replaces the `savedTones` map that
/// used to sit inside the user document, which held only a transpose amount,
/// had nowhere for notes, and grew without limit inside a document that is
/// read on every sign-in.
class SongPrefModel {
  final String songId;

  /// Transpose, in semitones, from the key being shown. 0 = as written.
  final int semitones;

  /// Personal notes: "entro na segunda voz", "capotraste na 2ª casa".
  final String notes;

  /// Capo position for guitar players. 0 = none.
  final int capo;

  final DateTime updatedAt;

  const SongPrefModel({
    required this.songId,
    this.semitones = 0,
    this.notes = '',
    this.capo = 0,
    required this.updatedAt,
  });

  bool get isEmpty => semitones == 0 && notes.trim().isEmpty && capo == 0;

  SongPrefModel copyWith({int? semitones, String? notes, int? capo}) {
    return SongPrefModel(
      songId: songId,
      semitones: semitones ?? this.semitones,
      notes: notes ?? this.notes,
      capo: capo ?? this.capo,
      updatedAt: DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'songId': songId,
      'semitones': semitones,
      'notes': notes,
      'capo': capo,
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  factory SongPrefModel.fromFirestore(Map<String, dynamic> data) {
    return SongPrefModel(
      songId: data['songId'] as String? ?? '',
      semitones: (data['semitones'] as num?)?.toInt() ?? 0,
      notes: data['notes'] as String? ?? '',
      capo: (data['capo'] as num?)?.toInt() ?? 0,
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}
