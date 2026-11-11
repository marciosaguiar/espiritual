import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../data/models/scale_model.dart';
import '../../data/services/firestore_service.dart';

class ScaleProvider extends ChangeNotifier {
  List<ScaleModel> _scales = [];
  ScaleModel? _selectedScale;
  bool _isLoading = false;
  String? _error;

  StreamSubscription<List<ScaleModel>>? _scalesSub;

  List<ScaleModel> get scales => _scales;
  ScaleModel? get selectedScale => _selectedScale;
  bool get isLoading => _isLoading;
  String? get error => _error;

  void listenToScales() {
    if (_scalesSub != null) return;
    _scalesSub = FirestoreService.watchScales().listen((scales) {
      _scales = scales;
      _error = null;
      notifyListeners();
    }, onError: (e) {
      _error = 'Erro ao carregar escalas';
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _scalesSub?.cancel();
    super.dispose();
  }

  Future<void> loadScales() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      _scales = await FirestoreService.getScales();
    } catch (e) {
      _error = 'Erro ao carregar escalas: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  ScaleModel? getScaleForDay(DateTime day) {
    final date = DateTime(day.year, day.month, day.day);
    try {
      return _scales.firstWhere((s) {
        final sDate = DateTime(s.date.year, s.date.month, s.date.day);
        return sDate == date;
      });
    } catch (_) {
      return null;
    }
  }

  List<ScaleModel> getScalesForMonth(int year, int month) {
    return _scales.where((s) {
      return s.date.year == year && s.date.month == month;
    }).toList();
  }

  List<ScaleModel> getUpcomingScales({int limit = 5}) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return _scales
        .where((s) {
          final sDate = DateTime(s.date.year, s.date.month, s.date.day);
          return !sDate.isBefore(today);
        })
        .take(limit)
        .toList();
  }

  ScaleModel? get nextScale {
    final upcoming = getUpcomingScales(limit: 1);
    return upcoming.isEmpty ? null : upcoming.first;
  }

  void selectScale(ScaleModel? scale) {
    _selectedScale = scale;
    notifyListeners();
  }

  Future<bool> createScale(ScaleModel scale) async {
    final success = await FirestoreService.createScale(scale);
    if (success) {
      _scales.add(scale);
      _scales.sort((a, b) => a.date.compareTo(b.date));
      notifyListeners();
    }
    return success;
  }

  Future<bool> deleteScale(String scaleId) async {
    final success = await FirestoreService.deleteScale(scaleId);
    if (success) {
      _scales.removeWhere((s) => s.id == scaleId);
      if (_selectedScale?.id == scaleId) {
        _selectedScale = null;
      }
      notifyListeners();
    }
    return success;
  }

  /// Confirms presence. Returns null on success, or the message to show.
  Future<String?> confirmPresence(
      String scaleId, String userId, bool confirmed) async {
    final result =
        await FirestoreService.confirmPresence(scaleId, userId, confirmed);
    if (!result.success) return result.error;
    _applyLocally(scaleId, (scale) {
      final levitas = scale.levitas
          .map((l) => l.userId == userId ? l.copyWith(confirmed: confirmed) : l)
          .toList();
      return scale.copyWith(levitas: levitas);
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
  Future<String?> setLevitas(
      String scaleId, List<ScaleLevita> levitas) async {
    final result = await FirestoreService.setScaleLevitas(scaleId, levitas);
    if (!result.success) return result.error;
    _applyLocally(scaleId, (scale) {
      final previous = {for (final l in scale.levitas) l.userId: l.confirmed};
      return scale.copyWith(
        levitas: levitas
            .map((l) =>
                l.copyWith(confirmed: previous[l.userId] ?? l.confirmed))
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

  /// Mirrors a confirmed change in the list already on screen, so the user
  /// does not wait for the realtime listener to come back.
  void _applyLocally(String scaleId, ScaleModel Function(ScaleModel) change) {
    final idx = _scales.indexWhere((s) => s.id == scaleId);
    if (idx < 0) return;
    _scales[idx] = change(_scales[idx]);
    if (_selectedScale?.id == scaleId) _selectedScale = _scales[idx];
    notifyListeners();
  }

  /// Check if a day has a service scheduled
  bool hasDayService(DateTime day) => getScaleForDay(day) != null;

  /// Days in current month with services
  Set<DateTime> getDaysWithServices(int year, int month) {
    return getScalesForMonth(year, month)
        .map((s) => DateTime(s.date.year, s.date.month, s.date.day))
        .toSet();
  }
}
