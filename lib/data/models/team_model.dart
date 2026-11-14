import 'package:cloud_firestore/cloud_firestore.dart';

/// One musician in a team: who, and on what instrument.
///
/// Only the id is stored. The name is looked up from `users` when drawing,
/// the same rule the repertoire follows — a copied name goes stale the day
/// somebody corrects their own.
class TeamMember {
  final String userId;

  /// Instrument for this team, which may differ from the person's usual one
  /// (the same person can sing in one team and play bass in another).
  final String instrument;

  const TeamMember({required this.userId, this.instrument = 'other'});

  Map<String, dynamic> toMap() => {'userId': userId, 'instrument': instrument};

  factory TeamMember.fromMap(Map<String, dynamic> data) => TeamMember(
        userId: data['userId'] as String,
        instrument: data['instrument'] as String? ?? 'other',
      );

  TeamMember copyWith({String? instrument}) =>
      TeamMember(userId: userId, instrument: instrument ?? this.instrument);
}

/// A standing team: "Equipe Manhã", "Equipe Noite".
///
/// Lives in `teams/{teamId}`. The ministry's services repeat every week with
/// roughly the same people, so the team is the unit that gets scheduled — not
/// a list rebuilt by hand for each service.
class TeamModel {
  final String id;
  final String name;
  final List<TeamMember> members;
  final String? createdBy;
  final DateTime updatedAt;

  const TeamModel({
    required this.id,
    required this.name,
    this.members = const [],
    this.createdBy,
    required this.updatedAt,
  });

  bool get isEmpty => members.isEmpty;

  bool hasMember(String userId) => members.any((m) => m.userId == userId);

  TeamModel copyWith({String? name, List<TeamMember>? members}) {
    return TeamModel(
      id: id,
      name: name ?? this.name,
      members: members ?? this.members,
      createdBy: createdBy,
      updatedAt: DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'id': id,
      'name': name,
      'members': members.map((m) => m.toMap()).toList(),
      'createdBy': createdBy,
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  factory TeamModel.fromFirestore(Map<String, dynamic> data) {
    return TeamModel(
      id: data['id'] as String,
      name: data['name'] as String? ?? 'Equipe',
      members: (data['members'] as List<dynamic>? ?? const [])
          .map((m) => TeamMember.fromMap(Map<String, dynamic>.from(m as Map)))
          .toList(),
      createdBy: data['createdBy'] as String?,
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}

/// One line of the standing schedule: a service that happens every week.
///
/// `weekday` follows Dart's [DateTime.weekday]: 1 = Monday … 7 = Sunday.
class ScheduleSlot {
  /// Stable id of the line, e.g. `dom-0800`. Also what a generated service
  /// records in `fromSlot`, so changing a team later can find its services.
  final String id;

  final int weekday;
  final int hour;
  final int minute;

  /// "Culto", "Ensaio" — what the service is called.
  final String name;

  /// Team scheduled by default. Empty means "nobody yet".
  final String teamId;

  const ScheduleSlot({
    required this.id,
    required this.weekday,
    required this.hour,
    required this.minute,
    this.name = 'Culto',
    this.teamId = '',
  });

  /// `08:00`, for showing and for building the service id.
  String get horaFormatada =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  String get diaDaSemana => const {
        1: 'Segunda',
        2: 'Terça',
        3: 'Quarta',
        4: 'Quinta',
        5: 'Sexta',
        6: 'Sábado',
        7: 'Domingo',
      }[weekday] ??
      '—';

  /// The next date on or after [from] that falls on this slot's weekday, at
  /// this slot's time.
  DateTime proximaData(DateTime from) {
    final diff = (weekday - from.weekday + 7) % 7;
    final dia = DateTime(from.year, from.month, from.day).add(
      Duration(days: diff),
    );
    return DateTime(dia.year, dia.month, dia.day, hour, minute);
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'weekday': weekday,
        'hour': hour,
        'minute': minute,
        'name': name,
        'teamId': teamId,
      };

  factory ScheduleSlot.fromMap(Map<String, dynamic> data) => ScheduleSlot(
        id: data['id'] as String,
        weekday: (data['weekday'] as num).toInt(),
        hour: (data['hour'] as num?)?.toInt() ?? 0,
        minute: (data['minute'] as num?)?.toInt() ?? 0,
        name: data['name'] as String? ?? 'Culto',
        teamId: data['teamId'] as String? ?? '',
      );

  ScheduleSlot copyWith({
    int? weekday,
    int? hour,
    int? minute,
    String? name,
    String? teamId,
  }) {
    return ScheduleSlot(
      id: id,
      weekday: weekday ?? this.weekday,
      hour: hour ?? this.hour,
      minute: minute ?? this.minute,
      name: name ?? this.name,
      teamId: teamId ?? this.teamId,
    );
  }
}

/// The ministry's standing schedule, as one document: `config/agendaFixa`.
///
/// A document rather than a collection because the five lines are read and
/// edited together — as a collection each app start would pay five reads for
/// no gain.
class FixedSchedule {
  final List<ScheduleSlot> slots;
  final DateTime updatedAt;

  const FixedSchedule({this.slots = const [], required this.updatedAt});

  /// What this church actually does, used the first time the screen opens.
  /// Quarta 8h e 19h30, sexta 19h30, domingo 8h e 19h.
  static List<ScheduleSlot> padraoDaIgreja({
    String equipeManha = '',
    String equipeNoite = '',
  }) {
    return [
      ScheduleSlot(
          id: 'qua-0800', weekday: 3, hour: 8, minute: 0, teamId: equipeManha),
      ScheduleSlot(
          id: 'qua-1930', weekday: 3, hour: 19, minute: 30, teamId: equipeNoite),
      ScheduleSlot(
          id: 'sex-1930', weekday: 5, hour: 19, minute: 30, teamId: equipeNoite),
      ScheduleSlot(
          id: 'dom-0800', weekday: 7, hour: 8, minute: 0, teamId: equipeManha),
      ScheduleSlot(
          id: 'dom-1900', weekday: 7, hour: 19, minute: 0, teamId: equipeNoite),
    ];
  }

  Map<String, dynamic> toFirestore() => {
        'slots': slots.map((s) => s.toMap()).toList(),
        'updatedAt': Timestamp.fromDate(updatedAt),
      };

  factory FixedSchedule.fromFirestore(Map<String, dynamic> data) {
    return FixedSchedule(
      slots: (data['slots'] as List<dynamic>? ?? const [])
          .map((s) => ScheduleSlot.fromMap(Map<String, dynamic>.from(s as Map)))
          .toList(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}
