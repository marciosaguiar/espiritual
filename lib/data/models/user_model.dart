import 'package:cloud_firestore/cloud_firestore.dart';

/// Quem é a pessoa dentro do ministério.
///
/// `pendente` é onde todo cadastro começa: o endereço do app é público, então
/// qualquer um com o link cria conta, e sem este degrau estaria dentro do chat
/// e da escala no mesmo instante. O líder aprova ou recusa em Perfil →
/// Membros. As regras do banco não liberam leitura nenhuma para pendente e
/// recusado, fora o próprio cadastro — é isso que faz a trava valer de
/// verdade, e não só sumir com os botões da tela.
enum UserRole { pendente, levita, admin, recusado }

enum UserInstrument { vocalist, guitar, bass, drums, keyboard, other }

/// Como a pessoa lê as músicas: quem canta vê só a letra, em fonte grande;
/// quem toca vê a cifra no tom dele.
enum ModoLeitura { canto, toco }

extension UserRoleExtension on UserRole {
  String get label {
    switch (this) {
      case UserRole.admin:
        return 'Líder';
      case UserRole.levita:
        return 'Levita';
      case UserRole.pendente:
        return 'Aguardando aprovação';
      case UserRole.recusado:
        return 'Não aprovado';
    }
  }

  String get value {
    return name;
  }

  /// Função desconhecida vira `pendente`, nunca `levita`.
  ///
  /// Um valor que não se reconhece — campo faltando, documento meio gravado,
  /// nome escrito errado no console — tem de significar MENOS acesso, não o
  /// acesso normal. Se o padrão fosse levita, bastaria um documento torto para
  /// alguém entrar sem passar pelo líder.
  static UserRole fromString(String value) {
    return UserRole.values.firstWhere(
      (e) => e.name == value,
      orElse: () => UserRole.pendente,
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
  /// Internal address used for Firebase Authentication, derived from [name].
  /// Never shown to the user, who signs in with the name alone.
  final String email;
  final UserRole role;
  final UserInstrument instrument;
  final String? photoUrl;
  final List<String> favoriteSongs;
  final DateTime createdAt;

  /// Escolhido no perfil. Nulo = nunca escolheu: vale o que o instrumento
  /// sugere (ver [modoLeitura]).
  final ModoLeitura? leitura;

  const UserModel({
    required this.id,
    required this.name,
    this.email = '',
    this.role = UserRole.levita,
    this.instrument = UserInstrument.other,
    this.photoUrl,
    this.favoriteSongs = const [],
    required this.createdAt,
    this.leitura,
  });

  bool get isAdmin => role == UserRole.admin;

  /// Já passou pelo líder. É o que abre o app inteiro, e a mesma conta que as
  /// regras do banco fazem — `levita` ou `admin`, nada mais.
  bool get aprovado => role == UserRole.levita || role == UserRole.admin;

  bool get isPendente => role == UserRole.pendente;
  bool get isRecusado => role == UserRole.recusado;

  /// Cantor(a) que nunca escolheu lê como quem canta; o resto, como quem toca.
  ModoLeitura get modoLeitura =>
      leitura ??
      (instrument == UserInstrument.vocalist ? ModoLeitura.canto : ModoLeitura.toco);

  bool get canta => modoLeitura == ModoLeitura.canto;

  static ModoLeitura? _leituraDe(Object? v) =>
      ModoLeitura.values.where((m) => m.name == v).firstOrNull;

  UserModel copyWith({
    String? id,
    String? name,
    String? email,
    UserRole? role,
    UserInstrument? instrument,
    String? photoUrl,
    List<String>? favoriteSongs,
    DateTime? createdAt,
    ModoLeitura? leitura,
  }) {
    return UserModel(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      role: role ?? this.role,
      instrument: instrument ?? this.instrument,
      photoUrl: photoUrl ?? this.photoUrl,
      favoriteSongs: favoriteSongs ?? this.favoriteSongs,
      createdAt: createdAt ?? this.createdAt,
      leitura: leitura ?? this.leitura,
    );
  }

  /// Normalized name used for case-insensitive lookups ("Márcio" == "márcio").
  static String normalizeName(String name) => name.trim().toLowerCase();

  String get nameLower => normalizeName(name);

  /// Domain of the internal addresses. Not a real mail domain: nothing is ever
  /// sent to it. It exists because Firebase Authentication identifies people by
  /// e-mail, while this ministry signs in with a name.
  static const String emailDomain = 'levitas.app';

  /// Builds the internal address for [name]: accents dropped, spaces turned
  /// into dots, everything else removed.
  ///
  ///     'Márcio Aguiar'  ->  'marcio.aguiar@levitas.app'
  ///     'João 2'         ->  'joao.2@levitas.app'
  ///
  /// Dropping accents is deliberate: whoever registers as "Márcio" must still
  /// get in after typing "Marcio", and an address with an accent is not valid
  /// for Firebase anyway.
  static String emailForName(String name) {
    const accented = 'áàâãäéèêëíìîïóòôõöúùûüçñ';
    const plain = 'aaaaaeeeeiiiiooooouuuucn';

    final buffer = StringBuffer();
    for (final rune in normalizeName(name).runes) {
      final char = String.fromCharCode(rune);
      final i = accented.indexOf(char);
      buffer.write(i >= 0 ? plain[i] : char);
    }

    var slug = buffer
        .toString()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '.')
        .replaceAll(RegExp(r'^\.+|\.+$'), '');

    // A name of nothing but symbols would leave an empty address.
    if (slug.isEmpty) slug = 'levita';
    // Keeps the local part inside the 64-character limit.
    if (slug.length > 48) slug = slug.substring(0, 48);

    return '$slug@$emailDomain';
  }

  String get derivedEmail => emailForName(name);

  Map<String, dynamic> toFirestore() {
    return {
      'id': id,
      'name': name.trim(),
      'nameLower': nameLower,
      'email': email,
      'role': role.name,
      'instrument': instrument.name,
      'photoUrl': photoUrl,
      'favoriteSongs': favoriteSongs,
      'createdAt': Timestamp.fromDate(createdAt),
      if (leitura != null) 'leitura': leitura!.name,
    };
  }

  factory UserModel.fromFirestore(Map<String, dynamic> data) {
    return UserModel(
      id: data['id'] as String,
      name: data['name'] as String,
      email: data['email'] as String? ?? '',
      // Campo ausente cai em pendente, não em levita: um cadastro sem
      // função não pode valer como cadastro aprovado.
      role: UserRoleExtension.fromString(data['role'] as String? ?? ''),
      instrument: UserInstrumentExtension.fromString(data['instrument'] as String? ?? 'other'),
      photoUrl: data['photoUrl'] as String?,
      favoriteSongs: List<String>.from(data['favoriteSongs'] ?? []),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      leitura: _leituraDe(data['leitura']),
    );
  }

  /// Plain-JSON form used for the local session.
  ///
  /// Stores the date as an ISO string, since Firestore's `Timestamp` is not
  /// JSON-encodable (encoding it throws and used to break login entirely).
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'role': role.name,
      'instrument': instrument.name,
      'photoUrl': photoUrl,
      'favoriteSongs': favoriteSongs,
      'createdAt': createdAt.toIso8601String(),
      if (leitura != null) 'leitura': leitura!.name,
    };
  }

  factory UserModel.fromJson(Map<String, dynamic> data) {
    return UserModel(
      id: data['id'] as String,
      name: data['name'] as String,
      // Campo ausente cai em pendente, não em levita: um cadastro sem
      // função não pode valer como cadastro aprovado.
      role: UserRoleExtension.fromString(data['role'] as String? ?? ''),
      instrument:
          UserInstrumentExtension.fromString(data['instrument'] as String? ?? 'other'),
      photoUrl: data['photoUrl'] as String?,
      favoriteSongs: List<String>.from(data['favoriteSongs'] ?? const []),
      createdAt:
          DateTime.tryParse(data['createdAt'] as String? ?? '') ?? DateTime.now(),
      leitura: _leituraDe(data['leitura']),
    );
  }
}
