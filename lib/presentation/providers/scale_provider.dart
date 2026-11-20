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

  StreamSubscription<({List<ScaleModel> itens, bool doCache})>? _scalesSub;

  List<ScaleModel> get scales => _scales;
  ScaleModel? get selectedScale => _selectedScale;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// [fonte] só os testes trocam: é o que permite provar o que o provider faz
  /// com um vazio do cache sem ter um Firestore.
  void listenToScales({Stream<({List<ScaleModel> itens, bool doCache})>? fonte}) {
    if (_scalesSub != null) return;
    _scalesSub = (fonte ?? FirestoreService.watchScalesComOrigem()).listen((r) {
      // Vazio vindo do cache não é resposta: não apaga o que está na tela.
      if (ignorarVazioDoCache(
          doCache: r.doCache, vazio: r.itens.isEmpty, jaTemDados: _servidor.isNotEmpty)) {
        return;
      }
      if (_scales.isEmpty) marcar('cultos-recebidos');
      _servidor = r.itens;
      _scales = _comPendencias(r.itens);
      _error = null;
      // A cópia só se regrava com o que o SERVIDOR confirmou.
      if (!r.doCache) _guardarNoAparelho();
      notifyListeners();
    }, onError: (e) {
      _error = 'Erro ao carregar escalas';
      notifyListeners();
    });
  }

  /// Drops the listener and attaches a new one.
  ///
  /// The listener guards against stacking subscriptions, so after a failure it
  /// would never reconnect on its own — "Tentar de novo" needs this.
  void retry() {
    _scalesSub?.cancel();
    _scalesSub = null;
    _error = null;
    notifyListeners();
    listenToScales();
  }

  @override
  void dispose() {
    _fila.removeListener(_aoMudarAFila);
    _scalesSub?.cancel();
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
      _servidor = [for (final d in docs) ScaleModel.fromFirestore(d)];
    } catch (_) {
      return 0; // cópia ilegível: o banco responde logo em seguida
    }
    _scales = _comPendencias(_servidor);
    _error = null;
    notifyListeners();
    return _servidor.length;
  }

  Future<void> loadScales() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      _servidor = await FirestoreService.getScales();
      _scales = _comPendencias(_servidor);
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
    _servidor = cultos;
    _scales = _comPendencias(cultos);
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
    _servidor = [..._servidor, scale]..sort((a, b) => a.date.compareTo(b.date));
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
    _scales[idx] = change(_scales[idx]);
    final i2 = _servidor.indexWhere((s) => s.id == scaleId);
    if (i2 >= 0 && !identical(_servidor, _scales)) {
      _servidor = [..._servidor]..[i2] = change(_servidor[i2]);
    }
    if (_selectedScale?.id == scaleId) _selectedScale = _scales[idx];
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
