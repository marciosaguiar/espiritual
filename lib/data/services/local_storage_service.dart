import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_model.dart';
import '../models/song_model.dart';

class LocalStorageService {
  static const String _sessionKey = 'session_user';
  static const String _themeKey = 'is_dark_mode';
  static const String _offlineSongsKey = 'offline_songs';

  static SharedPreferences? _prefs;
  static Map<String, SongModel>? _offlineCache;

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  static SharedPreferences get prefs {
    if (_prefs == null) {
      throw Exception('LocalStorageService not initialized. Call init() first.');
    }
    return _prefs!;
  }

  // ─── Session ─────────────────────────────────────────────────────────────

  static Future<void> saveSession(UserModel user) async {
    // toJson() uses ISO-8601 strings (not Firestore Timestamps) — survives
    // JSON round-trip and does not include passwordHash.
    final json = jsonEncode(user.toJson());
    await prefs.setString(_sessionKey, json);
  }

  static UserModel? getSession() {
    final json = prefs.getString(_sessionKey);
    if (json == null) return null;
    try {
      final data = Map<String, dynamic>.from(jsonDecode(json) as Map);
      return UserModel.fromFirestore(data);
    } catch (_) {
      return null;
    }
  }

  static Future<void> clearSession() async {
    await prefs.remove(_sessionKey);
  }

  static bool get hasSession => prefs.containsKey(_sessionKey);

  // ─── Theme ───────────────────────────────────────────────────────────────

  static Future<void> saveTheme(bool isDark) async {
    await prefs.setBool(_themeKey, isDark);
  }

  static bool get isDarkMode => prefs.getBool(_themeKey) ?? false;

  // ─── Offline Songs ────────────────────────────────────────────────────────

  static Future<void> saveSongOffline(SongModel song) async {
    final songs = getOfflineSongs();
    songs[song.id] = song;
    _offlineCache = Map.from(songs);
    final json = jsonEncode(songs.map((k, v) => MapEntry(k, v.toJson())));
    await prefs.setString(_offlineSongsKey, json);
  }

  static Future<void> removeSongOffline(String songId) async {
    final songs = getOfflineSongs();
    songs.remove(songId);
    _offlineCache = Map.from(songs);
    final json = jsonEncode(songs.map((k, v) => MapEntry(k, v.toJson())));
    await prefs.setString(_offlineSongsKey, json);
  }

  /// Returns the offline songs map. Result is cached in memory so repeated
  /// calls (e.g. from list tiles) skip JSON parsing after the first load.
  static Map<String, SongModel> getOfflineSongs() {
    if (_offlineCache != null) return _offlineCache!;
    final json = prefs.getString(_offlineSongsKey);
    if (json == null) {
      _offlineCache = {};
      return _offlineCache!;
    }
    try {
      final data = Map<String, dynamic>.from(jsonDecode(json) as Map);
      _offlineCache = data.map(
        (k, v) => MapEntry(k, SongModel.fromJson(Map<String, dynamic>.from(v as Map))),
      );
      return _offlineCache!;
    } catch (_) {
      _offlineCache = {};
      return _offlineCache!;
    }
  }

  static bool isSongOffline(String songId) {
    return getOfflineSongs().containsKey(songId);
  }

  static List<SongModel> get offlineSongsList =>
      getOfflineSongs().values.toList();
}
