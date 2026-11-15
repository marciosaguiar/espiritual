import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_model.dart';
import '../models/song_model.dart';

class LocalStorageService {
  static const String _sessionKey = 'session_user';
  static const String _themeKey = 'is_dark_mode';
  static const String _offlineSongsKey = 'offline_songs';

  static SharedPreferences? _prefs;

  /// In-memory cache of offline songs so we never decode JSON from disk
  /// inside hot paths (e.g. list item builds). Loaded once on [init].
  static Map<String, SongModel> _offlineCache = {};

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _loadOfflineCache();
  }

  static SharedPreferences get prefs {
    if (_prefs == null) {
      throw Exception('LocalStorageService not initialized. Call init() first.');
    }
    return _prefs!;
  }

  // ─── Session ─────────────────────────────────────────────────────────────

  /// Persists the signed-in user. Uses [UserModel.toJson], which omits the
  /// password hash and encodes dates as ISO strings — the Firestore map is not
  /// JSON-encodable (its `Timestamp` throws), which previously made every
  /// login fail and the session impossible to restore.
  static Future<void> saveSession(UserModel user) async {
    await prefs.setString(_sessionKey, jsonEncode(user.toJson()));
  }

  static UserModel? getSession() {
    final json = prefs.getString(_sessionKey);
    if (json == null) return null;
    try {
      final data = Map<String, dynamic>.from(jsonDecode(json) as Map);
      return UserModel.fromJson(data);
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

  static void _loadOfflineCache() {
    final json = prefs.getString(_offlineSongsKey);
    if (json == null) {
      _offlineCache = {};
      return;
    }
    try {
      final data = Map<String, dynamic>.from(jsonDecode(json) as Map);
      _offlineCache = data.map(
        (k, v) =>
            MapEntry(k, SongModel.fromJson(Map<String, dynamic>.from(v as Map))),
      );
    } catch (_) {
      _offlineCache = {};
    }
  }

  static Future<void> _persistOffline() async {
    final json = jsonEncode(
      _offlineCache.map((k, v) => MapEntry(k, v.toJson())),
    );
    await prefs.setString(_offlineSongsKey, json);
  }

  static Future<void> saveSongOffline(SongModel song) async {
    _offlineCache[song.id] = song;
    await _persistOffline();
  }

  static Future<void> removeSongOffline(String songId) async {
    _offlineCache.remove(songId);
    await _persistOffline();
  }

  /// Returns a copy of the cached offline songs (cheap, no disk/JSON work).
  static Map<String, SongModel> getOfflineSongs() =>
      Map<String, SongModel>.from(_offlineCache);

  /// Apaga tudo o que ficou guardado no aparelho: a sessão e as músicas
  /// salvas para tocar sem internet.
  ///
  /// Usado quando a pessoa sai do ministério. Sem isto, as regras do banco
  /// passariam a recusar tudo, mas o repertório que já estava no celular
  /// continuaria lá — o acesso seria cortado só pela metade.
  static Future<void> limparTudoDoMinisterio() async {
    _offlineCache.clear();
    await _persistOffline();
    await clearSession();
  }

  // ─── Bíblia ───────────────────────────────────────────────────────────────

  static const String _bibliaKey = 'biblia_ultima_leitura';
  static const String _bibliaFonteKey = 'biblia_fonte';

  /// Onde a pessoa parou de ler, por aparelho.
  ///
  /// Fica aqui e não no Firestore porque não há nada a sincronizar: é o
  /// marcador do celular de quem lê, e guardá-lo no banco custaria uma
  /// leitura por abertura para resolver um problema que não existe.
  static Future<void> salvarUltimaLeitura({
    required String traducao,
    required String livro,
    required int capitulo,
  }) async {
    await prefs.setString(_bibliaKey, '$traducao|$livro|$capitulo');
  }

  /// A última leitura, ou null se nunca leu neste aparelho.
  static ({String traducao, String livro, int capitulo})? getUltimaLeitura() {
    final bruto = prefs.getString(_bibliaKey);
    if (bruto == null) return null;
    final partes = bruto.split('|');
    if (partes.length != 3) return null;
    final capitulo = int.tryParse(partes[2]);
    if (capitulo == null || partes[0].isEmpty || partes[1].isEmpty) return null;
    return (traducao: partes[0], livro: partes[1], capitulo: capitulo);
  }

  static Future<void> salvarFonteBiblia(double tamanho) async {
    await prefs.setDouble(_bibliaFonteKey, tamanho);
  }

  static double get fonteBiblia => prefs.getDouble(_bibliaFonteKey) ?? 17;

  static bool isSongOffline(String songId) =>
      _offlineCache.containsKey(songId);

  static int get offlineCount => _offlineCache.length;

  static List<SongModel> get offlineSongsList =>
      _offlineCache.values.toList();
}
