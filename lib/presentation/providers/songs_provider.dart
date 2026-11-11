import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../../data/models/song_model.dart';
import '../../data/services/firestore_service.dart';
import '../../data/services/local_storage_service.dart';

enum SongsFilter { all, favorites, offline }

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
  List<SongModel> get allSongs => _songs;
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

  @override
  void dispose() {
    _songsSub?.cancel();
    super.dispose();
  }

  Future<void> loadSongs() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      _songs = await FirestoreService.getSongs();
      _applyFilter();
    } catch (e) {
      // Try offline
      _songs = LocalStorageService.offlineSongsList;
      _applyFilter();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
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
      case SongsFilter.all:
        base = List.from(_songs);
        break;
      case SongsFilter.favorites:
        base = _songs.where((s) => _favoriteSongIds.contains(s.id)).toList();
        break;
      case SongsFilter.offline:
        final offlineIds = LocalStorageService.getOfflineSongs().keys.toSet();
        base = _songs.where((s) => offlineIds.contains(s.id)).toList();
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

  Future<bool> addSong(SongModel song) async {
    // No manual reload needed: the realtime listener picks up the new song.
    return FirestoreService.addSong(song);
  }

  Future<bool> updateSong(SongModel song) async {
    final success = await FirestoreService.updateSong(song);
    if (success) {
      final idx = _songs.indexWhere((s) => s.id == song.id);
      if (idx >= 0) {
        _songs[idx] = song;
        _applyFilter();
        notifyListeners();
      }
    }
    return success;
  }

  Future<bool> deleteSong(String songId) async {
    final success = await FirestoreService.deleteSong(songId);
    if (success) {
      _songs.removeWhere((s) => s.id == songId);
      _applyFilter();
      notifyListeners();
    }
    return success;
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
  List<SongModel> suggestRepertoire({int count = 6}) {
    if (_songs.isEmpty) return const [];
    final now = DateTime.now();
    final seed = now.year * 10000 + now.month * 100 + now.day;
    final shuffled = List<SongModel>.from(_songs)..shuffle(Random(seed));
    return shuffled.take(count).toList();
  }
}
