import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/models/team_model.dart';
import '../../data/services/firestore_service.dart';

/// Teams and the standing schedule — the two things a leader sets once so the
/// app can build the services by itself.
class AgendaProvider extends ChangeNotifier {
  List<TeamModel> _teams = [];
  FixedSchedule? _schedule;
  bool _loading = true;
  String? _error;

  StreamSubscription<List<TeamModel>>? _teamsSub;
  StreamSubscription<FixedSchedule?>? _scheduleSub;

  List<TeamModel> get teams => _teams;
  FixedSchedule? get schedule => _schedule;
  bool get isLoading => _loading;
  String? get error => _error;

  /// The slots to work from. Empty while nothing was ever saved.
  List<ScheduleSlot> get slots => _schedule?.slots ?? const [];

  /// Teams by id, which is what generating services needs.
  Map<String, TeamModel> get teamsById => {for (final t in _teams) t.id: t};

  TeamModel? teamById(String id) => teamsById[id];

  void listen() {
    if (_teamsSub != null) return;

    _teamsSub = FirestoreService.watchTeams().listen((teams) {
      _teams = teams;
      _loading = false;
      _error = null;
      notifyListeners();
    }, onError: (_) {
      _loading = false;
      _error = 'Não foi possível carregar as equipes.';
      notifyListeners();
    });

    _scheduleSub = FirestoreService.watchSchedule().listen((agenda) {
      _schedule = agenda;
      notifyListeners();
    }, onError: (_) {
      _error = 'Não foi possível carregar a agenda fixa.';
      notifyListeners();
    });
  }

  /// Drops both listeners and attaches new ones, for "try again".
  void retry() {
    _teamsSub?.cancel();
    _scheduleSub?.cancel();
    _teamsSub = null;
    _scheduleSub = null;
    _error = null;
    _loading = true;
    notifyListeners();
    listen();
  }

  @override
  void dispose() {
    _teamsSub?.cancel();
    _scheduleSub?.cancel();
    super.dispose();
  }

  // ─── Teams ────────────────────────────────────────────────────────────────

  /// Saves a team. Returns null on success, or the message to show.
  Future<String?> saveTeam(TeamModel team) async {
    final r = await FirestoreService.saveTeam(team);
    return r.error;
  }

  Future<String?> deleteTeam(String teamId) async {
    // A team still used by the schedule would leave services pointing at
    // nothing; the slot is cleared first.
    final usados = slots.where((s) => s.teamId == teamId).toList();
    if (usados.isNotEmpty) {
      final limpos = slots
          .map((s) => s.teamId == teamId ? s.copyWith(teamId: '') : s)
          .toList();
      final r = await FirestoreService.saveSchedule(
        FixedSchedule(slots: limpos, updatedAt: DateTime.now()),
      );
      if (!r.success) return r.error;
    }
    final r = await FirestoreService.deleteTeam(teamId);
    return r.error;
  }

  // ─── Standing schedule ────────────────────────────────────────────────────

  Future<String?> saveSlots(List<ScheduleSlot> novos) async {
    final r = await FirestoreService.saveSchedule(
      FixedSchedule(slots: novos, updatedAt: DateTime.now()),
    );
    return r.error;
  }

  /// Writes the church's five standing services the first time the screen is
  /// opened, so the leader starts from something real instead of a blank list.
  Future<String?> criarAgendaPadrao({
    String equipeManha = '',
    String equipeNoite = '',
  }) {
    return saveSlots(FixedSchedule.padraoDaIgreja(
      equipeManha: equipeManha,
      equipeNoite: equipeNoite,
    ));
  }
}
