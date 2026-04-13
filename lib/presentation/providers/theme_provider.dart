import 'package:flutter/material.dart';
import '../../data/services/local_storage_service.dart';

class ThemeProvider extends ChangeNotifier {
  bool _isDarkMode;

  ThemeProvider() : _isDarkMode = LocalStorageService.isDarkMode;

  bool get isDarkMode => _isDarkMode;

  ThemeMode get themeMode => _isDarkMode ? ThemeMode.dark : ThemeMode.light;

  Future<void> toggleTheme() async {
    _isDarkMode = !_isDarkMode;
    await LocalStorageService.saveTheme(_isDarkMode);
    notifyListeners();
  }

  Future<void> setDarkMode(bool value) async {
    if (_isDarkMode != value) {
      _isDarkMode = value;
      await LocalStorageService.saveTheme(_isDarkMode);
      notifyListeners();
    }
  }
}
