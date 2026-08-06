import 'package:cloud_firestore/cloud_firestore.dart';

enum UserRole { admin, levita }

enum UserInstrument { vocalist, guitar, bass, drums, keyboard, other }

extension UserRoleExtension on UserRole {
  String get label {
    switch (this) {
      case UserRole.admin:
        return 'Líder';
      case UserRole.levita:
        return 'Levita';
    }
  }

  String get value {
    return name;
  }

  static UserRole fromString(String value) {
    return UserRole.values.firstWhere(
      (e) => e.name == value,
      orElse: () => UserRole.levita,
    );
  }
}

extension UserInstrumentExtension on UserInstrument {
  String get label {
    switch (this) {
      case UserInstrument.vocalist:
        return 'Cantor(a)';
      case UserInstrument.guitar:
        return 'Violão/Guitarra';
      case UserInstrument.bass:
        return 'Baixo';
      case UserInstrument.drums:
        return 'Bateria';
      case UserInstrument.keyboard:
        return 'Teclado';
      case UserInstrument.other:
        return 'Outro';
    }
  }

  String get emoji {
    switch (this) {
      case UserInstrument.vocalist:
        return '🎤';
      case UserInstrument.guitar:
        return '🎸';
      case UserInstrument.bass:
        return '🎸';
      case UserInstrument.drums:
        return '🥁';
      case UserInstrument.keyboard:
        return '🎹';
      case UserInstrument.other:
        return '🎵';
    }
  }

  static UserInstrument fromString(String value) {
    return UserInstrument.values.firstWhere(
      (e) => e.name == value,
      orElse: () => UserInstrument.other,
    );
  }
}

class UserModel {
  final String id;
  final String name;
  final String passwordHash;
  final UserRole role;
  final UserInstrument instrument;
  final String? photoUrl;
  final List<String> favoriteSongs;
  final Map<String, int> savedTones; // songId -> semitones offset
  final DateTime createdAt;

  const UserModel({
    required this.id,
    required this.name,
    this.passwordHash = '',
    this.role = UserRole.levita,
    this.instrument = UserInstrument.other,
    this.photoUrl,
    this.favoriteSongs = const [],
    this.savedTones = const {},
    required this.createdAt,
  });

  bool get isAdmin => role == UserRole.admin;

  UserModel copyWith({
    String? id,
    String? name,
    String? passwordHash,
    UserRole? role,
    UserInstrument? instrument,
    String? photoUrl,
    List<String>? favoriteSongs,
    Map<String, int>? savedTones,
    DateTime? createdAt,
  }) {
    return UserModel(
      id: id ?? this.id,
      name: name ?? this.name,
      passwordHash: passwordHash ?? this.passwordHash,
      role: role ?? this.role,
      instrument: instrument ?? this.instrument,
      photoUrl: photoUrl ?? this.photoUrl,
      favoriteSongs: favoriteSongs ?? this.favoriteSongs,
      savedTones: savedTones ?? this.savedTones,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  /// Normalized name used for case-insensitive lookups ("Márcio" == "márcio").
  static String normalizeName(String name) => name.trim().toLowerCase();

  String get nameLower => normalizeName(name);

  Map<String, dynamic> toFirestore() {
    return {
      'id': id,
      'name': name.trim(),
      'nameLower': nameLower,
      'passwordHash': passwordHash,
      'role': role.name,
      'instrument': instrument.name,
      'photoUrl': photoUrl,
      'favoriteSongs': favoriteSongs,
      'savedTones': savedTones,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  factory UserModel.fromFirestore(Map<String, dynamic> data) {
    return UserModel(
      id: data['id'] as String,
      name: data['name'] as String,
      passwordHash: data['passwordHash'] as String? ?? '',
      role: UserRoleExtension.fromString(data['role'] as String? ?? 'levita'),
      instrument: UserInstrumentExtension.fromString(data['instrument'] as String? ?? 'other'),
      photoUrl: data['photoUrl'] as String?,
      favoriteSongs: List<String>.from(data['favoriteSongs'] ?? []),
      savedTones: Map<String, int>.from(data['savedTones'] ?? {}),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  /// Plain-JSON form used for the local session.
  ///
  /// Deliberately excludes [passwordHash] — the device never needs it — and
  /// stores the date as an ISO string, since Firestore's `Timestamp` is not
  /// JSON-encodable (encoding it throws and used to break login entirely).
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'role': role.name,
      'instrument': instrument.name,
      'photoUrl': photoUrl,
      'favoriteSongs': favoriteSongs,
      'savedTones': savedTones,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory UserModel.fromJson(Map<String, dynamic> data) {
    return UserModel(
      id: data['id'] as String,
      name: data['name'] as String,
      role: UserRoleExtension.fromString(data['role'] as String? ?? 'levita'),
      instrument:
          UserInstrumentExtension.fromString(data['instrument'] as String? ?? 'other'),
      photoUrl: data['photoUrl'] as String?,
      favoriteSongs: List<String>.from(data['favoriteSongs'] ?? const []),
      savedTones: Map<String, int>.from(data['savedTones'] ?? const {}),
      createdAt:
          DateTime.tryParse(data['createdAt'] as String? ?? '') ?? DateTime.now(),
    );
  }
}
