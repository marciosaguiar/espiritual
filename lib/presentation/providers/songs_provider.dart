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

  List<SongModel> get songs => _filteredSongs;
  List<SongModel> get allSongs => _songs;
  SongsFilter get filter => _filter;
  String get searchQuery => _searchQuery;
  bool get isLoading => _isLoading;
  String? get error => _error;

  void setFavorites(List<String> ids) {
    _favoriteSongIds = ids;
    _applyFilter();
    notifyListeners();
  }

  void listenToSongs() {
    FirestoreService.watchSongs().listen((songs) {
      _songs = songs;
      _applyFilter();
      notifyListeners();
    }, onError: (e) {
      _error = 'Erro ao carregar músicas';
      notifyListeners();
    });
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
    final success = await FirestoreService.addSong(song);
    if (success) {
      await loadSongs();
    }
    return success;
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

  /// AI-like repertoire suggestion based on history
  List<SongModel> suggestRepertoire({int count = 6}) {
    if (_songs.isEmpty) return [];
    final shuffled = List<SongModel>.from(_songs)..shuffle();
    return shuffled.take(count).toList();
  }
}
