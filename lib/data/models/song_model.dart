import 'package:cloud_firestore/cloud_firestore.dart';

/// A reference saved with a song: a video, a chord sheet, a recording.
///
/// The ministry finds songs on the internet, so a song keeps several links,
/// not just one video.
class SongLink {
  final String url;

  /// What to call it on screen. Empty means "work it out from the address".
  final String label;

  const SongLink({required this.url, this.label = ''});

  /// Name to show. Falls back to the site's own name, so a pasted address
  /// never shows up as a bare URL.
  String get displayLabel {
    if (label.trim().isNotEmpty) return label.trim();
    final host = Uri.tryParse(url)?.host.replaceFirst('www.', '') ?? '';
    if (host.isEmpty) return 'Link';
    if (host.contains('youtube') || host.contains('youtu.be')) return 'YouTube';
    if (host.contains('spotify')) return 'Spotify';
    if (host.contains('cifraclub')) return 'Cifra Club';
    if (host.contains('letras')) return 'Letras';
    return host;
  }

  bool get isVideo {
    final host = Uri.tryParse(url)?.host ?? '';
    return host.contains('youtube') || host.contains('youtu.be');
  }

  Map<String, dynamic> toMap() => {'url': url, 'label': label};

  factory SongLink.fromMap(Map<String, dynamic> data) => SongLink(
        url: data['url'] as String? ?? '',
        label: data['label'] as String? ?? '',
      );
}

/// A song as a work: what it is called, who recorded it, the words.
///
/// What it deliberately does NOT hold: the chord chart. How this church plays
/// a song is an arrangement, lives in `songs/{id}/arrangements/{id}`, and can
/// have more than one version — see [ArrangementModel]. Keeping charts out of
/// this document also means opening the app no longer downloads every chart in
/// the repertoire.
class SongModel {
  final String id;
  final String name;
  final String artist;
  final String lyrics;

  /// Key the song was recorded in. The key this church plays belongs to the
  /// arrangement.
  final String originalKey;

  final List<SongLink> links;

  /// Recado do líder sobre a música: "entra sem bateria", "repete o refrão
  /// três vezes", "subir meio tom no último".
  ///
  /// Fica na música, e não no arranjo, porque é combinação da igreja sobre a
  /// obra — e aparece para quem canta e para quem toca igual.
  final String observacoes;

  final bool isOfflineAvailable;
  final DateTime createdAt;
  final String? addedBy;

  /// De qual hinário impresso este hino é: `harpa`, `cantor`. Vazio na música
  /// que não é hino, que é a maioria.
  ///
  /// Guardar o id, e não o nome, é o que permite trocar "Harpa Cristã" por
  /// outro rótulo na tela sem reescrever o repertório. Ver
  /// `core/constants/hinarios.dart`.
  final String hinario;

  /// O número do hino naquele hinário. Nulo na música que não é hino.
  ///
  /// Nulo e não zero: zero é um número, e um dia alguém o leria como "hino
  /// zero". Ausência tem de parecer ausência.
  final int? numero;

  /// Tirada do repertório, mas NÃO apagada.
  ///
  /// Mesma decisão que já valia para os cultos — "cancelar é um campo, nunca
  /// exclusão" — e pelo mesmo motivo prático: o documento continua existindo,
  /// então os cultos em que a música foi tocada seguem mostrando o nome dela
  /// em vez de "Música removida", e um toque errado tem conserto. Apagar de
  /// verdade só pelo console do Firebase; as regras não deixam mais nem o
  /// líder apagar pelo app.
  final bool archived;
  final DateTime? archivedAt;
  final String? archivedBy;

  const SongModel({
    required this.id,
    required this.name,
    required this.artist,
    required this.lyrics,
    required this.originalKey,
    this.links = const [],
    this.observacoes = '',
    this.isOfflineAvailable = false,
    required this.createdAt,
    this.addedBy,
    this.hinario = '',
    this.numero,
    this.archived = false,
    this.archivedAt,
    this.archivedBy,
  });

  /// A música com o link de vídeo trocado pelo que vem em [url].
  ///
  /// Mexe SÓ no link de vídeo: o Cifra Club, o Spotify e qualquer outro que a
  /// música já tenha ficam como estão. Vazio ou nulo tira o vídeo.
  ///
  /// Mora aqui, e não na tela de editar, porque é regra sobre os dados — e
  /// porque "trocar o YouTube sem derrubar os outros links" é exatamente o
  /// tipo de coisa que um teste precisa alcançar.
  SongModel comVideo(String? url) {
    final limpo = (url ?? '').trim();
    final outros = links.where((l) => !l.isVideo).toList();
    return copyWith(
      links: limpo.isEmpty
          ? outros
          : [SongLink(url: limpo, label: 'YouTube'), ...outros],
    );
  }

  /// É um hino de hinário impresso?
  ///
  /// Exige os DOIS campos. Um sem o outro é documento pela metade — hinário
  /// sem número não dá para abrir, número sem hinário não dá para saber de
  /// onde é —, e nos dois casos é melhor tratar como música comum que como
  /// hino quebrado.
  bool get ehHino => hinario.isNotEmpty && numero != null;

  /// First video link, for the "watch" button.
  String? get videoUrl {
    for (final l in links) {
      if (l.isVideo) return l.url;
    }
    return null;
  }

  SongModel copyWith({
    String? id,
    String? name,
    String? artist,
    String? lyrics,
    String? originalKey,
    List<SongLink>? links,
    String? observacoes,
    bool? isOfflineAvailable,
    DateTime? createdAt,
    String? addedBy,
    bool? archived,
    DateTime? archivedAt,
    String? archivedBy,
    bool limparArquivamento = false,
    String? hinario,
    int? numero,
  }) {
    return SongModel(
      id: id ?? this.id,
      name: name ?? this.name,
      artist: artist ?? this.artist,
      lyrics: lyrics ?? this.lyrics,
      originalKey: originalKey ?? this.originalKey,
      links: links ?? this.links,
      observacoes: observacoes ?? this.observacoes,
      isOfflineAvailable: isOfflineAvailable ?? this.isOfflineAvailable,
      createdAt: createdAt ?? this.createdAt,
      addedBy: addedBy ?? this.addedBy,
      archived: limparArquivamento ? false : (archived ?? this.archived),
      // `?? this.x` nunca consegue voltar para nulo, e devolver a música ao
      // repertório precisa exatamente disso.
      archivedAt: limparArquivamento ? null : (archivedAt ?? this.archivedAt),
      archivedBy: limparArquivamento ? null : (archivedBy ?? this.archivedBy),
      hinario: hinario ?? this.hinario,
      numero: numero ?? this.numero,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'id': id,
      'name': name,
      'artist': artist,
      'lyrics': lyrics,
      'originalKey': originalKey,
      'links': links.map((l) => l.toMap()).toList(),
      'observacoes': observacoes,
      'isOfflineAvailable': isOfflineAvailable,
      'createdAt': Timestamp.fromDate(createdAt),
      'addedBy': addedBy,
      'archived': archived,
      'archivedAt': archivedAt == null ? null : Timestamp.fromDate(archivedAt!),
      'archivedBy': archivedBy,
      'hinario': hinario,
      'numero': numero,
    };
  }

  factory SongModel.fromFirestore(Map<String, dynamic> data) {
    return SongModel(
      id: data['id'] as String,
      name: data['name'] as String,
      artist: data['artist'] as String? ?? '',
      lyrics: data['lyrics'] as String? ?? '',
      originalKey: data['originalKey'] as String? ?? 'C',
      links: _linksFrom(data),
      observacoes: data['observacoes'] as String? ?? '',
      isOfflineAvailable: data['isOfflineAvailable'] as bool? ?? false,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      addedBy: data['addedBy'] as String?,
      // Música gravada antes do arquivamento não tem o campo: está no
      // repertório, como sempre esteve.
      archived: data['archived'] as bool? ?? false,
      archivedAt: (data['archivedAt'] as Timestamp?)?.toDate(),
      archivedBy: data['archivedBy'] as String?,
      hinario: data['hinario'] as String? ?? '',
      numero: _numeroDe(data['numero']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'artist': artist,
      'lyrics': lyrics,
      'originalKey': originalKey,
      'links': links.map((l) => l.toMap()).toList(),
      'observacoes': observacoes,
      'isOfflineAvailable': isOfflineAvailable,
      'createdAt': createdAt.toIso8601String(),
      'addedBy': addedBy,
      'archived': archived,
      // Timestamp não vira JSON — ver CLAUDE.md.
      'archivedAt': archivedAt?.toIso8601String(),
      'archivedBy': archivedBy,
      'hinario': hinario,
      'numero': numero,
    };
  }

  factory SongModel.fromJson(Map<String, dynamic> data) {
    return SongModel(
      id: data['id'] as String,
      name: data['name'] as String,
      artist: data['artist'] as String? ?? '',
      lyrics: data['lyrics'] as String? ?? '',
      originalKey: data['originalKey'] as String? ?? 'C',
      links: _linksFrom(data),
      observacoes: data['observacoes'] as String? ?? '',
      isOfflineAvailable: data['isOfflineAvailable'] as bool? ?? false,
      createdAt: DateTime.tryParse(data['createdAt'] as String? ?? '') ??
          DateTime.now(),
      addedBy: data['addedBy'] as String?,
      archived: data['archived'] as bool? ?? false,
      archivedAt: DateTime.tryParse(data['archivedAt'] as String? ?? ''),
      archivedBy: data['archivedBy'] as String?,
      hinario: data['hinario'] as String? ?? '',
      numero: _numeroDe(data['numero']),
    );
  }

  /// O número do hino, vindo do banco ou do aparelho.
  ///
  /// O Firestore devolve inteiro, mas o mesmo campo sai como `num` no JSON
  /// guardado no celular — e um documento mexido no console pode trazer
  /// texto. Qualquer coisa que não seja um número inteiro de verdade vira
  /// nulo, que o resto do app já sabe tratar como "não é hino".
  static int? _numeroDe(Object? bruto) {
    if (bruto is int) return bruto;
    if (bruto is num) return bruto.toInt();
    if (bruto is String) return int.tryParse(bruto.trim());
    return null;
  }

  /// Reads the link list, accepting the single `youtubeUrl` field that songs
  /// used to carry.
  static List<SongLink> _linksFrom(Map<String, dynamic> data) {
    final raw = data['links'];
    if (raw is List) {
      return raw
          .map((l) => SongLink.fromMap(Map<String, dynamic>.from(l as Map)))
          .where((l) => l.url.isNotEmpty)
          .toList();
    }
    final legacy = data['youtubeUrl'] as String?;
    if (legacy != null && legacy.isNotEmpty) {
      return [SongLink(url: legacy, label: 'YouTube')];
    }
    return const [];
  }
}
