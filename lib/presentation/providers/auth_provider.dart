import 'package:flutter/foundation.dart';
import '../../data/models/user_model.dart';
import '../../data/services/auth_service.dart';
import '../../data/services/local_storage_service.dart';

enum AuthStatus { initial, loading, authenticated, unauthenticated, error }

class AuthProvider extends ChangeNotifier {
  UserModel? _user;
  AuthStatus _status = AuthStatus.initial;
  String? _errorMessage;

  UserModel? get user => _user;
  AuthStatus get status => _status;
  String? get errorMessage => _errorMessage;
  bool get isAuthenticated => _status == AuthStatus.authenticated && _user != null;
  bool get isAdmin => _user?.isAdmin ?? false;
  bool get isLoading => _status == AuthStatus.loading;

  /// Check persisted session on app start
  Future<void> checkSession() async {
    _status = AuthStatus.loading;
    notifyListeners();

    final savedUser = LocalStorageService.getSession();
    if (savedUser != null) {
      _user = savedUser;
      _status = AuthStatus.authenticated;
    } else {
      _status = AuthStatus.unauthenticated;
    }
    notifyListeners();
  }

  /// Register new user
  Future<bool> register({
    required String name,
    required String password,
    UserRole role = UserRole.levita,
    UserInstrument instrument = UserInstrument.other,
  }) async {
    _status = AuthStatus.loading;
    _errorMessage = null;
    notifyListeners();

    final result = await AuthService.register(
      name: name,
      password: password,
      role: role,
      instrument: instrument,
    );

    if (result.success && result.user != null) {
      _user = result.user;
      _status = AuthStatus.authenticated;
      notifyListeners();
      return true;
    } else {
      _errorMessage = result.error;
      _status = AuthStatus.unauthenticated;
      notifyListeners();
      return false;
    }
  }

  /// Login with name and password
  Future<bool> login({required String name, required String password}) async {
    _status = AuthStatus.loading;
    _errorMessage = null;
    notifyListeners();

    final result = await AuthService.login(name: name, password: password);

    if (result.success && result.user != null) {
      _user = result.user;
      _status = AuthStatus.authenticated;
      notifyListeners();
      return true;
    } else {
      _errorMessage = result.error;
      _status = AuthStatus.unauthenticated;
      notifyListeners();
      return false;
    }
  }

  /// Logout
  Future<void> logout() async {
    await AuthService.logout();
    _user = null;
    _status = AuthStatus.unauthenticated;
    _errorMessage = null;
    notifyListeners();
  }

  /// Toggle favorite song
  Future<void> toggleFavorite(String songId) async {
    if (_user == null) return;
    final updated = await AuthService.toggleFavorite(_user!, songId);
    _user = updated;
    notifyListeners();
  }

  /// Check if song is favorite
  bool isFavorite(String songId) {
    return _user?.favoriteSongs.contains(songId) ?? false;
  }

  /// Save preferred tone for a song
  Future<void> saveSongTone(String songId, int semitones) async {
    if (_user == null) return;
    final updated = await AuthService.saveSongTone(_user!, songId, semitones);
    _user = updated;
    notifyListeners();
  }

  /// Get saved tone for a song (0 = original)
  int getSavedTone(String songId) {
    return _user?.savedTones[songId] ?? 0;
  }

  /// Update user profile
  Future<bool> updateProfile({
    UserInstrument? instrument,
    String? photoUrl,
  }) async {
    if (_user == null) return false;
    final updated = _user!.copyWith(
      instrument: instrument,
      photoUrl: photoUrl,
    );
    final success = await AuthService.updateUser(updated);
    if (success) {
      _user = updated;
      notifyListeners();
    }
    return success;
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
}
