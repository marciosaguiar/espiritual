import 'package:cloud_firestore/cloud_firestore.dart';

class ScaleSong {
  final String songId;
  final String songName;
  final String artist;
  final String key;

  const ScaleSong({
    required this.songId,
    required this.songName,
    required this.artist,
    required this.key,
  });

  Map<String, dynamic> toMap() {
    return {
      'songId': songId,
      'songName': songName,
      'artist': artist,
      'key': key,
    };
  }

  factory ScaleSong.fromMap(Map<String, dynamic> data) {
    return ScaleSong(
      songId: data['songId'] as String,
      songName: data['songName'] as String,
      artist: data['artist'] as String? ?? '',
      key: data['key'] as String? ?? 'C',
    );
  }
}

class ScaleLevita {
  final String userId;
  final String userName;
  final String instrument;
  final bool confirmed;

  const ScaleLevita({
    required this.userId,
    required this.userName,
    required this.instrument,
    this.confirmed = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'userName': userName,
      'instrument': instrument,
      'confirmed': confirmed,
    };
  }

  factory ScaleLevita.fromMap(Map<String, dynamic> data) {
    return ScaleLevita(
      userId: data['userId'] as String,
      userName: data['userName'] as String,
      instrument: data['instrument'] as String? ?? 'other',
      confirmed: data['confirmed'] as bool? ?? false,
    );
  }

  ScaleLevita copyWith({bool? confirmed}) {
    return ScaleLevita(
      userId: userId,
      userName: userName,
      instrument: instrument,
      confirmed: confirmed ?? this.confirmed,
    );
  }
}

class ScaleModel {
  final String id;
  final DateTime date;
  final String serviceType; // 'Culto', 'Ensaio', 'Especial'
  final List<ScaleSong> songs;
  final List<ScaleLevita> levitas;
  final String observations;
  final String? createdBy;
  final DateTime createdAt;

  const ScaleModel({
    required this.id,
    required this.date,
    this.serviceType = 'Culto',
    this.songs = const [],
    this.levitas = const [],
    this.observations = '',
    this.createdBy,
    required this.createdAt,
  });

  bool get hasUserConfirmed(String userId) {
    return levitas.any((l) => l.userId == userId && l.confirmed);
  }

  bool get isUserInScale(String userId) {
    return levitas.any((l) => l.userId == userId);
  }

  int get confirmedCount => levitas.where((l) => l.confirmed).length;

  ScaleModel copyWith({
    String? id,
    DateTime? date,
    String? serviceType,
    List<ScaleSong>? songs,
    List<ScaleLevita>? levitas,
    String? observations,
    String? createdBy,
    DateTime? createdAt,
  }) {
    return ScaleModel(
      id: id ?? this.id,
      date: date ?? this.date,
      serviceType: serviceType ?? this.serviceType,
      songs: songs ?? this.songs,
      levitas: levitas ?? this.levitas,
      observations: observations ?? this.observations,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'id': id,
      'date': Timestamp.fromDate(date),
      'serviceType': serviceType,
      'songs': songs.map((s) => s.toMap()).toList(),
      'levitas': levitas.map((l) => l.toMap()).toList(),
      'observations': observations,
      'createdBy': createdBy,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  factory ScaleModel.fromFirestore(Map<String, dynamic> data) {
    return ScaleModel(
      id: data['id'] as String,
      date: (data['date'] as Timestamp).toDate(),
      serviceType: data['serviceType'] as String? ?? 'Culto',
      songs: (data['songs'] as List<dynamic>? ?? [])
          .map((s) => ScaleSong.fromMap(Map<String, dynamic>.from(s)))
          .toList(),
      levitas: (data['levitas'] as List<dynamic>? ?? [])
          .map((l) => ScaleLevita.fromMap(Map<String, dynamic>.from(l)))
          .toList(),
      observations: data['observations'] as String? ?? '',
      createdBy: data['createdBy'] as String?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}
