import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_model.dart';
import '../models/song_model.dart';

class LocalStorageService {
  static const String _sessionKey = 'session_user';
  static const String _themeKey = 'is_dark_mode';
  static const String _offlineSongsKey = 'offline_songs';

  static SharedPreferences? _prefs;

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
    final json = jsonEncode(user.toFirestore()
      ..remove('passwordHash')); // don't store hash in prefs
    await prefs.setString(_sessionKey, json);
  }

  static Future<void> saveSessionFull(UserModel user) async {
    final data = user.toFirestore();
    final json = jsonEncode(data);
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
    final json = jsonEncode(
      songs.map((k, v) => MapEntry(k, v.toJson())),
    );
    await prefs.setString(_offlineSongsKey, json);
  }

  static Future<void> removeSongOffline(String songId) async {
    final songs = getOfflineSongs();
    songs.remove(songId);
    final json = jsonEncode(
      songs.map((k, v) => MapEntry(k, v.toJson())),
    );
    await prefs.setString(_offlineSongsKey, json);
  }

  static Map<String, SongModel> getOfflineSongs() {
    final json = prefs.getString(_offlineSongsKey);
    if (json == null) return {};
    try {
      final data = Map<String, dynamic>.from(jsonDecode(json) as Map);
      return data.map(
        (k, v) => MapEntry(k, SongModel.fromJson(Map<String, dynamic>.from(v as Map))),
      );
    } catch (_) {
      return {};
    }
  }

  static bool isSongOffline(String songId) {
    return getOfflineSongs().containsKey(songId);
  }

  static List<SongModel> get offlineSongsList =>
      getOfflineSongs().values.toList();
}
