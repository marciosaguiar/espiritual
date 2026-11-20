import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../../core/platform/marcas.dart';
import '../../data/models/scale_model.dart';
import '../../data/models/song_model.dart';
import '../../data/services/firestore_service.dart';
import '../../data/services/local_storage_service.dart';
import '../../core/constants/hinarios.dart';
import '../../core/utils/texto.dart';

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
  List<SongModel> get repertorio => _songs.where((s) => !s.archived).toList();
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

  /// Põe músicas na memória sem falar com o banco. Só os testes e o roteiro de
  /// captura de telas usam: é o que permite fotografar o app com o repertório
  /// do tamanho do ministério sem emulador nenhum.
  @visibleForTesting
  void carregarParaTeste(List<SongModel> musicas) {
    _songs = musicas;
    _isLoading = false;
    _error = null;
    _applyFilter();
    notifyListeners();
  }

  void listenToSongs() {
    // Guard against stacking multiple subscriptions (e.g. re-login).
    if (_songsSub != null) return;
    _isLoading = true;
    _songsSub = FirestoreService.watchSongs().listen((songs) {
      if (_songs.isEmpty) marcar('musicas-recebidas');
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

  // ─── Quais músicas já têm cifra pronta ────────────────────────────────────
  //
  // A cifra mora no ARRANJO (`songs/{id}/arrangements`), e é isso que impede
  // o app de baixar o repertório inteiro de cifras só para abrir a lista de
  // músicas. O preço é que, para saber quais músicas têm cifra, alguém tem de
  // perguntar.
  //
  // A pergunta é feita UMA VEZ POR SESSÃO, e só quando o líder abre o diálogo
  // de escolher as músicas do culto — não na abertura do app, não na lista de
  // músicas, não para quem não é líder. São ~40 leituras no ministério de
  // hoje, de 50 mil por dia, numa tela que se abre de propósito.
  //
  // A alternativa seria um campo `temCifra` na música, escrito ao salvar o
  // arranjo. Foi descartada por causa dos dados que JÁ EXISTEM: música com
  // cifra cadastrada antes do campo apareceria como "sem cifra", e o líder
  // montaria o culto com uma informação errada — justamente o contrário do
  // que o ícone promete.

  Set<String> _comCifra = const {};
  bool _cifrasConferidas = false;
  Future<void>? _conferindo;

  /// Já sabemos quais músicas têm cifra? Enquanto for falso, a tela não
  /// desenha ícone nenhum: ausência de ícone não pode significar "sem cifra"
  /// quando a resposta ainda não chegou.
  bool get cifrasConferidas => _cifrasConferidas;

  bool temCifra(String songId) => _comCifra.contains(songId);

  /// Pergunta ao banco quais músicas do repertório têm arranjo com cifra.
  ///
  /// Chamar de novo na mesma sessão não custa nada: a resposta fica guardada,
  /// e duas aberturas seguidas do diálogo compartilham a mesma consulta.
  Future<void> conferirCifras() async {
    if (_cifrasConferidas) return;
    if (_conferindo != null) return _conferindo;

    _conferindo = (() async {
      final achadas = <String>{};
      final musicas = repertorio;
      // Em blocos, e não todas de uma vez: 300 consultas em paralelo num
      // celular ruim é pedido de timeout.
      const bloco = 10;
      for (var i = 0; i < musicas.length; i += bloco) {
        final parte = musicas.skip(i).take(bloco);
        final respostas = await Future.wait(parte.map((m) async {
          final arranjos = await FirestoreService.getArrangements(m.id);
          final tem = arranjos.any((a) => a.chords.trim().isNotEmpty);
          return tem ? m.id : '';
        }));
        achadas.addAll(respostas.where((id) => id.isNotEmpty));
      }
      _comCifra = achadas;
      _cifrasConferidas = true;
      notifyListeners();
    })();

    try {
      await _conferindo;
    } catch (_) {
      // Leitura com valor padrão seguro: sem a resposta, a tela não mostra
      // ícone nenhum, e o líder escolhe as músicas como escolhia antes.
    } finally {
      _conferindo = null;
    }
  }

  // ─── Hino pelo número ─────────────────────────────────────────────────────
  //
  // O caso principal do hinário: o dirigente anuncia "hino 15 da Harpa" e
  // quem vai tocar precisa chegar à cifra em segundos, sem procurar pelo
  // nome. As duas primeiras funções são PURAS e recebem a lista, como
  // `ScaleProvider.aindaVale` recebe `agora`: é conta sobre dados, e conta
  // sobre dados tem de dar para testar sem Flutter em volta.

  /// O hino com este número nesta lista, ou nulo.
  ///
  /// Procura pelos CAMPOS `hinario` e `numero`, nunca pelo texto do título.
  /// O título traz a sigla ("HC 15 · …") para quem lê a tela; se a busca
  /// dependesse dele, um líder corrigindo o nome quebraria o teclado numérico
  /// sem ter como saber por quê.
  static SongModel? acharHino(
      List<SongModel> musicas, String hinario, int numero) {
    for (final m in musicas) {
      if (m.hinario == hinario && m.numero == numero) return m;
    }
    return null;
  }

  /// Os hinos daquele hinário que combinam com a busca.
  ///
  /// A busca ignora acento e alcança o número, o nome, o artista e a LETRA —
  /// é o "lembro do trecho mas não do número", que é como a maioria das
  /// pessoas procura hino. **Filtrar e ordenar são coisas separadas**: a
  /// busca funciona igual em qualquer ordem, porque a ordem é aplicada depois
  /// (ver [hinosOrdenados]).
  static List<SongModel> hinosFiltrados(
      List<SongModel> musicas, String hinario, String busca) {
    final achados = musicas
        .where((m) => m.hinario == hinario && m.numero != null)
        .where(
            (m) => combina(busca, [m.name, m.artist, m.lyrics, '${m.numero}']))
        .toList();
    achados.sort((a, b) => a.numero!.compareTo(b.numero!));
    return achados;
  }

  /// Os mesmos hinos, na ordem que a pessoa escolheu.
  ///
  /// Recebe tudo de fora (a contagem dos cultos, a lista de favoritas) e não
  /// lê provider nenhum: é a parte que erra em silêncio — uma lista fora de
  /// ordem não dá erro, só faz a pessoa não achar o hino — e por isso tem de
  /// ser testável sem app.
  ///
  /// **O número é sempre o desempate.** Em "mais tocados", dois hinos com a
  /// mesma contagem (o caso comum: zero) sairiam em ordem indefinida, e a
  /// lista dançaria a cada abertura. Mesma regra do repertório, em "Escolher
  /// as músicas do culto".
  static List<SongModel> hinosOrdenados(
    List<SongModel> hinos,
    OrdemDosHinos ordem, {
    Map<String, int> vezesTocadas = const {},
    Set<String> favoritas = const {},
  }) {
    final saida = List<SongModel>.from(hinos);
    int porNumero(SongModel a, SongModel b) =>
        (a.numero ?? 0).compareTo(b.numero ?? 0);

    switch (ordem) {
      case OrdemDosHinos.numero:
        saida.sort(porNumero);
      case OrdemDosHinos.nome:
        // Duas coisas, e as duas foram vistas na tela:
        //
        // · sem a sigla e o número do título ("HC 15 · "), senão isto ordena
        //   pelo número de novo e a opção parece não fazer nada;
        // · sem acento e sem maiúscula, senão "Ó Vem" cai depois de "Zelo",
        //   porque o código do "Ó" é maior que o de qualquer letra comum.
        saida.sort((a, b) {
          final c = nomeComparavel(nomeSemHinario(a.name))
              .compareTo(nomeComparavel(nomeSemHinario(b.name)));
          return c != 0 ? c : porNumero(a, b);
        });
      case OrdemDosHinos.nomeDescendente:
        saida.sort((a, b) {
          final c = nomeComparavel(nomeSemHinario(b.name))
              .compareTo(nomeComparavel(nomeSemHinario(a.name)));
          return c != 0 ? c : porNumero(a, b);
        });
      case OrdemDosHinos.maisTocados:
        saida.sort((a, b) {
          final c =
              (vezesTocadas[b.id] ?? 0).compareTo(vezesTocadas[a.id] ?? 0);
          return c != 0 ? c : porNumero(a, b);
        });
      case OrdemDosHinos.favoritos:
        saida.sort((a, b) {
          final fa = favoritas.contains(a.id) ? 0 : 1;
          final fb = favoritas.contains(b.id) ? 0 : 1;
          return fa != fb ? fa.compareTo(fb) : porNumero(a, b);
        });
    }
    return saida;
  }

  /// O hino do repertório de hoje, ou nulo.
  SongModel? hinoPorNumero(String hinario, int numero) =>
      acharHino(repertorio, hinario, numero);

  /// O hino mesmo que esteja FORA do repertório.
  ///
  /// Existe para a tela poder dizer "está fora do repertório" em vez de
  /// "ainda não está cadastrado". São coisas diferentes, e confundi-las faria
  /// o líder cadastrar de novo um hino que já existe — criando duplicata e
  /// perdendo a cifra que alguém já tinha colado.
  SongModel? hinoCadastrado(String hinario, int numero) =>
      acharHino(allSongs, hinario, numero);

  /// Os hinos daquele hinário no repertório de hoje.
  List<SongModel> hinosDe(String hinario, {String busca = ''}) =>
      hinosFiltrados(repertorio, hinario, busca);

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
