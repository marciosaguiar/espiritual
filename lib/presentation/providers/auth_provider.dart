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

  /// Restores the session on app start.
  ///
  /// Firebase keeps the signed-in account on the device, so it — not the local
  /// copy — decides whether someone is logged in. The local copy is only used
  /// to fill the screens while offline, when the profile cannot be fetched.
  Future<void> checkSession() async {
    _status = AuthStatus.loading;
    notifyListeners();

    final account = AuthService.currentAuthUser;
    if (account == null) {
      // No account: drop any profile left over from an older version.
      await LocalStorageService.clearSession();
      _user = null;
      _status = AuthStatus.unauthenticated;
      notifyListeners();
      return;
    }

    final profile = await AuthService.getUserById(account.uid) ??
        LocalStorageService.getSession();

    if (profile == null) {
      // Signed in, but the profile could not be read and nothing is cached.
      _errorMessage = 'Não foi possível carregar seu perfil. Verifique a internet.';
      _status = AuthStatus.unauthenticated;
      notifyListeners();
      return;
    }

    _user = profile;
    _status = AuthStatus.authenticated;
    await LocalStorageService.saveSession(profile);
    notifyListeners();
  }

  /// Register new user
  Future<bool> register({
    required String name,
    required String password,
    UserInstrument instrument = UserInstrument.other,
  }) async {
    _status = AuthStatus.loading;
    _errorMessage = null;
    notifyListeners();

    final result = await AuthService.register(
      name: name,
      password: password,
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
