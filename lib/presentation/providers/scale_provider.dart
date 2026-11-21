import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../core/platform/marcas.dart';
import '../../core/utils/crypto_utils.dart';
import '../../core/utils/fila_de_envio.dart';
import '../../core/utils/origem_do_dado.dart';
import '../../core/utils/snapshot_local.dart';
import '../../data/models/scale_model.dart';
import '../../data/models/team_model.dart';
import '../../data/services/fila_service.dart';
import '../../data/services/modo_economia.dart';
import '../../data/services/firestore_service.dart';

class ScaleProvider extends ChangeNotifier {
  ScaleProvider({FilaDeEnvio? fila}) : _fila = fila ?? FilaService.fila {
    _fila.addListener(_aoMudarAFila);
  }

  final FilaDeEnvio _fila;

  /// Os cultos como o BANCO os mandou. [_scales] é isto mais o que a pessoa
  /// fez e ainda não chegou lá (presença pendente): a tela mostra o segundo, e
  /// uma resposta nova do banco não pode desfazer o primeiro.
  List<ScaleModel> _servidor = [];
  List<ScaleModel> _scales = [];
  ScaleModel? _selectedScale;
  bool _isLoading = false;
  String? _error;


  List<ScaleModel> get scales => _scales;
  ScaleModel? get selectedScale => _selectedScale;
  bool get isLoading => _isLoading;
  String? get error => _error;

  // ─── janelas de leitura ───────────────────────────────────────────────────
  //
  // Os cultos NÃO vêm todos de uma vez. A escuta de sempre pegava de 60 dias
  // atrás a 90 à frente (~110 documentos, ~45% do que uma abertura fria custava)
  // para mostrar, no Início, um cartão com o próximo culto. Agora há uma janela
  // BASE curta, sempre ligada — de 2 dias atrás a 28 à frente, ~20 documentos —
  // e as outras abrem por demanda: o mês que a pessoa vê no calendário e o
  // histórico de 60 dias que só a escolha de músicas e "mais tocados" usam.
  //
  // `_servidor` é a união do que cada janela respondeu, por cima do que veio do
  // aparelho: um documento do aparelho dentro de uma janela que já respondeu é
  // substituído pela resposta (o servidor manda), e um fora de toda janela fica.

  final Map<String, _Janela> _janelas = {};
  String? _chaveDaBase;
  DateTime? _diaDaBase;

  /// Ligado por `carregarParaTeste`: não há banco, então as janelas por demanda
  /// (calendário, histórico) não abrem escuta nenhuma.
  bool _semBanco = false;

  /// O que veio do aparelho (e o que se criou aqui), por baixo das janelas.
  List<ScaleModel> _restaurados = [];

  static String _chaveDa(DateTime i, DateTime f) =>
      '${i.year}-${i.month}-${i.day}:${f.year}-${f.month}-${f.day}';

  /// Liga a janela BASE. [fonte] só os testes trocam: é o que permite provar o
  /// que o provider faz com um vazio do cache sem ter um Firestore.
  void listenToScales({Stream<({List<ScaleModel> itens, bool doCache})>? fonte}) {
    if (_chaveDaBase != null) return;
    final agora = DateTime.now();
    _diaDaBase = DateTime(agora.year, agora.month, agora.day);
    _chaveDaBase = _abrirJanela(
      FirestoreService.inicioDaJanelaBase(agora),
      FirestoreService.fimDaJanelaBase(agora),
      fonte: fonte,
    );
  }

  /// Garante que o intervalo está sendo lido. Barato quando já está.
  void garantirJanela(DateTime inicio, DateTime fim) {
    _abrirJanela(inicio, fim);
  }

  /// O mês do calendário que a pessoa está vendo.
  void garantirMes(DateTime mes) {
    garantirJanela(DateTime(mes.year, mes.month, 1),
        DateTime(mes.year, mes.month + 1, 0, 23, 59, 59));
  }

  /// Os 60 dias de histórico, para "tocada em…" e "mais tocados". Em modo de
  /// economia não se abre: é conforto, não necessidade.
  ///
  /// Devolve quando o servidor responde (ou em [espera], o que vier primeiro):
  /// quem monta uma lista logo em seguida precisa dos cultos, não da promessa.
  Future<void> garantirHistorico(
      {Duration espera = const Duration(seconds: 4)}) async {
    if (ModoEconomia.instancia.ligado || _semBanco) return;
    final agora = DateTime.now();
    final ini = DateTime(agora.year, agora.month, agora.day)
        .subtract(FirestoreService.janelaPassado);
    final fim = DateTime(agora.year, agora.month, agora.day);
    final chave = _abrirJanela(ini, fim);
    final j = _janelas[chave]!;
    final limite = DateTime.now().add(espera);
    while (j.itens == null && DateTime.now().isBefore(limite)) {
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }
  }

  /// Os cultos de hoje até [FirestoreService.janelaFuturo] (90 dias), que é até
  /// onde um culto pode existir. A janela BASE só vai a 4 semanas; quem precisa
  /// do futuro INTEIRO — tirar uma pessoa de todos os cultos em que ela está —
  /// pede isto antes, para não deixá-la escalada num culto que o app não leu.
  /// Devolve quando o servidor responde (ou em [espera]).
  Future<void> garantirFuturo(
      {Duration espera = const Duration(seconds: 6)}) async {
    if (_semBanco) return;
    final agora = DateTime.now();
    final hoje = DateTime(agora.year, agora.month, agora.day);
    final chave =
        _abrirJanela(hoje, hoje.add(FirestoreService.janelaFuturo));
    final j = _janelas[chave];
    if (j == null) return;
    final limite = DateTime.now().add(espera);
    while (j.itens == null && DateTime.now().isBefore(limite)) {
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }
  }

  /// O app voltou à tela: se o dia virou, a janela BASE (que é relativa a hoje)
  /// precisa andar junto, senão o "próximo culto" ficaria preso no dia em que o
  /// app abriu.
  void renovarJanelaBase() {
    final b = _chaveDaBase;
    if (b == null) return;
    final agora = DateTime.now();
    final hoje = DateTime(agora.year, agora.month, agora.day);
    if (_diaDaBase == hoje) return;
    _janelas.remove(b)?.sub?.cancel();
    _chaveDaBase = null;
    listenToScales();
    _recompor();
    notifyListeners();
  }

  String _abrirJanela(DateTime ini, DateTime fim,
      {Stream<({List<ScaleModel> itens, bool doCache})>? fonte}) {
    final chave = _chaveDa(ini, fim);
    if (_janelas.containsKey(chave)) return chave;
    if (_semBanco && fonte == null) return chave;
    final j = _Janela(ini, fim);
    _janelas[chave] = j;
    j.sub = (fonte ??
            FirestoreService.watchScalesComOrigem(inicio: ini, fim: fim))
        .listen((r) {
      // Vazio vindo do cache não é resposta: não apaga o que está na tela.
      if (ignorarVazioDoCache(
          doCache: r.doCache,
          vazio: r.itens.isEmpty,
          jaTemDados: _servidor.any((c) => j.contem(c.date)))) {
        return;
      }
      if (_scales.isEmpty) marcar('cultos-recebidos');
      j.itens = r.itens;
      _recompor();
      _error = null;
      // A cópia só se regrava com o que o SERVIDOR confirmou.
      if (!r.doCache) _guardarNoAparelho();
      notifyListeners();
    }, onError: (e) {
      _error = 'Erro ao carregar escalas';
      notifyListeners();
    });
    return chave;
  }

  /// Refaz `_servidor` e `_scales` a partir do aparelho e das janelas.
  void _recompor() {
    final respondidas = _janelas.values.where((j) => j.itens != null).toList();
    final porId = <String, ScaleModel>{};
    for (final c in _restaurados) {
      if (!respondidas.any((j) => j.contem(c.date))) porId[c.id] = c;
    }
    for (final j in respondidas) {
      for (final c in j.itens!) {
        porId[c.id] = c;
      }
    }
    _servidor = porId.values.toList()..sort((a, b) => a.date.compareTo(b.date));
    _scales = _comPendencias(_servidor);
  }

  /// Drops the listener and attaches a new one.
  ///
  /// The listener guards against stacking subscriptions, so after a failure it
  /// would never reconnect on its own — "Tentar de novo" needs this.
  void retry() {
    for (final j in _janelas.values) {
      j.sub?.cancel();
    }
    _janelas.clear();
    _chaveDaBase = null;
    _error = null;
    notifyListeners();
    listenToScales();
  }

  @override
  void dispose() {
    _fila.removeListener(_aoMudarAFila);
    for (final j in _janelas.values) {
      j.sub?.cancel();
    }
    super.dispose();
  }

  // ─── o que está na fila, por cima do que veio do banco ───────────────────

  void _aoMudarAFila() {
    _scales = _comPendencias(_servidor);
    notifyListeners();
  }

  /// Os cultos com as presenças que ainda esperam para ser enviadas.
  List<ScaleModel> _comPendencias(List<ScaleModel> base) {
    final pendencias = _fila.itens
        .where((i) => i.tipo == TipoDeAcao.presenca)
        .toList();
    if (pendencias.isEmpty) return base;
    return [
      for (final s in base)
        _comPresencas(s, pendencias.where((i) => i.dados['culto'] == s.id)),
    ];
  }

  ScaleModel _comPresencas(ScaleModel s, Iterable<ItemDaFila> itens) {
    if (itens.isEmpty) return s;
    var levitas = s.levitas;
    for (final i in itens) {
      final uid = i.dados['userId'] as String;
      final confirmado = i.dados['confirmado'] as bool;
      levitas = levitas
          .map((l) => l.userId == uid ? l.copyWith(confirmed: confirmado) : l)
          .toList();
    }
    return s.copyWith(levitas: levitas);
  }

  /// Esta presença foi pedida e ainda não chegou ao banco?
  bool presencaPendente(String scaleId, String userId) =>
      _fila.temPendencia('presenca:$scaleId:$userId');

  // ─── cópia no aparelho: abrir já com os cultos na tela ───────────────────

  Timer? _relogioDaCopia;

  void _guardarNoAparelho() {
    _relogioDaCopia?.cancel();
    _relogioDaCopia = Timer(const Duration(seconds: 2), () {
      SnapshotLocal.guardar('scales', _servidor.map((s) => s.toFirestore()).toList());
    });
  }

  /// Põe na tela os cultos que o aparelho guardou da última vez, ANTES de o
  /// banco responder (e antes de o Firebase terminar de ligar). Devolve
  /// quantos eram.
  Future<int> restaurarDoAparelho() async {
    final docs = await SnapshotLocal.ler('scales');
    if (docs == null || _servidor.isNotEmpty) return 0;
    try {
      _restaurados = [for (final d in docs) ScaleModel.fromFirestore(d)];
    } catch (_) {
      return 0; // cópia ilegível: o banco responde logo em seguida
    }
    _recompor();
    _error = null;
    notifyListeners();
    return _servidor.length;
  }

  Future<void> loadScales() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      _restaurados = await FirestoreService.getScales();
      _recompor();
    } catch (e) {
      _error = 'Erro ao carregar escalas: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Coloca uma lista de cultos na memória, sem passar pelo Firestore. Só os
  /// testes de tela usam: o provider de verdade só se enche pela escuta.
  @visibleForTesting
  void carregarParaTeste(List<ScaleModel> cultos) {
    _semBanco = true;
    _restaurados = cultos;
    _recompor();
    notifyListeners();
  }

  /// TODOS os cultos de um dia, do mais cedo ao mais tarde.
  ///
  /// Existia `getScaleForDay`, que devolvia UM culto — o primeiro que
  /// achasse. Numa igreja em que o domingo tem culto de manhã e de noite (e a
  /// quarta também), tocar no dia mostrava só o da manhã: o da noite estava no
  /// banco, na lista de próximos e com ponto no calendário, mas não dava para
  /// abrir pelo dia. A pergunta "qual é o culto deste dia?" não tem resposta
  /// única aqui, então a função que a fazia deixou de existir — e não deve
  /// voltar.
  ///
  /// Pura, e recebe a lista, como [aindaVale]: é conta de data, e conta de
  /// data se testa melhor sem o banco no meio. A hora do dia tocado não
  /// importa; cancelado entra (a tela o mostra riscado, com a marca).
  static List<ScaleModel> cultosDoDia(List<ScaleModel> todos, DateTime dia) {
    return todos
        .where((s) =>
            s.date.year == dia.year &&
            s.date.month == dia.month &&
            s.date.day == dia.day)
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
  }

  List<ScaleModel> getScalesForDay(DateTime day) => cultosDoDia(_scales, day);

  /// Quantos cultos há em cada dia de um mês — para o calendário pôr um ponto
  /// por culto, e o líder ver sem tocar que o domingo tem dois.
  static Map<DateTime, int> cultosPorDia(
      List<ScaleModel> todos, int ano, int mes) {
    final saida = <DateTime, int>{};
    for (final s in todos) {
      if (s.date.year != ano || s.date.month != mes) continue;
      final dia = DateTime(s.date.year, s.date.month, s.date.day);
      saida[dia] = (saida[dia] ?? 0) + 1;
    }
    return saida;
  }

  Map<DateTime, int> getServicesPerDay(int year, int month) =>
      cultosPorDia(_scales, year, month);

  List<ScaleModel> getScalesForMonth(int year, int month) {
    return _scales.where((s) {
      return s.date.year == year && s.date.month == month;
    }).toList();
  }

  /// Por quanto tempo um culto continua sendo "o de agora" depois de começar.
  ///
  /// Quem abre o app no meio do culto quer ver o culto que está
  /// acontecendo, não o da semana que vem. Duas horas cobrem um culto comum
  /// com folga.
  static const Duration duracaoDoCulto = Duration(hours: 2);

  /// Este culto ainda interessa neste instante?
  ///
  /// Função pura, e separada, porque o erro que ela conserta não aparecia em
  /// nenhum teste: a conta anterior comparava só a DATA, jogando a hora
  /// fora. Domingo às 20h53, o culto das 8h daquele mesmo domingo ainda
  /// contava como "próximo", e era ele que aparecia na tela inicial.
  ///
  /// `agora` entra como parâmetro para o teste poder escolher o instante —
  /// inclusive a virada do dia, que é onde este tipo de conta costuma
  /// quebrar.
  static bool aindaVale(ScaleModel culto, DateTime agora) {
    if (culto.canceled) return false;
    return culto.date.isAfter(agora.subtract(duracaoDoCulto));
  }

  /// As músicas que EU vou tocar nos próximos [dias] dias.
  ///
  /// Função pura, e recebe `agora`, pelo mesmo motivo de `aindaVale`: é conta
  /// de data, e conta de data quebra na virada do dia — onde o teste precisa
  /// poder ficar.
  ///
  /// Só entra culto em que a pessoa está escalada. Quem não está escalado
  /// recebe lista vazia, e a tela não desenha cartão nenhum: cartão vazio
  /// dizendo "nenhuma música" é pior que cartão nenhum, porque ocupa o lugar
  /// de algo útil e ensina a pessoa a passar o olho por cima.
  static List<MinhaMusica> minhasProximasMusicas({
    required List<ScaleModel> cultos,
    required String userId,
    required DateTime agora,
    int dias = 7,
  }) {
    if (userId.isEmpty) return const [];
    final limite = agora.add(Duration(days: dias));
    final saida = <MinhaMusica>[];

    for (final culto in cultos) {
      if (!aindaVale(culto, agora)) continue;
      if (culto.date.isAfter(limite)) continue;

      // A função é a DAQUELE culto, não a do perfil: quem canta num domingo e
      // toca baixo no outro precisa abrir a música no modo certo.
      String? minhaFuncao;
      for (final l in culto.levitas) {
        if (l.userId == userId) {
          minhaFuncao = l.instrument;
          break;
        }
      }
      if (minhaFuncao == null) continue;

      for (final ref in culto.songs) {
        saida.add(MinhaMusica(
          culto: culto,
          ref: ref,
          instrumento: minhaFuncao,
        ));
      }
    }

    // A lista do banco já vem por data, mas ordenar aqui deixa a função
    // independente de quem a chama — e o teste pode passar os cultos em
    // qualquer ordem.
    saida.sort((a, b) => a.culto.date.compareTo(b.culto.date));
    return saida;
  }

  /// Quando cada música foi tocada pela última vez, pelas escalas passadas.
  ///
  /// Sem coleção nova: a resposta sai dos cultos que o app já tem em memória.
  /// Isso tem um LIMITE que a tela precisa respeitar — a janela de leitura vai
  /// só até 60 dias atrás (`FirestoreService.janelaPassado`), então a ausência
  /// aqui significa "não tocada nesse período", e **nunca** "nunca tocada".
  /// Dizer "nunca tocada" sobre uma música do ano passado seria mentira, e o
  /// líder montaria o culto com base nela.
  ///
  /// Culto cancelado não conta: ninguém tocou nele. Culto futuro também não —
  /// a pergunta é o que já foi tocado, não o que está marcado.
  static Map<String, DateTime> ultimaVezTocada(
      List<ScaleModel> cultos, DateTime agora) {
    final saida = <String, DateTime>{};
    for (final culto in cultos) {
      if (culto.canceled) continue;
      if (culto.date.isAfter(agora)) continue;
      for (final ref in culto.songs) {
        final atual = saida[ref.songId];
        if (atual == null || culto.date.isAfter(atual)) {
          saida[ref.songId] = culto.date;
        }
      }
    }
    return saida;
  }

  /// Quantas vezes cada música foi tocada, pelas escalas passadas.
  ///
  /// Mesmas regras de [ultimaVezTocada], pela mesma razão: culto cancelado
  /// não conta (ninguém tocou nele) e culto futuro não conta (a pergunta é o
  /// que já foi tocado, não o que está marcado).
  ///
  /// **E o mesmo limite, que a tela precisa dizer em voz alta:** a janela de
  /// leitura vai só até 60 dias atrás, então isto é "mais tocados nos últimos
  /// dois meses", nunca "mais tocados de todos os tempos". Um hino cantado
  /// toda semana até agosto aparece aqui com zero.
  ///
  /// A mesma música repetida DENTRO de um culto conta uma vez só: foi um
  /// culto, e contar duas premiaria um repertório gravado com engano.
  static Map<String, int> vezesTocadas(
      List<ScaleModel> cultos, DateTime agora) {
    final saida = <String, int>{};
    for (final culto in cultos) {
      if (culto.canceled) continue;
      if (culto.date.isAfter(agora)) continue;
      final noCulto = <String>{};
      for (final ref in culto.songs) {
        noCulto.add(ref.songId);
      }
      for (final id in noCulto) {
        saida[id] = (saida[id] ?? 0) + 1;
      }
    }
    return saida;
  }

  /// Upcoming services, cancelled ones left out — they are kept in the
  /// database so the generator does not recreate them, but nobody needs to
  /// see a cancelled service as "the next one".
  ///
  /// A lista já vem do banco ordenada por data (`watchScales` usa
  /// `orderBy('date')`), então o primeiro que passa no filtro é o próximo.
  List<ScaleModel> getUpcomingScales({int limit = 5}) {
    final agora = DateTime.now();
    return _scales.where((s) => aindaVale(s, agora)).take(limit).toList();
  }

  ScaleModel? get nextScale {
    final upcoming = getUpcomingScales(limit: 1);
    return upcoming.isEmpty ? null : upcoming.first;
  }

  void selectScale(ScaleModel? scale) {
    _selectedScale = scale;
    notifyListeners();
  }

  /// Creates a service. Returns null on success, or the message to show.
  Future<String?> createScale(ScaleModel scale) async {
    final result = await FirestoreService.createScale(scale);
    if (!result.success) return result.error;

    _scales = [..._scales, scale]..sort((a, b) => a.date.compareTo(b.date));
    _restaurados = [..._restaurados, scale];
    _recompor();
    notifyListeners();
    return null;
  }

  // Não existe apagar culto. Cancelar é um campo (`setCanceled`), como
  // arquivar é para a música: o culto fica, com quem confirmou, o repertório
  // e o registro de quem tocou. A regra do banco também recusa (`allow
  // delete: if false` em `scales`), então nem um caminho novo no app
  // conseguiria apagar por engano.

  /// Confirma ou desmarca a presença. Devolve null quando deu certo OU quando
  /// ficou esperando a internet; devolve a frase quando o banco recusou.
  ///
  /// A mudança aparece na tela NA HORA (com o relógio de "pendente") e vai
  /// para a fila: o app não espera a rede para dizer à pessoa que o toque
  /// valeu. Com internet, o envio leva menos de um segundo e o relógio nem
  /// chega a ser visto; sem, a confirmação espera, sobrevive a fechar o app e
  /// segue sozinha quando o sinal voltar.
  Future<String?> confirmPresence(
      String scaleId, String userId, bool confirmed) async {
    final culto = _servidor.where((c) => c.id == scaleId).firstOrNull ??
        _scales.where((c) => c.id == scaleId).firstOrNull;
    final item = ItemDaFila.presenca(
      id: CryptoUtils.generateId(),
      culto: scaleId,
      userId: userId,
      confirmado: confirmed,
      agora: DateTime.now(),
      rotulo: culto == null
          ? null
          : '${culto.serviceType} de ${culto.date.day.toString().padLeft(2, '0')}/${culto.date.month.toString().padLeft(2, '0')}',
    );
    final r = await _fila.enfileirar(item);
    if (r != null && r.desfecho == Desfecho.descartado) return r.erro;
    return null;
  }

  /// Leva um recado do chat para as observações do culto. Nulo se deu certo.
  Future<String?> acrescentarObservacao(
      String scaleId, String texto, String autor) async {
    final r = await FirestoreService.acrescentarObservacao(scaleId, texto,
        autor: autor);
    if (!r.success) return r.error;
    _applyLocally(scaleId, (scale) {
      final novo = ScaleModel.comObservacaoNova(scale.observations, texto,
          autor: autor, quando: DateTime.now());
      return novo == null ? scale : scale.copyWith(observations: novo);
    });
    return null;
  }

  /// Replaces the service's repertoire. Null on success, else the message.
  Future<String?> setSongs(String scaleId, List<ScaleSong> songs) async {
    final result = await FirestoreService.setScaleSongs(scaleId, songs);
    if (!result.success) return result.error;
    _applyLocally(scaleId, (scale) => scale.copyWith(songs: songs));
    return null;
  }

  /// Adds one song to the end of the service's repertoire.
  Future<String?> addSong(String scaleId, ScaleSong song) async {
    final result = await FirestoreService.addSongToScale(scaleId, song);
    if (!result.success) return result.error;
    _applyLocally(scaleId, (scale) {
      if (scale.songs.any((s) => s.songId == song.songId)) return scale;
      return scale.copyWith(songs: [...scale.songs, song]);
    });
    return null;
  }

  /// Replaces who is scheduled, keeping the answers already given.
  Future<String?> setLevitas(String scaleId, List<ScaleLevita> levitas) async {
    final result = await FirestoreService.setScaleLevitas(scaleId, levitas);
    if (!result.success) return result.error;
    _applyLocally(scaleId, (scale) {
      final previous = {for (final l in scale.levitas) l.userId: l.confirmed};
      return scale.copyWith(
        levitas: levitas
            .map(
                (l) => l.copyWith(confirmed: previous[l.userId] ?? l.confirmed))
            .toList(),
      );
    });
    return null;
  }

  /// Changes the service's own fields, without touching the lists.
  Future<String?> updateDetails(
    String scaleId, {
    DateTime? date,
    String? serviceType,
    String? observations,
  }) async {
    final result = await FirestoreService.updateScaleDetails(
      scaleId,
      date: date,
      serviceType: serviceType,
      observations: observations,
    );
    if (!result.success) return result.error;
    _applyLocally(
      scaleId,
      (scale) => scale.copyWith(
        date: date,
        serviceType: serviceType,
        observations: observations,
      ),
    );
    return null;
  }

  /// Cancels or reinstates a service. Null on success, else the message.
  ///
  /// Cancelling is a field, not a deletion: the id comes from the date and
  /// time, so a deleted service would be created again on the next start.
  Future<String?> setCanceled(String scaleId, bool canceled) async {
    final r = await FirestoreService.setScaleCanceled(scaleId, canceled);
    if (!r.success) return r.error;
    _applyLocally(scaleId, (s) => s.copyWith(canceled: canceled));
    return null;
  }

  /// Creates the services of the next weeks that are missing.
  ///
  /// Runs only for a leader — the rules refuse it for anybody else — and
  /// costs no reads: what exists is already in [_scales].
  Future<String?> gerarProximos({
    required List<ScheduleSlot> slots,
    required Map<String, TeamModel> equipes,
    String? createdBy,
  }) async {
    if (slots.isEmpty) return null;
    final r = await FirestoreService.ensureUpcomingServices(
      slots: slots,
      equipes: equipes,
      existentes: _scales,
      createdBy: createdBy,
    );
    // The realtime listener brings the new services in; nothing to merge here.
    return r.error;
  }

  /// Puts a team's current line-up back on its future services.
  /// Returns (how many changed, message) — the count is worth showing.
  Future<({int atualizados, String? error})> aplicarEquipeNosProximos(
      TeamModel equipe) {
    return FirestoreService.applyTeamToFutureServices(
      equipe: equipe,
      existentes: _scales,
    );
  }

  /// Mirrors a confirmed change in the list already on screen, so the user
  /// does not wait for the realtime listener to come back.
  void _applyLocally(String scaleId, ScaleModel Function(ScaleModel) change) {
    final idx = _scales.indexWhere((s) => s.id == scaleId);
    if (idx < 0) return;
    // Em TODAS as listas de onde `_recompor` refaz o que se vê: senão a
    // próxima resposta de outra janela desfaria a mudança por um instante.
    ScaleModel trocar(ScaleModel c) => c.id == scaleId ? change(c) : c;
    _restaurados = _restaurados.map(trocar).toList();
    for (final j in _janelas.values) {
      if (j.itens != null) j.itens = j.itens!.map(trocar).toList();
    }
    _servidor = _servidor.map(trocar).toList();
    _scales = _comPendencias(_servidor);
    final novo = _scales.where((s) => s.id == scaleId).firstOrNull;
    if (_selectedScale?.id == scaleId && novo != null) _selectedScale = novo;
    notifyListeners();
  }

}

/// Uma música que eu vou tocar, e em que culto.
///
/// Junta as três coisas que a tela precisa dizer de uma vez: qual música, em
/// que culto (dia e hora), e em que função eu estou naquele culto — que é o
/// que decide se a música abre em cifra ou só com a letra.
class MinhaMusica {
  final ScaleModel culto;
  final ScaleSong ref;

  /// A função NAQUELE culto (`vocalist`, `bass`…), não a do perfil.
  final String instrumento;

  const MinhaMusica({
    required this.culto,
    required this.ref,
    required this.instrumento,
  });
}

/// Um intervalo de datas de cultos que está sendo lido, e o que o servidor já
/// respondeu para ele (nulo até a primeira resposta).
class _Janela {
  final DateTime inicio;
  final DateTime fim;
  StreamSubscription<({List<ScaleModel> itens, bool doCache})>? sub;
  List<ScaleModel>? itens;

  _Janela(this.inicio, this.fim);

  bool contem(DateTime d) => !d.isBefore(inicio) && !d.isAfter(fim);
}
