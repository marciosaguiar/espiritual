import 'package:cloud_firestore/cloud_firestore.dart';

class SongModel {
  final String id;
  final String name;
  final String artist;
  final String lyrics; // plain lyrics without chords
  final String chords; // chord chart with chords inline
  final String originalKey;
  final String? youtubeUrl;
  final bool isOfflineAvailable;
  final DateTime createdAt;
  final String? addedBy; // userId of who added

  const SongModel({
    required this.id,
    required this.name,
    required this.artist,
    required this.lyrics,
    required this.chords,
    required this.originalKey,
    this.youtubeUrl,
    this.isOfflineAvailable = false,
    required this.createdAt,
    this.addedBy,
  });

  SongModel copyWith({
    String? id,
    String? name,
    String? artist,
    String? lyrics,
    String? chords,
    String? originalKey,
    String? youtubeUrl,
    bool? isOfflineAvailable,
    DateTime? createdAt,
    String? addedBy,
  }) {
    return SongModel(
      id: id ?? this.id,
      name: name ?? this.name,
      artist: artist ?? this.artist,
      lyrics: lyrics ?? this.lyrics,
      chords: chords ?? this.chords,
      originalKey: originalKey ?? this.originalKey,
      youtubeUrl: youtubeUrl ?? this.youtubeUrl,
      isOfflineAvailable: isOfflineAvailable ?? this.isOfflineAvailable,
      createdAt: createdAt ?? this.createdAt,
      addedBy: addedBy ?? this.addedBy,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'id': id,
      'name': name,
      'artist': artist,
      'lyrics': lyrics,
      'chords': chords,
      'originalKey': originalKey,
      'youtubeUrl': youtubeUrl,
      'isOfflineAvailable': isOfflineAvailable,
      'createdAt': Timestamp.fromDate(createdAt),
      'addedBy': addedBy,
    };
  }

  factory SongModel.fromFirestore(Map<String, dynamic> data) {
    return SongModel(
      id: data['id'] as String,
      name: data['name'] as String,
      artist: data['artist'] as String? ?? '',
      lyrics: data['lyrics'] as String? ?? '',
      chords: data['chords'] as String? ?? '',
      originalKey: data['originalKey'] as String? ?? 'C',
      youtubeUrl: data['youtubeUrl'] as String?,
      isOfflineAvailable: data['isOfflineAvailable'] as bool? ?? false,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      addedBy: data['addedBy'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'artist': artist,
      'lyrics': lyrics,
      'chords': chords,
      'originalKey': originalKey,
      'youtubeUrl': youtubeUrl,
      'isOfflineAvailable': isOfflineAvailable,
      'createdAt': createdAt.toIso8601String(),
      'addedBy': addedBy,
    };
  }

  factory SongModel.fromJson(Map<String, dynamic> data) {
    return SongModel(
      id: data['id'] as String,
      name: data['name'] as String,
      artist: data['artist'] as String? ?? '',
      lyrics: data['lyrics'] as String? ?? '',
      chords: data['chords'] as String? ?? '',
      originalKey: data['originalKey'] as String? ?? 'C',
      youtubeUrl: data['youtubeUrl'] as String?,
      isOfflineAvailable: data['isOfflineAvailable'] as bool? ?? false,
      createdAt: DateTime.parse(data['createdAt'] as String),
      addedBy: data['addedBy'] as String?,
    );
  }
}
