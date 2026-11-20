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
      throw Exception(
          'LocalStorageService not initialized. Call init() first.');
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
        (k, v) => MapEntry(
            k, SongModel.fromJson(Map<String, dynamic>.from(v as Map))),
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

  // ─── Quando o chat foi visto ───────────────────────────────────────────────

  static const String _chatVistoKey = 'chat_visto_em';

  /// A última vez que esta pessoa abriu o chat NESTE aparelho.
  ///
  /// Fica no aparelho, e não no banco, de propósito: o Firestore já tem
  /// `chatLeituras` para os dois tiques, e aquele documento é escrito uma vez
  /// por abertura do chat. Ler de lá para contar não lidas no Início
  /// custaria uma escuta a mais sobre o mesmo dado, e o número aqui é só
  /// para um aviso — não para prometer nada a ninguém.
  ///
  /// Limite conhecido: quem usa dois aparelhos vê a contagem de cada um
  /// separada. Para um aviso de "tem mensagem nova", isso é aceitável; se um
  /// dia não for, o caminho é `chatLeituras`, não este campo.
  static Future<void> marcarChatVisto() async {
    await prefs.setString(_chatVistoKey, DateTime.now().toIso8601String());
  }

  /// Nulo quando nunca abriu o chat neste aparelho — e aí a contagem é zero,
  /// não "tudo". Estrear o app com "47 mensagens novas" não é notícia, é
  /// parede.
  static DateTime? get chatVistoEm {
    final bruto = prefs.getString(_chatVistoKey);
    return bruto == null ? null : DateTime.tryParse(bruto);
  }

  // ─── Esconder tablatura ───────────────────────────────────────────────────

  static const String _tablaturaKey = 'ocultar_tablaturas';

  /// Quem toca violão quer tablatura sempre; quem canta, nunca. Então a
  /// escolha é do APARELHO e vale para todas as músicas — perguntar música
  /// por música seria o mesmo toque repetido para a mesma pessoa, para
  /// sempre.
  ///
  /// Ausente é MOSTRAR: é como o app sempre funcionou, e esconder parte da
  /// cifra de quem não pediu seria pior que mostrar demais.
  static bool get ocultarTablaturas => prefs.getBool(_tablaturaKey) ?? false;

  static Future<void> salvarOcultarTablaturas(bool ocultar) async {
    await prefs.setBool(_tablaturaKey, ocultar);
  }

  // ─── Faixa "Sugestão de repertório" ───────────────────────────────────────

  static const String _sugestoesKey = 'sugestoes_abertas';

  /// A faixa de sugestão do Repertório abre ou fecha, e a escolha fica no
  /// aparelho. Ausente é FECHADA: a tela serve primeiro a quem procura uma
  /// música, e as quatro sugestões repetem músicas que já estão na lista.
  static bool get sugestoesAbertas => prefs.getBool(_sugestoesKey) ?? false;

  static Future<void> salvarSugestoesAbertas(bool abertas) async {
    await prefs.setBool(_sugestoesKey, abertas);
  }

  // ─── Rascunho do editor de letra e cifra ──────────────────────────────────

  static const String _rascunhoKey = 'rascunho_cifra';

  /// Guarda o que está sendo escrito no editor de letra e cifra.
  ///
  /// POR QUE ISTO EXISTE
  ///
  /// Colar e arrumar uma cifra leva minutos, e é feito sentado no sofá com a
  /// internet da casa — a mesma que cai. Sem rascunho, a tela volta vazia e o
  /// trabalho inteiro se perde sem nada avisar; é o tipo de perda que faz uma
  /// pessoa desistir do app.
  ///
  /// Fica no APARELHO, não no banco: é texto não salvo, de uma pessoa só, e
  /// gravá-lo no Firestore a cada tecla seria cota jogada fora.
  static Future<void> salvarRascunho(String songId, String texto) async {
    if (songId.isEmpty) return;
    await prefs.setString('$_rascunhoKey|$songId', texto);
  }

  /// O rascunho daquela música, ou nulo.
  static String? rascunho(String songId) {
    if (songId.isEmpty) return null;
    final t = prefs.getString('$_rascunhoKey|$songId');
    return (t == null || t.trim().isEmpty) ? null : t;
  }

  /// Apaga o rascunho. Chamado quando a gravação dá certo — e só então.
  static Future<void> esquecerRascunho(String songId) async {
    if (songId.isEmpty) return;
    await prefs.remove('$_rascunhoKey|$songId');
  }

  // ─── Fui ao Cifra Club ────────────────────────────────────────────────────

  static const String _idaAoCifraClubKey = 'ida_ao_cifra_club';

  /// Quanto tempo a ida ao Cifra Club continua valendo como "acabei de ir".
  ///
  /// Trinta minutos: é tempo de achar a música, conferir o tom e copiar, e
  /// curto o bastante para a faixa não aparecer no domingo seguinte por
  /// causa de uma busca de quarta-feira.
  static const Duration validadeDaIda = Duration(minutes: 30);

  /// Marca que a pessoa acabou de sair para o Cifra Club, com o que ela
  /// estava procurando.
  ///
  /// POR QUE A MARCA EXISTE
  ///
  /// A faixa "toque para usar a cifra copiada" não pode LER a área de
  /// transferência para decidir se aparece: no iPhone, ler exige um toque da
  /// pessoa, e perguntar antes de ter o que oferecer seria pedir permissão
  /// por nada. A marca resolve isso de outro jeito — se acabamos de mandar a
  /// pessoa ao Cifra Club, o que ela copiou lá é quase certamente uma cifra.
  static Future<void> marcarIdaAoCifraClub(String procurado) async {
    await prefs.setString(
        _idaAoCifraClubKey, '${DateTime.now().toIso8601String()}|$procurado');
  }

  /// O que foi procurado, se a ida foi recente. Nulo caso contrário.
  static String? idaRecenteAoCifraClub([DateTime? agora]) {
    final bruto = prefs.getString(_idaAoCifraClubKey);
    if (bruto == null) return null;
    final corte = bruto.indexOf('|');
    if (corte < 0) return null;
    final quando = DateTime.tryParse(bruto.substring(0, corte));
    if (quando == null) return null;
    final referencia = agora ?? DateTime.now();
    if (referencia.difference(quando) > validadeDaIda) return null;
    return bruto.substring(corte + 1);
  }

  static Future<void> esquecerIdaAoCifraClub() async {
    await prefs.remove(_idaAoCifraClubKey);
  }

  // ─── Hinos pelo número ────────────────────────────────────────────────────

  static const String _hinarioKey = 'hinario_escolhido';
  static const String _hinosAbertosKey = 'hinos_abertos';
  static const String _ordemHinariosKey = 'ordem_hinarios';
  static const String _ordemHinosKey = 'ordem_hinos';
  static const int _maxHinosAbertos = 8;

  /// A ordem em que os hinários aparecem, escolhida arrastando os cartões.
  ///
  /// FICA NO APARELHO, como o marcador da Bíblia e os últimos hinos abertos.
  /// É preferência de quem está com o celular na mão: não há o que
  /// sincronizar, ninguém mais precisa saber, e no Firestore custaria uma
  /// leitura por abertura do app para guardar duas palavras.
  ///
  /// Guarda só os ids. Quem transforma isto na lista da tela é
  /// `hinariosNaOrdem`, que sabe lidar com id que não existe mais e com
  /// hinário novo que ainda não está aqui.
  static Future<void> salvarOrdemDosHinarios(List<String> ids) async {
    await prefs.setStringList(_ordemHinariosKey, ids);
  }

  static List<String> get ordemDosHinarios =>
      prefs.getStringList(_ordemHinariosKey) ?? const <String>[];

  /// Em que ordem a lista de hinos aparece, dentro de qualquer hinário.
  static Future<void> salvarOrdemDosHinos(String id) async {
    await prefs.setString(_ordemHinosKey, id);
  }

  static String? get ordemDosHinos => prefs.getString(_ordemHinosKey);

  // ─── As mesmas escolhas, POR PESSOA ───────────────────────────────────────
  //
  // O aparelho é de quem está com ele na mão, mas no computador da igreja
  // quem usa muda: a ordem que a Ana escolheu não é a do Bruno. A chave leva o
  // id de quem está logado, e quem nunca escolheu nada herda o que estava
  // gravado antes disto existir — senão todo mundo voltaria para "pelo
  // número" sem ninguém ter mexido em nada.

  static String _chaveDe(String base, String? usuario) =>
      (usuario == null || usuario.isEmpty) ? base : '${base}_$usuario';

  static Future<void> salvarOrdemDosHinosDe(String? usuario, String id) async {
    await prefs.setString(_chaveDe(_ordemHinosKey, usuario), id);
  }

  static String? ordemDosHinosDe(String? usuario) =>
      prefs.getString(_chaveDe(_ordemHinosKey, usuario)) ?? ordemDosHinos;

  static Future<void> salvarOrdemDosHinariosDe(
      String? usuario, List<String> ids) async {
    await prefs.setStringList(_chaveDe(_ordemHinariosKey, usuario), ids);
  }

  static List<String> ordemDosHinariosDe(String? usuario) =>
      prefs.getStringList(_chaveDe(_ordemHinariosKey, usuario)) ??
      ordemDosHinarios;

  // ─── As letras dos hinários, no aparelho ──────────────────────────────────
  //
  // Para a busca "por um trecho da letra" funcionar sem custo. Cada hinário
  // fica numa chave só, como um texto JSON (número → letra), com a MARCA da
  // importação de que veio: quando o líder importa de novo, a marca muda e o
  // que está aqui deixa de valer. Mora no aparelho, não no Firestore: é uma
  // cópia de leitura, e no banco custaria 640 leituras a cada pessoa.

  static String _letrasKey(String hinario) => 'letras_hinario_$hinario';

  static Future<void> salvarLetrasDoHinario(
      String hinario, Map<int, String> letras, String marca) async {
    final corpo = jsonEncode({
      'marca': marca,
      'letras': {for (final e in letras.entries) '${e.key}': e.value},
    });
    await prefs.setString(_letrasKey(hinario), corpo);
  }

  /// As letras guardadas e a marca de que vieram, ou nulo se não há (ou se o
  /// que há está estragado: lê-se como "nunca baixou", que é o seguro).
  static ({Map<int, String> letras, String marca})? letrasDoHinario(
      String hinario) {
    final bruto = prefs.getString(_letrasKey(hinario));
    if (bruto == null || bruto.isEmpty) return null;
    try {
      final d = jsonDecode(bruto);
      if (d is! Map || d['letras'] is! Map || d['marca'] is! String) {
        return null;
      }
      final saida = <int, String>{};
      (d['letras'] as Map).forEach((k, v) {
        final n = int.tryParse('$k');
        if (n != null && v is String) saida[n] = v;
      });
      return (letras: saida, marca: d['marca'] as String);
    } catch (_) {
      return null;
    }
  }

  static Future<void> esquecerLetrasDoHinario(String hinario) async {
    await prefs.remove(_letrasKey(hinario));
  }

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
    final chave = '$hinario|$numero';
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

  static bool isSongOffline(String songId) => _offlineCache.containsKey(songId);

  static int get offlineCount => _offlineCache.length;

  static List<SongModel> get offlineSongsList => _offlineCache.values.toList();
}
