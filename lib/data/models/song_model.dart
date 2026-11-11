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
  final bool isOfflineAvailable;
  final DateTime createdAt;
  final String? addedBy;

  const SongModel({
    required this.id,
    required this.name,
    required this.artist,
    required this.lyrics,
    required this.originalKey,
    this.links = const [],
    this.isOfflineAvailable = false,
    required this.createdAt,
    this.addedBy,
  });

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
    bool? isOfflineAvailable,
    DateTime? createdAt,
    String? addedBy,
  }) {
    return SongModel(
      id: id ?? this.id,
      name: name ?? this.name,
      artist: artist ?? this.artist,
      lyrics: lyrics ?? this.lyrics,
      originalKey: originalKey ?? this.originalKey,
      links: links ?? this.links,
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
      'originalKey': originalKey,
      'links': links.map((l) => l.toMap()).toList(),
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
      originalKey: data['originalKey'] as String? ?? 'C',
      links: _linksFrom(data),
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
      'originalKey': originalKey,
      'links': links.map((l) => l.toMap()).toList(),
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
      originalKey: data['originalKey'] as String? ?? 'C',
      links: _linksFrom(data),
      isOfflineAvailable: data['isOfflineAvailable'] as bool? ?? false,
      createdAt: DateTime.tryParse(data['createdAt'] as String? ?? '') ??
          DateTime.now(),
      addedBy: data['addedBy'] as String?,
    );
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
