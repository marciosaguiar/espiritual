import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../../core/platform/marcas.dart';
import '../../core/utils/crypto_utils.dart';
import '../../core/utils/fila_de_envio.dart';
import '../../core/utils/fusao_de_edicao.dart';
import '../../core/utils/origem_do_dado.dart';
import '../../core/utils/snapshot_local.dart';
import '../../data/models/arrangement_model.dart';
import '../../data/models/scale_model.dart';
import '../../data/models/song_model.dart';
import '../../data/services/fila_service.dart';
import '../../data/services/modo_economia.dart';
import '../../data/services/firestore_service.dart';
import '../../data/services/local_storage_service.dart';
import '../../core/constants/hinarios.dart';
import '../../core/utils/texto.dart';

enum SongsFilter { all, favorites, offline, arquivadas }

class SongsProvider extends ChangeNotifier {
  SongsProvider({
    FilaDeEnvio? fila,
    Future<({List<SongModel> itens, bool doServidor})?> Function()? lerRepertorio,
    Future<({SongModel? musica, bool respondeu})> Function(String id)? lerPorId,
  })  : _fila = fila ?? FilaService.fila,
        _lerRepertorio = lerRepertorio ?? FirestoreService.lerMusicasUmaVez,
        _lerPorId = lerPorId ?? FirestoreService.lerMusicaPorId {
    _fila.addListener(_aoMudarAFila);
  }

  final Future<({List<SongModel> itens, bool doServidor})?> Function()
      _lerRepertorio;
  final Future<({SongModel? musica, bool respondeu})> Function(String id)
      _lerPorId;

  /// Tem banco de verdade por trás? Falso nas telas de teste e na captura de
  /// telas, onde ninguém deve tentar ler do Firestore.
  bool _semBanco = false;

  final FilaDeEnvio _fila;

  /// As músicas como o BANCO as mandou. [_songs] é isto com as edições que
  /// ainda esperam a internet por cima: a tela mostra o que a pessoa fez, e
  /// uma resposta nova do banco não desfaz isso.
  List<SongModel> _servidor = [];
  List<SongModel> _songs = [];
  List<SongModel> _filteredSongs = [];
  SongsFilter _filter = SongsFilter.all;
  String _searchQuery = '';
  bool _isLoading = false;
  String? _error;
  List<String> _favoriteSongIds = [];

  StreamSubscription<({List<SongModel> itens, bool doCache})>? _songsSub;

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
    _semBanco = true;
    _servidor = musicas;
    _songs = _comPendencias(musicas);
    _isLoading = false;
    _error = null;
    _applyFilter();
    notifyListeners();
  }

  /// Até quando o repertório que está no aparelho dispensa ir ao servidor.
  ///
  /// **O repertório é lido POR NECESSIDADE, não a cada abertura.** Ele já foi
  /// uma escuta sempre ligada, e depois uma leitura a cada abertura do app — e
  /// as duas custam o repertório INTEIRO (uma leitura por música) toda vez,
  /// para saber de uma lista que quase nunca muda. O custo cresce com o
  /// tamanho do repertório: 40 músicas passam despercebidas, 300 gastam sozinhas
  /// um quinto da cota do dia só em abrir o app seis vezes.
  ///
  /// Agora o Início NÃO lê a lista: cada música de um culto é resolvida pelo id
  /// (`getSongById` pede a que falta) e a lista inteira só vem quando alguém
  /// precisa dela — a aba Músicas, o cadastro (para avisar de duplicata), a
  /// escolha das músicas de um culto, o teclado de hinos — e, em segundo plano,
  /// pela preparação do app. Chegando, vale por [prazoDasMusicas]. A própria
  /// pessoa que grava vê a música na hora (`musicasGravadas`).
  ///
  /// O que se perde: uma música cadastrada por OUTRA pessoa só aparece na LISTA
  /// no próximo prazo ou quando se toca em "Atualizar a lista". Num culto ela
  /// aparece de qualquer jeito, porque o culto a resolve pelo id.
  static const Duration prazoDasMusicas = Duration(hours: 12);

  DateTime? _musicasEm;
  bool _atualizandoMusicas = false;
  StreamSubscription<SongModel>? _gravadasSub;
  Set<String> _musicasPendentes = {};

  /// Ids já respondidos pelo banco como "não existe" (nesta sessão).
  final Set<String> _naoExistem = {};

  /// Ids que estão sendo buscados agora, e quando a última tentativa falhou
  /// (para não insistir a cada quadro desenhado).
  final Set<String> _buscando = {};
  final Map<String, DateTime> _falhouEm = {};
  static const Duration esperaDepoisDeFalhar = Duration(minutes: 2);

  void listenToSongs({Stream<({List<SongModel> itens, bool doCache})>? fonte}) {
    _gravadasSub ??= FirestoreService.musicasGravadas.listen(registrarLocal);
    // Sem fonte (o app de verdade) NÃO se lê nada aqui: ver `prazoDasMusicas`.
    if (fonte == null) return;
    // Guard against stacking multiple subscriptions (e.g. re-login).
    if (_songsSub != null) return;
    _isLoading = true;
    _songsSub = fonte.listen((r) {
      // Vazio vindo do cache não é resposta: não apaga o que está na tela.
      if (ignorarVazioDoCache(
          doCache: r.doCache, vazio: r.itens.isEmpty, jaTemDados: _servidor.isNotEmpty)) {
        return;
      }
      if (_songs.isEmpty) marcar('musicas-recebidas');
      _servidor = r.itens;
      _songs = _comPendencias(r.itens);
      _isLoading = false;
      _error = null;
      // A cópia só se regrava com o que o SERVIDOR confirmou.
      if (!r.doCache) _guardarNoAparelho();
      _applyFilter();
      notifyListeners();
    }, onError: (e) {
      _isLoading = false;
      _error = 'Erro ao carregar músicas';
      notifyListeners();
    });
  }

  /// A lista INTEIRA já foi lida (ou restaurada de uma cópia inteira)?
  ///
  /// Não é o mesmo que "há músicas na memória": o Início traz músicas soltas,
  /// pelo id, e uma lista de três não é o repertório. É isto que decide se a
  /// cópia vale mais [prazoDasMusicas].
  bool get repertorioCompleto => _musicasEm != null;

  /// Relê o repertório do servidor se a cópia passou de [prazoDasMusicas] (ou
  /// não existe). Em modo de economia não relê, a não ser que não haja nada na
  /// tela. [forcar] ignora o prazo — é o botão "Atualizar a lista".
  Future<void> atualizarSeVelho({bool forcar = false, DateTime? agora}) async {
    if (_atualizandoMusicas || _semBanco) return;
    final t = agora ?? DateTime.now();
    final temAlgo = _servidor.isNotEmpty;
    if (!forcar) {
      // Em modo de economia a lista inteira (uma leitura por música) espera
      // amanhã, a não ser que não haja música nenhuma na tela.
      if (temAlgo && ModoEconomia.instancia.ligado) return;
      if (_musicasEm != null && t.difference(_musicasEm!) < prazoDasMusicas) {
        if (_isLoading) {
          _isLoading = false;
          notifyListeners();
        }
        return;
      }
    }
    _atualizandoMusicas = true;
    if (!temAlgo) {
      _isLoading = true;
      notifyListeners();
    }
    try {
      final r = await _lerRepertorio();
      if (r == null) {
        // Sem resposta: fica com o que há — e só vira erro se não há nada.
        _isLoading = false;
        if (!temAlgo) _error = 'Erro ao carregar músicas';
        notifyListeners();
        return;
      }
      if (ignorarVazioDoCache(
          doCache: !r.doServidor, vazio: r.itens.isEmpty, jaTemDados: temAlgo)) {
        _isLoading = false;
        notifyListeners();
        return;
      }
      if (_songs.isEmpty) marcar('musicas-recebidas');
      _servidor = r.itens;
      _songs = _comPendencias(r.itens);
      _isLoading = false;
      _error = null;
      if (r.doServidor) {
        _musicasEm = t;
        _guardarNoAparelho();
      }
      _applyFilter();
      notifyListeners();
    } finally {
      _atualizandoMusicas = false;
    }
  }

  // ─── uma música por id: é assim que o Início resolve os cultos ────────────

  /// Pede ao banco a música [id], se ela não está na memória. Idempotente e
  /// barata de chamar a cada quadro: já buscando, já confirmada como inexistente
  /// ou falha recente não fazem nada.
  void _pedirPorId(String id) {
    if (_semBanco || id.isEmpty) return;
    if (_naoExistem.contains(id) || _buscando.contains(id)) return;
    final f = _falhouEm[id];
    if (f != null && DateTime.now().difference(f) < esperaDepoisDeFalhar) return;
    _buscando.add(id);
    // Fora do `build` que a pediu: notificar de dentro dele é erro do Flutter.
    scheduleMicrotask(() => unawaited(_buscarPorId(id)));
  }

  Future<void> _buscarPorId(String id) async {
    try {
      final r = await _lerPorId(id);
      final m = r.musica;
      if (m != null) {
        _falhouEm.remove(id);
        _servidor = [..._servidor.where((x) => x.id != id), m]
          ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        _songs = _comPendencias(_servidor);
        _applyFilter();
        _guardarNoAparelho();
      } else if (r.respondeu) {
        _naoExistem.add(id);
      } else {
        _falhouEm[id] = DateTime.now();
      }
    } catch (_) {
      _falhouEm[id] = DateTime.now();
    } finally {
      _buscando.remove(id);
      notifyListeners();
    }
  }

  /// Traz de uma vez as músicas [ids] que faltam (a tela do culto sabe quais).
  Future<void> garantirMusicas(Iterable<String> ids) async {
    for (final id in ids) {
      if (_songs.any((s) => s.id == id)) continue;
      _pedirPorId(id);
    }
  }

  /// Uma música gravada por este aparelho entra na lista na hora.
  void registrarLocal(SongModel s) {
    _servidor = [..._servidor.where((x) => x.id != s.id), s]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    _songs = _comPendencias(_servidor);
    _applyFilter();
    _guardarNoAparelho();
    notifyListeners();
  }

  /// Relê UMA música (1 leitura) e a troca na lista: o que se faz quando uma
  /// edição saiu da fila, para a tela mostrar o que ficou no banco.
  Future<void> _recarregarMusica(String id) async {
    final m = (await _lerPorId(id)).musica;
    if (m == null) return;
    _servidor = [for (final x in _servidor) x.id == id ? m : x];
    _songs = _comPendencias(_servidor);
    _applyFilter();
    _guardarNoAparelho();
    notifyListeners();
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
    // A música entra na lista pelo `musicasGravadas` (ver `listenToSongs`).
    final result = await FirestoreService.addSong(song);
    return result.error;
  }

  /// Os campos da música que "Editar música" e "Editar cifra" mexem. A fila
  /// grava SÓ estes, um a um (ver `fusao_de_edicao.dart`): gravar a música
  /// inteira desfaria, de carona, o que outra pessoa mudou nos campos que a
  /// primeira nem tocou.
  static const List<String> camposEditaveis = [
    'name',
    'artist',
    'lyrics',
    'originalKey',
    'links',
    'observacoes',
  ];

  /// Quais campos [novo] muda em relação a [base]. Função pura.
  static Map<String, CampoEditado> camposQueMudaram(
      SongModel base, SongModel novo) {
    final antes = base.toFirestore();
    final depois = novo.toFirestore();
    return {
      for (final c in camposEditaveis)
        if (!valoresIguais(antes[c], depois[c]))
          c: CampoEditado(base: antes[c], novo: depois[c]),
    };
  }

  /// A música com as edições [campos] por cima. Função pura.
  static SongModel comEdicoes(SongModel base, Map<String, CampoEditado> campos) {
    if (campos.isEmpty) return base;
    return SongModel.fromFirestore({
      ...base.toFirestore(),
      for (final e in campos.entries) e.key: e.value.novo,
    });
  }

  /// Altera uma música. Devolve null quando deu certo OU quando ficou
  /// esperando a internet (a música já aparece alterada, com o relógio);
  /// devolve a frase quando o banco recusou.
  Future<String?> updateSong(SongModel song) async {
    final atual = _songs.where((s) => s.id == song.id).firstOrNull;
    if (atual == null) return 'Esta música não está mais na lista.';
    final campos = camposQueMudaram(atual, song);
    if (campos.isEmpty) return null;

    final r = await _fila.enfileirar(ItemDaFila.edicao(
      id: CryptoUtils.generateId(),
      tipo: TipoDeAcao.musica,
      songId: song.id,
      campos: campos,
      agora: DateTime.now(),
      extra: {'rotulo': atual.name},
    ));
    if (r != null && r.desfecho == Desfecho.descartado) return r.erro;
    return null;
  }

  /// Esta música tem alteração esperando para ser enviada?
  bool musicaPendente(String songId) => _fila.temPendencia('musica:$songId');

  /// Esta cifra (arranjo) tem alteração esperando?
  bool arranjoPendente(String songId) => _fila.temPendencia('arranjo:$songId');

  /// Grava campos do arranjo (cifra, tom da igreja, BPM, aprovação).
  ///
  /// Devolve o arranjo COMO FICOU na tela — com a alteração por cima, mesmo
  /// que ainda esteja esperando a internet — e o erro, se o banco recusou.
  /// Quando o arranjo ainda não existe, [seNaoExistir] é o que será criado.
  Future<({ArrangementModel? arranjo, String? erro, bool pendente})>
      salvarArranjo({
    required String songId,
    required ArrangementModel? atual,
    required ArrangementModel seNaoExistir,
    required Map<String, dynamic> novos,
    required String rotulo,
  }) async {
    final base = atual ?? seNaoExistir;
    final antes = base.toFirestore();
    final campos = {
      for (final e in novos.entries)
        if (!valoresIguais(antes[e.key], e.value))
          e.key: CampoEditado(base: antes[e.key], novo: e.value),
    };
    final naTela = comEdicoesDoArranjo(base, campos);
    if (campos.isEmpty && atual != null) {
      return (arranjo: atual, erro: null, pendente: false);
    }
    final r = await _fila.enfileirar(ItemDaFila.edicao(
      id: CryptoUtils.generateId(),
      tipo: TipoDeAcao.arranjo,
      songId: songId,
      campos: campos,
      agora: DateTime.now(),
      extra: {
        'arranjoId': base.id,
        'rotulo': rotulo,
        // Só vai junto quando o arranjo ainda não existe no banco.
        if (atual == null) 'criar': seNaoExistir.toJson(),
      },
    ));
    if (r != null && r.desfecho == Desfecho.descartado) {
      return (arranjo: null, erro: r.erro, pendente: false);
    }
    return (arranjo: naTela, erro: null, pendente: r == null);
  }

  /// O arranjo com as edições [campos] por cima. Função pura.
  static ArrangementModel comEdicoesDoArranjo(
      ArrangementModel base, Map<String, CampoEditado> campos) {
    if (campos.isEmpty) return base;
    return ArrangementModel.fromFirestore({
      ...base.toFirestore(),
      for (final e in campos.entries) e.key: e.value.novo,
    });
  }

  /// O arranjo [a] com o que ainda espera na fila por cima.
  ArrangementModel? arranjoComPendencias(String songId, ArrangementModel? a) {
    final item = _fila.daChave('arranjo:$songId');
    if (item == null) return a;
    if (a == null) {
      final criar = item.dados['criar'];
      if (criar == null) return null;
      a = ArrangementModel.fromJson(Map<String, dynamic>.from(criar as Map));
    }
    return comEdicoesDoArranjo(a, item.campos);
  }

  // ─── o que está na fila, por cima do que veio do banco ───────────────────

  void _aoMudarAFila() {
    // Uma edição que SAIU da fila foi enviada (ou recusada): relê só aquela
    // música, para a tela deixar de mostrar o "por cima" e mostrar o banco.
    final agora = _fila.itens
        .where((i) => i.tipo == TipoDeAcao.musica)
        .map((i) => i.dados['songId'] as String)
        .toSet();
    for (final id in _musicasPendentes.difference(agora)) {
      unawaited(_recarregarMusica(id));
    }
    _musicasPendentes = agora;
    _songs = _comPendencias(_servidor);
    _applyFilter();
    notifyListeners();
  }

  List<SongModel> _comPendencias(List<SongModel> base) {
    final pendentes = _fila.itens
        .where((i) => i.tipo == TipoDeAcao.musica)
        .toList();
    if (pendentes.isEmpty) return base;
    final porId = {for (final i in pendentes) i.dados['songId'] as String: i};
    return [
      for (final s in base)
        porId.containsKey(s.id) ? comEdicoes(s, porId[s.id]!.campos) : s,
    ];
  }

  // ─── cópia no aparelho: abrir já com o repertório na tela ────────────────

  Timer? _relogioDaCopia;

  void _guardarNoAparelho() {
    _relogioDaCopia?.cancel();
    _relogioDaCopia = Timer(const Duration(seconds: 2), () {
      final docs = _servidor.map((s) => s.toFirestore()).toList();
      if (_musicasEm != null) {
        // Lista inteira: guarda com a hora da ÚLTIMA leitura completa, e não
        // com a de agora. Uma música acrescentada à mão não torna a lista
        // "recém-lida" — e estender o prazo assim esconderia as músicas que
        // OUTRAS pessoas cadastraram.
        SnapshotLocal.guardar('songs', docs, agora: _musicasEm);
      } else {
        // Só as músicas soltas que o Início buscou: outra cópia, para a lista
        // incompleta nunca passar por inteira na próxima abertura.
        SnapshotLocal.guardar('songs-avulsas', docs);
      }
    });
  }

  /// Põe na tela o repertório que o aparelho guardou da última vez, ANTES de o
  /// banco responder (e antes de o Firebase terminar de ligar). Devolve
  /// quantas músicas eram.
  Future<int> restaurarDoAparelho() async {
    if (_servidor.isNotEmpty) return 0;
    final inteira = await SnapshotLocal.ler('songs');
    final avulsas = await SnapshotLocal.ler('songs-avulsas');
    if (inteira == null && avulsas == null) return 0;
    try {
      final lista = <SongModel>[
        for (final d in inteira ?? const <Map<String, dynamic>>[])
          SongModel.fromFirestore(d),
      ];
      // As soltas entram só se a lista inteira não as tem.
      for (final d in avulsas ?? const <Map<String, dynamic>>[]) {
        final m = SongModel.fromFirestore(d);
        if (!lista.any((x) => x.id == m.id)) lista.add(m);
      }
      _servidor = lista;
    } catch (_) {
      return 0; // cópia ilegível: o banco responde quando alguém pedir
    }
    _musicasEm = inteira == null ? null : await SnapshotLocal.quando('songs');
    _songs = _comPendencias(_servidor);
    _isLoading = false;
    _error = null;
    _applyFilter();
    notifyListeners();
    return _servidor.length;
  }

  @override
  void dispose() {
    _fila.removeListener(_aoMudarAFila);
    _gravadasSub?.cancel();
    _relogioDaCopia?.cancel();
    _songsSub?.cancel();
    super.dispose();
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
    unawaited(_recarregarMusica(songId));
    return null;
  }

  Future<String?> desarquivar(String songId) async {
    final r = await FirestoreService.desarquivarSong(songId);
    if (r.success) unawaited(_recarregarMusica(songId));
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

  /// A música [id], ou nulo. Se não está na memória, PEDE ao banco (uma
  /// leitura) e avisa quando chegar: é assim que o Início mostra as músicas de
  /// um culto sem ter baixado o repertório inteiro.
  SongModel? getSongById(String id) {
    for (final s in _songs) {
      if (s.id == id) return s;
    }
    _pedirPorId(id);
    return null;
  }

  /// Repertoire suggestion. Seeded by the current day so the list stays
  /// stable across rebuilds (it no longer reshuffles on every frame).
  // ─── Resolving service references ─────────────────────────────────────────
  // A service stores only ids, so these turn a reference into what to show.
  // Correcting a song now corrects every service that uses it.

  /// Name to show for a referenced song.
  ///
  /// Enquanto a música vem do banco diz "Carregando…", e "Música removida" só
  /// depois de o banco responder que não existe — dizer "removida" no meio do
  /// caminho assustaria quem acabou de abrir o app. Se não deu para perguntar
  /// (sem internet), diz "ainda não baixada", que é o que é.
  String nameOf(ScaleSong ref) {
    final m = getSongById(ref.songId);
    if (m != null) return m.name;
    if (_semBanco || _naoExistem.contains(ref.songId)) return 'Música removida';
    if (_falhouEm.containsKey(ref.songId)) return 'Música ainda não baixada';
    return 'Carregando…';
  }

  /// Artist to show, empty when unknown.
  String artistOf(ScaleSong ref) => getSongById(ref.songId)?.artist ?? '';

  /// Key to show: the service's own key when it sets one, else the song's.
  String keyOf(ScaleSong ref) {
    if (ref.keyOverride.isNotEmpty) return ref.keyOverride;
    return getSongById(ref.songId)?.originalKey ?? '?';
  }

  /// Whether the referenced song still exists in the repertoire.
  ///
  /// "Ainda não sei" conta como existe: só é "faltando" quando o banco
  /// confirmou que não há — senão toda tela de culto piscaria o aviso de
  /// música faltando enquanto as músicas chegam.
  bool exists(ScaleSong ref) {
    if (getSongById(ref.songId) != null) return true;
    return !(_semBanco || _naoExistem.contains(ref.songId));
  }

  List<SongModel> suggestRepertoire({int count = 6}) {
    if (repertorio.isEmpty) return const [];
    final now = DateTime.now();
    final seed = now.year * 10000 + now.month * 100 + now.day;
    final shuffled = List<SongModel>.from(repertorio)..shuffle(Random(seed));
    return shuffled.take(count).toList();
  }
}
