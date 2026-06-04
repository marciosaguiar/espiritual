import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../core/preview.dart';
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
    if (kPreviewMode) {
      _scales = PreviewData.scales;
      notifyListeners();
      return;
    }
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

  Future<bool> updateScale(ScaleModel scale) async {
    final success = await FirestoreService.updateScale(scale);
    if (success) {
      final idx = _scales.indexWhere((s) => s.id == scale.id);
      if (idx >= 0) {
        _scales[idx] = scale;
        notifyListeners();
      }
      if (_selectedScale?.id == scale.id) {
        _selectedScale = scale;
      }
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

  Future<bool> confirmPresence(
      String scaleId, String userId, bool confirmed) async {
    final success =
        await FirestoreService.confirmPresence(scaleId, userId, confirmed);
    if (success) {
      final idx = _scales.indexWhere((s) => s.id == scaleId);
      if (idx >= 0) {
        final scale = _scales[idx];
        final levitas = scale.levitas.map((l) {
          if (l.userId == userId) {
            return l.copyWith(confirmed: confirmed);
          }
          return l;
        }).toList();
        _scales[idx] = scale.copyWith(levitas: levitas);
        if (_selectedScale?.id == scaleId) {
          _selectedScale = _scales[idx];
        }
        notifyListeners();
      }
    }
    return success;
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
