import 'package:cloud_firestore/cloud_firestore.dart';

/// A song in a service, stored as a *reference*.
///
/// It used to copy the name, the artist and the key into the service document.
/// That froze them: renaming a song left every service already built showing
/// the old name, with no way to tell why. Now only ids are stored and the
/// screens look the current values up.
class ScaleSong {
  final String songId;

  /// Which arrangement to play. Empty means "whatever is the default".
  final String arrangementId;

  /// Key just for this service, when it differs from the arrangement's.
  /// Empty means "use the arrangement's key".
  final String keyOverride;

  const ScaleSong({
    required this.songId,
    this.arrangementId = '',
    this.keyOverride = '',
  });

  Map<String, dynamic> toMap() {
    return {
      'songId': songId,
      'arrangementId': arrangementId,
      'keyOverride': keyOverride,
    };
  }

  factory ScaleSong.fromMap(Map<String, dynamic> data) {
    return ScaleSong(
      songId: data['songId'] as String,
      arrangementId: data['arrangementId'] as String? ?? '',
      // Services written before this change carried `key` with a copied value.
      keyOverride:
          data['keyOverride'] as String? ?? data['key'] as String? ?? '',
    );
  }

  ScaleSong copyWith({String? arrangementId, String? keyOverride}) {
    return ScaleSong(
      songId: songId,
      arrangementId: arrangementId ?? this.arrangementId,
      keyOverride: keyOverride ?? this.keyOverride,
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

  /// O nome para mostrar, resolvido POR ID.
  ///
  /// `userName` é cópia, e o gerador da agenda fixa grava vazio: ele monta o
  /// culto a partir da equipe, que guarda só ids. Além disso nome copiado
  /// dentro do culto fica errado quando a pessoa corrige o próprio nome — a
  /// mesma razão por que a escala guarda referência de música, nunca cópia.
  /// Então o cadastro manda, e a cópia é a reserva.
  String nomeCom(Map<String, String> nomes) {
    final doCadastro = (nomes[userId] ?? '').trim();
    if (doCadastro.isNotEmpty) return doCadastro;
    final copia = userName.trim();
    if (copia.isNotEmpty) return copia;
    // Nem cadastro nem cópia: alguém que saiu e cujo documento ficou. Dizer
    // "Alguém" mostra que há um lugar ocupado ali, em vez de uma linha em
    // branco que o líder leria como "não tem ninguém".
    return 'Alguém';
  }

  /// A letra do avatar.
  ///
  /// NUNCA indexa texto vazio. A tela fazia `userName[0]`, e `''[0]` LANÇA —
  /// então todo culto criado pela agenda fixa com equipe padrão derrubava a
  /// tela do culto inteira, no meio da lista de escalados. O gerador grava
  /// `userName` vazio de propósito.
  String inicialCom(Map<String, String> nomes) {
    final n = nomeCom(nomes);
    return n.isEmpty ? '?' : n[0].toUpperCase();
  }

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

/// Quem ENTROU na escala, comparando a lista antiga com a nova.
///
/// É o que decide quem recebe "você foi escalado". Avisar quem já estava é o
/// pior tipo de notificação: a que não traz novidade e ensina a pessoa a
/// ignorar as próximas.
///
/// Função solta, e não método, porque ela compara DUAS listas — a de antes e
/// a de depois — e nenhuma das duas é "o objeto".
List<String> quemEntrouNaEscala(
  List<ScaleLevita> antes,
  List<ScaleLevita> depois,
) {
  final jaEstavam = antes.map((l) => l.userId).toSet();
  final vistos = <String>{};
  final novos = <String>[];
  for (final l in depois) {
    if (l.userId.isEmpty) continue;
    if (jaEstavam.contains(l.userId)) continue;
    // A mesma pessoa duas vezes na lista nova não vira dois avisos.
    if (!vistos.add(l.userId)) continue;
    novos.add(l.userId);
  }
  return novos;
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

  /// Which line of the standing schedule produced this service. Empty for a
  /// one-off created with the "+" button.
  final String fromSlot;

  /// Team scheduled when it was generated. Lets "apply to the next services"
  /// find what to update after the team changes.
  final String teamId;

  /// True once a leader changed THIS service by hand. Reapplying a team skips
  /// these, so a deliberate change is never undone by a later bulk update.
  final bool manuallyEdited;

  /// Cancelled services are kept, never deleted: the id comes from the date
  /// and time, so a deleted one would simply be created again on the next
  /// app start.
  final bool canceled;

  /// Nomes de quem saiu do ministério e estava escalado aqui.
  ///
  /// Tirar a pessoa da lista sem dizer nada deixaria um culto com um
  /// instrumento a menos e ninguém sabendo — o líder só descobriria no
  /// domingo. A lista some quando ele mexe na escalação, que é o gesto de
  /// "já vi e resolvi".
  final List<String> faltando;

  const ScaleModel({
    required this.id,
    required this.date,
    this.serviceType = 'Culto',
    this.songs = const [],
    this.levitas = const [],
    this.observations = '',
    this.createdBy,
    required this.createdAt,
    this.fromSlot = '',
    this.teamId = '',
    this.manuallyEdited = false,
    this.canceled = false,
    this.faltando = const [],
  });

  /// Generated by the standing schedule rather than created by hand.
  bool get daAgendaFixa => fromSlot.isNotEmpty;

  /// Id built from the date and time: `2026-11-15_0800`.
  ///
  /// Two leaders opening the app at the same moment compute the same id, so
  /// the write lands on the same document and the service is never doubled.
  static String idPara(DateTime quando) {
    String d(int v, [int casas = 2]) => v.toString().padLeft(casas, '0');
    return '${d(quando.year, 4)}-${d(quando.month)}-${d(quando.day)}'
        '_${d(quando.hour)}${d(quando.minute)}';
  }

  bool hasUserConfirmed(String userId) {
    return levitas.any((l) => l.userId == userId && l.confirmed);
  }

  bool isUserInScale(String userId) {
    return levitas.any((l) => l.userId == userId);
  }

  int get confirmedCount => levitas.where((l) => l.confirmed).length;

  /// Quem ainda não confirmou, na ordem em que está escalado.
  ///
  /// É a pergunta que o líder faz no sábado à noite, e a que ele respondia
  /// abrindo o culto e contando os nomes verdes na mão.
  List<ScaleLevita> get naoConfirmados =>
      levitas.where((l) => !l.confirmed).toList();

  /// "3 de 7 confirmaram", ou o que fizer sentido quando não são 3 de 7.
  ///
  /// Os casos de borda estão aqui, e não na tela, porque são eles que fazem a
  /// frase soar como gente: "ninguém confirmou ainda" é mais claro que "0 de
  /// 7 confirmaram", e "todos confirmaram" é a notícia que o líder quer ler
  /// de longe. Com uma pessoa só, "1 de 1 confirmaram" estaria errado no
  /// português e na conta.
  String get textoDaConfirmacao {
    final total = levitas.length;
    if (total == 0) return 'Ninguém escalado';
    final ok = confirmedCount;
    if (ok == total) return total == 1 ? 'Confirmado' : 'Todos confirmaram';
    if (ok == 0) return 'Ninguém confirmou ainda';
    return '$ok de $total confirmaram';
  }

  /// Já está tudo confirmado? Serve para a tela escolher a cor.
  bool get todosConfirmaram =>
      levitas.isNotEmpty && confirmedCount == levitas.length;

  /// "Falta confirmar: Ana, Bruno e mais 2" — ou vazio quando não falta
  /// ninguém.
  ///
  /// Corta em [limite] nomes de propósito: a lista inteira numa escala de 12
  /// pessoas viraria um parágrafo no cartão do Início, e quem lê quer a
  /// primeira informação ("ainda falta gente") sem rolar a tela.
  String faltamConfirmar(Map<String, String> nomes, {int limite = 3}) {
    final faltam = naoConfirmados;
    if (faltam.isEmpty) return '';
    final nomesDeles = faltam.map((l) => l.nomeCom(nomes)).toList();
    if (nomesDeles.length <= limite) {
      if (nomesDeles.length == 1) return 'Falta confirmar: ${nomesDeles.first}';
      final ultimo = nomesDeles.removeLast();
      return 'Falta confirmar: ${nomesDeles.join(', ')} e $ultimo';
    }
    final mostrados = nomesDeles.take(limite).join(', ');
    final resto = nomesDeles.length - limite;
    return 'Falta confirmar: $mostrados e mais $resto';
  }

  ScaleModel copyWith({
    String? id,
    DateTime? date,
    String? serviceType,
    List<ScaleSong>? songs,
    List<ScaleLevita>? levitas,
    String? observations,
    String? createdBy,
    DateTime? createdAt,
    String? fromSlot,
    String? teamId,
    bool? manuallyEdited,
    bool? canceled,
    List<String>? faltando,
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
      fromSlot: fromSlot ?? this.fromSlot,
      teamId: teamId ?? this.teamId,
      manuallyEdited: manuallyEdited ?? this.manuallyEdited,
      canceled: canceled ?? this.canceled,
      faltando: faltando ?? this.faltando,
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
      'fromSlot': fromSlot,
      'teamId': teamId,
      'manuallyEdited': manuallyEdited,
      'canceled': canceled,
      'faltando': faltando,
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
      fromSlot: data['fromSlot'] as String? ?? '',
      teamId: data['teamId'] as String? ?? '',
      manuallyEdited: data['manuallyEdited'] as bool? ?? false,
      canceled: data['canceled'] as bool? ?? false,
      faltando: (data['faltando'] as List?)?.cast<String>() ?? const [],
    );
  }
}
