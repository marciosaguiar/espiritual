import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../../data/models/scale_model.dart';
import '../../data/models/song_model.dart';
import '../../data/services/firestore_service.dart';
import '../../data/services/local_storage_service.dart';

enum SongsFilter { all, favorites, offline, arquivadas }

class SongsProvider extends ChangeNotifier {
  List<SongModel> _songs = [];
  List<SongModel> _filteredSongs = [];
  SongsFilter _filter = SongsFilter.all;
  String _searchQuery = '';
  bool _isLoading = false;
  String? _error;
  List<String> _favoriteSongIds = [];

  StreamSubscription<List<SongModel>>? _songsSub;

  List<SongModel> get songs => _filteredSongs;
  /// TUDO, arquivadas incluídas. Serve para RESOLVER por id — é o que faz um
  /// culto antigo continuar mostrando o nome da música em vez de "Música
  /// removida". Nunca use para oferecer músicas a escolher.
  List<SongModel> get allSongs => _songs;

  /// O repertório de hoje: o que se pode escolher, escalar, buscar.
  /// Tirar do repertório não serviria de nada se a música continuasse
  /// aparecendo na hora de montar o culto.
  List<SongModel> get repertorio =>
      _songs.where((s) => !s.archived).toList();
  SongsFilter get filter => _filter;
  String get searchQuery => _searchQuery;
  bool get isLoading => _isLoading;
  String? get error => _error;
  int get offlineCount => LocalStorageService.offlineCount;

  /// Idempotent: only rebuilds when the favorite set actually changes.
  /// This guard is what prevents an infinite rebuild loop when callers
  /// sync favorites in response to other provider updates.
  void setFavorites(List<String> ids) {
    if (listEquals(_favoriteSongIds, ids)) return;
    _favoriteSongIds = List<String>.from(ids);
    _applyFilter();
    notifyListeners();
  }

  void listenToSongs() {
    // Guard against stacking multiple subscriptions (e.g. re-login).
    if (_songsSub != null) return;
    _isLoading = true;
    _songsSub = FirestoreService.watchSongs().listen((songs) {
      _songs = songs;
      _isLoading = false;
      _error = null;
      _applyFilter();
      notifyListeners();
    }, onError: (e) {
      _isLoading = false;
      _error = 'Erro ao carregar músicas';
      notifyListeners();
    });
  }

  /// Drops the listener and attaches a new one.
  ///
  /// The listener guards against stacking subscriptions, so after a failure it
  /// would never reconnect on its own — "Tentar de novo" needs this.
  void retry() {
    _songsSub?.cancel();
    _songsSub = null;
    _error = null;
    notifyListeners();
    listenToSongs();
  }

  @override
  void dispose() {
    _songsSub?.cancel();
    super.dispose();
  }

  void search(String query) {
    _searchQuery = query;
    _applyFilter();
    notifyListeners();
  }

  void setFilter(SongsFilter filter) {
    _filter = filter;
    _applyFilter();
    notifyListeners();
  }

  void _applyFilter() {
    List<SongModel> base;

    switch (_filter) {
      // As arquivadas continuam em `_songs`, para os cultos antigos
      // resolverem o nome; o que muda é só o que a tela mostra.
      case SongsFilter.all:
        base = _songs.where((s) => !s.archived).toList();
        break;
      case SongsFilter.favorites:
        base = _songs
            .where((s) => !s.archived && _favoriteSongIds.contains(s.id))
            .toList();
        break;
      case SongsFilter.offline:
        final offlineIds = LocalStorageService.getOfflineSongs().keys.toSet();
        base = _songs
            .where((s) => !s.archived && offlineIds.contains(s.id))
            .toList();
        break;
      case SongsFilter.arquivadas:
        base = _songs.where((s) => s.archived).toList();
        break;
    }

    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      base = base.where((s) {
        return s.name.toLowerCase().contains(q) ||
            s.artist.toLowerCase().contains(q);
      }).toList();
    }

    _filteredSongs = base;
  }

  /// Adds a song. Returns null on success, or the message to show.
  Future<String?> addSong(SongModel song) async {
    // No manual reload needed: the realtime listener picks up the new song.
    final result = await FirestoreService.addSong(song);
    return result.error;
  }

  /// Changes a song. Returns null on success, or the message to show.
  Future<String?> updateSong(SongModel song) async {
    final result = await FirestoreService.updateSong(song);
    if (!result.success) return result.error;

    final idx = _songs.indexWhere((s) => s.id == song.id);
    if (idx >= 0) {
      _songs[idx] = song;
      _applyFilter();
      notifyListeners();
    }
    return null;
  }

  /// Tira a música do repertório. Devolve null quando dá certo.
  ///
  /// A música NÃO sai de `_songs`: sai só das listas que a tela mostra. É
  /// isso que mantém `nameOf` respondendo o nome certo nos cultos em que ela
  /// foi tocada — tirar daqui faria voltar o "Música removida" que o
  /// arquivamento existe para evitar.
  Future<String?> arquivar(String songId, String porQuemId) async {
    final r = await FirestoreService.arquivarSong(songId, porQuemId);
    if (!r.success) return r.error;
    // A cópia guardada no aparelho sai junto: a música não está mais no
    // repertório, e deixá-la ali só confundiria quem procura offline.
    await LocalStorageService.removeSongOffline(songId);
    return null;
  }

  Future<String?> desarquivar(String songId) async {
    final r = await FirestoreService.desarquivarSong(songId);
    return r.success ? null : r.error;
  }

  Future<void> toggleOffline(SongModel song) async {
    if (LocalStorageService.isSongOffline(song.id)) {
      await LocalStorageService.removeSongOffline(song.id);
    } else {
      await LocalStorageService.saveSongOffline(song);
    }
    _applyFilter();
    notifyListeners();
  }

  bool isOffline(String songId) => LocalStorageService.isSongOffline(songId);

  SongModel? getSongById(String id) {
    try {
      return _songs.firstWhere((s) => s.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Repertoire suggestion. Seeded by the current day so the list stays
  /// stable across rebuilds (it no longer reshuffles on every frame).
  // ─── Resolving service references ─────────────────────────────────────────
  // A service stores only ids, so these turn a reference into what to show.
  // Correcting a song now corrects every service that uses it.

  /// Name to show for a referenced song.
  String nameOf(ScaleSong ref) =>
      getSongById(ref.songId)?.name ?? 'Música removida';

  /// Artist to show, empty when unknown.
  String artistOf(ScaleSong ref) => getSongById(ref.songId)?.artist ?? '';

  /// Key to show: the service's own key when it sets one, else the song's.
  String keyOf(ScaleSong ref) {
    if (ref.keyOverride.isNotEmpty) return ref.keyOverride;
    return getSongById(ref.songId)?.originalKey ?? '?';
  }

  /// Whether the referenced song still exists in the repertoire.
  bool exists(ScaleSong ref) => getSongById(ref.songId) != null;

  List<SongModel> suggestRepertoire({int count = 6}) {
    if (repertorio.isEmpty) return const [];
    final now = DateTime.now();
    final seed = now.year * 10000 + now.month * 100 + now.day;
    final shuffled = List<SongModel>.from(repertorio)..shuffle(Random(seed));
    return shuffled.take(count).toList();
  }
}
