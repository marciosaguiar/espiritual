import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/utils/crypto_utils.dart';
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

  // ─── Avisos do chat ───────────────────────────────────────────────────────

  static const String _aparelhoKey = 'id_do_aparelho';

  /// Um id fixo para ESTE aparelho, criado na primeira vez e guardado.
  ///
  /// É a chave do registro de inscrição no Firestore. Sem um id estável, cada
  /// abertura do app criaria um registro novo e o ministério acumularia
  /// inscrições mortas — e cada aviso tentaria mandar para todas elas.
  ///
  /// Não identifica a pessoa: é sorteado, fica só neste navegador, e some
  /// quando ela limpa os dados do site (que também mata a inscrição).
  static String get idDoAparelho {
    final guardado = prefs.getString(_aparelhoKey);
    if (guardado != null && guardado.isNotEmpty) return guardado;
    final novo = CryptoUtils.generateId();
    // Sem `await`: o id já vale nesta chamada, e perder a gravação só
    // custaria um registro extra na próxima abertura.
    prefs.setString(_aparelhoKey, novo);
    return novo;
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

  // ─── Hinos pelo número ────────────────────────────────────────────────────

  static const String _hinarioKey = 'hinario_escolhido';
  static const String _hinosAbertosKey = 'hinos_abertos';
  static const int _maxHinosAbertos = 8;

  /// O hinário que esta pessoa usa neste aparelho.
  ///
  /// Uma igreja canta de um hinário quase sempre; fazer a pessoa escolher
  /// "Harpa" toda vez que abre a tela seria um toque a mais no meio do culto,
  /// que é exatamente onde ela não tem tempo.
  static Future<void> salvarHinario(String id) async {
    await prefs.setString(_hinarioKey, id);
  }

  static String? get ultimoHinario {
    final v = prefs.getString(_hinarioKey);
    return (v == null || v.isEmpty) ? null : v;
  }

  /// Guarda que este hino foi aberto, do mais recente para o mais antigo.
  ///
  /// Fica no aparelho, como o marcador da Bíblia: é o histórico de quem está
  /// com o celular na mão, não há o que sincronizar, e no Firestore custaria
  /// uma escrita por hino aberto.
  static Future<void> salvarHinoAberto(String hinario, int numero) async {
    final chave = '\$hinario|\$numero';
    final lista = prefs.getStringList(_hinosAbertosKey) ?? <String>[];
    // Tira antes de pôr na frente: abrir o mesmo hino duas vezes não pode
    // encher a lista de repetições e empurrar os outros para fora.
    lista.remove(chave);
    lista.insert(0, chave);
    await prefs.setStringList(
        _hinosAbertosKey, lista.take(_maxHinosAbertos).toList());
  }

  /// Os últimos hinos abertos neste aparelho.
  ///
  /// Entrada torta é descartada em silêncio, não derruba a tela: é leitura
  /// com valor padrão seguro, e o pior caso é a lista vir mais curta.
  static List<({String hinario, int numero})> get hinosAbertos {
    final lista = prefs.getStringList(_hinosAbertosKey) ?? const <String>[];
    final saida = <({String hinario, int numero})>[];
    for (final bruto in lista) {
      final p = bruto.split('|');
      if (p.length != 2 || p[0].isEmpty) continue;
      final n = int.tryParse(p[1]);
      if (n == null) continue;
      saida.add((hinario: p[0], numero: n));
    }
    return saida;
  }

  static bool isSongOffline(String songId) =>
      _offlineCache.containsKey(songId);

  static int get offlineCount => _offlineCache.length;

  static List<SongModel> get offlineSongsList =>
      _offlineCache.values.toList();
}
