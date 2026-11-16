import 'package:cloud_firestore/cloud_firestore.dart';

/// Quem é a pessoa dentro do ministério.
///
/// `pendente` é onde todo cadastro começa: o endereço do app é público, então
/// qualquer um com o link cria conta, e sem este degrau estaria dentro do chat
/// e da escala no mesmo instante. O líder aprova ou recusa em Perfil →
/// Membros. As regras do banco não liberam leitura nenhuma para pendente e
/// recusado, fora o próprio cadastro — é isso que faz a trava valer de
/// verdade, e não só sumir com os botões da tela.
enum UserRole { pendente, levita, admin, removido }

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
      case UserRole.removido:
        return 'Fora do ministério';
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
    // `recusado` foi o primeiro nome de `removido`, quando só existia o caso
    // de recusar um pedido novo. Agora recusar um pendente e tirar alguém já
    // aprovado são o MESMO estado — um estado só, uma regra só — e este
    // apelido evita ter de mexer em documento gravado para migrar.
    if (value == 'recusado') return UserRole.removido;
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

  /// Como a função entra numa frase: "Você toca domingo, 19h, **no baixo**".
  ///
  /// Existe porque "Você toca domingo no Cantor(a)" é o que sai ao colar o
  /// rótulo numa frase — e quem canta não "toca": a frase inteira muda.
  String get naFrase {
    switch (this) {
      case UserInstrument.vocalist:
        return 'cantando';
      case UserInstrument.guitar:
        return 'no violão';
      case UserInstrument.bass:
        return 'no baixo';
      case UserInstrument.drums:
        return 'na bateria';
      case UserInstrument.keyboard:
        return 'no teclado';
      case UserInstrument.other:
        return '';
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

  /// Todas as funções da pessoa, e a PRIMEIRA é a principal.
  ///
  /// Era uma função só. Mas no ministério é comum tocar duas coisas — cantar
  /// e fazer violão, baixo e teclado —, e com uma só o líder tinha de
  /// escolher no cadastro qual delas "valia", o que decidia errado a escala e
  /// o modo de ver a música para sempre.
  ///
  /// Nunca é vazia: sem função, a lista nasce com a principal dentro.
  final List<UserInstrument> instruments;
  final String? photoUrl;
  final List<String> favoriteSongs;
  final DateTime createdAt;

  /// Quando e por quem a pessoa saiu do ministério. Só existem enquanto
  /// `role` é `removido`; devolver o acesso limpa os dois. Servem para a tela
  /// Membros poder dizer "saiu em 14/11, por Marcio" — sem isso, "Removidos"
  /// vira uma lista de nomes sem história, e ninguém lembra o que houve.
  final DateTime? removedAt;
  final String? removedBy;

  /// Escolhido no perfil. Nulo = nunca escolheu: vale o que o instrumento
  /// sugere (ver [modoLeitura]).
  final ModoLeitura? leitura;

  /// Conta de robô: a faxina do chat e o mini-servidor dos avisos.
  ///
  /// Elas existem porque este projeto não usa chave de administrador — os
  /// dois robôs entram como líderes comuns, com e-mail e senha. O efeito
  /// colateral é que apareciam como gente: na lista de Membros, na contagem
  /// "3 líderes · 5 membros", nas equipes e nas escalas. E, pior, contavam na
  /// proteção do último líder: dava para remover a última pessoa de verdade
  /// porque o robô "ainda era líder", e o ministério ficava só com ele.
  ///
  /// Robô não usa o app: não entra em lista, não é escalado, não recebe
  /// aviso, e não conta como líder.
  final bool bot;

  /// Esta conta tem um e-mail DE VERDADE, que recebe o link de recuperação.
  ///
  /// É a única coisa que separa "esqueci a senha" de "perdi o acesso para
  /// sempre". O endereço que o Firebase usa para identificar a conta nasce do
  /// nome (`nome@levitas.app`) e esse domínio não é de ninguém: o link de
  /// recuperação enviado para lá não chega a lugar nenhum. E trocar a senha de
  /// outra pessoa exige chave de administrador, que este projeto não tem — nem
  /// o console do Firebase faz isso.
  ///
  /// Então a conta sem e-mail de verdade não tem como ser recuperada. Daí o
  /// campo existir: a tela Membros mostra ao líder quem ainda está nessa
  /// situação, enquanto a pessoa ainda consegue entrar e resolver.
  ///
  /// O endereço em si NÃO vem para cá: ele fica no Firebase Authentication, e
  /// aqui guardamos só o sim/não. Todo aprovado lê `users`, então gravar o
  /// e-mail pessoal de cada um daria a lista de e-mails do ministério a
  /// qualquer membro.
  final bool recuperacaoPorEmail;

  /// A função principal: a que aparece onde só cabe uma (lista de membros,
  /// chat, selo da escala).
  UserInstrument get instrument => instruments.first;

  /// Esta pessoa faz esta função?
  bool fazFuncao(UserInstrument f) => instruments.contains(f);

  bool get temVariasFuncoes => instruments.length > 1;

  /// Limpa a lista de funções: sem repetição, nunca vazia.
  ///
  /// Documento antigo não tem `instruments`, e documento torto pode ter uma
  /// lista vazia. Nos dois casos vale a função principal — uma lista vazia
  /// faria `instrument` lançar e derrubar a tela inteira.
  static List<UserInstrument> _funcoes(
      List<UserInstrument>? lista, UserInstrument principal) {
    final limpa = <UserInstrument>[];
    for (final f in lista ?? const <UserInstrument>[]) {
      if (!limpa.contains(f)) limpa.add(f);
    }
    return limpa.isEmpty ? [principal] : limpa;
  }

  UserModel({
    required this.id,
    required this.name,
    this.email = '',
    this.role = UserRole.levita,
    UserInstrument instrument = UserInstrument.other,
    List<UserInstrument>? instruments,
    this.photoUrl,
    this.favoriteSongs = const [],
    required this.createdAt,
    this.removedAt,
    this.removedBy,
    this.leitura,
    this.bot = false,
    this.recuperacaoPorEmail = false,
  }) : instruments = _funcoes(instruments, instrument);

  bool get isAdmin => role == UserRole.admin;

  /// Já passou pelo líder. É o que abre o app inteiro, e a mesma conta que as
  /// regras do banco fazem — `levita` ou `admin`, nada mais.
  bool get aprovado => role == UserRole.levita || role == UserRole.admin;

  bool get isPendente => role == UserRole.pendente;
  bool get isRemovido => role == UserRole.removido;

  /// Cantor(a) que nunca escolheu lê como quem canta; o resto, como quem toca.
  ModoLeitura get modoLeitura =>
      leitura ?? leituraDaFuncao(instrument);

  /// O modo que uma função pede, quando a pessoa não escolheu.
  ///
  /// Serve ao culto: lá vale a função daquela escala, não a principal — quem
  /// canta num domingo e toca baixo no outro precisa ver coisas diferentes.
  static ModoLeitura leituraDaFuncao(UserInstrument f) =>
      f == UserInstrument.vocalist ? ModoLeitura.canto : ModoLeitura.toco;

  bool get canta => modoLeitura == ModoLeitura.canto;

  /// Lê a lista de funções do banco, descartando o que não se reconhece.
  ///
  /// Nome escrito errado no console vira `other`, e não derruba a tela;
  /// campo ausente devolve nulo, e aí vale a função principal.
  static List<UserInstrument>? _lerFuncoes(Object? bruto) {
    if (bruto is! List) return null;
    final lista = bruto
        .whereType<String>()
        .map(UserInstrumentExtension.fromString)
        .toList();
    return lista.isEmpty ? null : lista;
  }

  static ModoLeitura? _leituraDe(Object? v) =>
      ModoLeitura.values.where((m) => m.name == v).firstOrNull;

  UserModel copyWith({
    String? id,
    String? name,
    String? email,
    UserRole? role,
    UserInstrument? instrument,
    List<UserInstrument>? instruments,
    String? photoUrl,
    List<String>? favoriteSongs,
    DateTime? createdAt,
    DateTime? removedAt,
    String? removedBy,
    bool limparRemocao = false,
    ModoLeitura? leitura,
    bool? bot,
    bool? recuperacaoPorEmail,
  }) {
    return UserModel(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      role: role ?? this.role,
      // `instrument` aqui significa "passa a ser a principal", e as outras
      // funções FICAM. Trocar a principal não é deixar de tocar o resto.
      instruments: instruments ??
          (instrument == null
              ? this.instruments
              : [instrument, ...this.instruments.where((f) => f != instrument)]),
      photoUrl: photoUrl ?? this.photoUrl,
      favoriteSongs: favoriteSongs ?? this.favoriteSongs,
      createdAt: createdAt ?? this.createdAt,
      // `?? this.x` não consegue voltar para nulo, e devolver o acesso
      // precisa exatamente disso: apagar quem removeu e quando.
      removedAt: limparRemocao ? null : (removedAt ?? this.removedAt),
      removedBy: limparRemocao ? null : (removedBy ?? this.removedBy),
      leitura: leitura ?? this.leitura,
      bot: bot ?? this.bot,
      recuperacaoPorEmail: recuperacaoPorEmail ?? this.recuperacaoPorEmail,
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

  /// Este endereço é interno, dos que não recebem e-mail nenhum?
  ///
  /// É a conferência que impede a pior falha possível na recuperação de
  /// senha: mandar o link para `ana@levitas.app`, a tela dizer "enviamos" e
  /// nada chegar nunca. Domínio inexistente, mensagem perdida, pessoa
  /// esperando.
  static bool enderecoInterno(String email) =>
      email.trim().toLowerCase().endsWith('@$emailDomain');

  /// O endereço com que o Firebase vai receber a tentativa de entrada.
  ///
  /// A tela de login pede "nome ou e-mail", e os dois caminham pelo mesmo
  /// lugar: quem tem arroba está dizendo um e-mail de verdade; quem não tem
  /// está dizendo o nome, de onde sai o endereço interno — que é como todo
  /// mundo entrou até hoje e continua entrando.
  ///
  /// Os dois juntos são necessários porque **uma conta tem um endereço só**
  /// no Firebase: quem cadastra um e-mail de verdade para poder recuperar a
  /// senha passa a ter esse endereço no lugar do interno, e entrar pelo nome
  /// deixaria de funcionar para ela.
  static String emailParaEntrar(String nomeOuEmail) {
    final limpo = nomeOuEmail.trim();
    if (limpo.contains('@')) return limpo.toLowerCase();
    return emailForName(limpo);
  }

  Map<String, dynamic> toFirestore() {
    return {
      'id': id,
      'name': name.trim(),
      'nameLower': nameLower,
      'email': email,
      'role': role.name,
      // A principal continua em `instrument`, sozinha: é o que uma versão
      // antiga do app lê, e é o que a regra do banco já validava.
      'instrument': instrument.name,
      'instruments': instruments.map((f) => f.name).toList(),
      'photoUrl': photoUrl,
      'favoriteSongs': favoriteSongs,
      'createdAt': Timestamp.fromDate(createdAt),
      'removedAt': removedAt == null ? null : Timestamp.fromDate(removedAt!),
      'removedBy': removedBy,
      if (leitura != null) 'leitura': leitura!.name,
      // Só grava quando é robô: cadastro de gente não ganha campo novo, e a
      // regra do banco só precisa olhar o que mudou.
      if (bot) 'bot': true,
      if (recuperacaoPorEmail) 'recuperacaoPorEmail': true,
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
      instrument: UserInstrumentExtension.fromString(
          data['instrument'] as String? ?? 'other'),
      instruments: _lerFuncoes(data['instruments']),
      photoUrl: data['photoUrl'] as String?,
      favoriteSongs: List<String>.from(data['favoriteSongs'] ?? []),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      removedAt: (data['removedAt'] as Timestamp?)?.toDate(),
      removedBy: data['removedBy'] as String?,
      leitura: _leituraDe(data['leitura']),
      // Qualquer coisa que não seja `true` é gente. Um valor estranho no
      // console não pode esconder uma pessoa de verdade das listas.
      bot: data['bot'] == true,
      // Só `true` conta: campo ausente, nulo ou torto significa "não tem",
      // que é o lado seguro — manda o líder perguntar de novo, em vez de
      // deixar a pessoa achando que está protegida.
      recuperacaoPorEmail: data['recuperacaoPorEmail'] == true,
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
      'instruments': instruments.map((f) => f.name).toList(),
      'photoUrl': photoUrl,
      'favoriteSongs': favoriteSongs,
      'createdAt': createdAt.toIso8601String(),
      'removedAt': removedAt?.toIso8601String(),
      'removedBy': removedBy,
      if (leitura != null) 'leitura': leitura!.name,
      if (bot) 'bot': true,
      if (recuperacaoPorEmail) 'recuperacaoPorEmail': true,
    };
  }

  factory UserModel.fromJson(Map<String, dynamic> data) {
    return UserModel(
      id: data['id'] as String,
      name: data['name'] as String,
      // Campo ausente cai em pendente, não em levita: um cadastro sem
      // função não pode valer como cadastro aprovado.
      role: UserRoleExtension.fromString(data['role'] as String? ?? ''),
      instrument: UserInstrumentExtension.fromString(
          data['instrument'] as String? ?? 'other'),
      instruments: _lerFuncoes(data['instruments']),
      photoUrl: data['photoUrl'] as String?,
      favoriteSongs: List<String>.from(data['favoriteSongs'] ?? const []),
      createdAt:
          DateTime.tryParse(data['createdAt'] as String? ?? '') ?? DateTime.now(),
      removedAt: DateTime.tryParse(data['removedAt'] as String? ?? ''),
      removedBy: data['removedBy'] as String?,
      leitura: _leituraDe(data['leitura']),
      bot: data['bot'] == true,
      // Só `true` conta: campo ausente, nulo ou torto significa "não tem",
      // que é o lado seguro — manda o líder perguntar de novo, em vez de
      // deixar a pessoa achando que está protegida.
      recuperacaoPorEmail: data['recuperacaoPorEmail'] == true,
    );
  }
}
