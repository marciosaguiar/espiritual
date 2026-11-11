import 'package:flutter/foundation.dart';
import '../../data/models/arrangement_model.dart';
import '../../data/models/user_model.dart';
import '../../data/services/auth_service.dart';
import '../../data/services/firestore_service.dart';
import '../../data/services/local_storage_service.dart';

enum AuthStatus { initial, loading, authenticated, unauthenticated, error }

class AuthProvider extends ChangeNotifier {
  UserModel? _user;
  AuthStatus _status = AuthStatus.initial;
  String? _errorMessage;

  /// This musician's own settings per song (tone, notes, capo), read from
  /// `users/{id}/songPrefs`. Loaded once at sign-in and kept here so the song
  /// screens never hit the network just to show a transpose amount.
  Map<String, SongPrefModel> _prefs = {};

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

    await _loadPrefs(profile.id);
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
      await _loadPrefs(result.user!.id);
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
    _prefs = {};
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

  /// This person's settings for [songId], or null if they never set any.
  SongPrefModel? prefFor(String songId) => _prefs[songId];

  /// Every song this person has settings for.
  Map<String, SongPrefModel> get songPrefs => Map.unmodifiable(_prefs);

  /// Saved transpose for a song (0 = as written).
  int getSavedTone(String songId) => _prefs[songId]?.semitones ?? 0;

  /// This person's own notes for a song.
  String getSongNotes(String songId) => _prefs[songId]?.notes ?? '';

  /// Saves the tone, keeping any notes already written.
  Future<String?> saveSongTone(String songId, int semitones) =>
      _savePref(songId, semitones: semitones);

  /// Saves personal notes, keeping the chosen tone.
  Future<String?> saveSongNotes(String songId, String notes) =>
      _savePref(songId, notes: notes);

  /// Writes one song's preference. Returns null on success, or the message to
  /// show. An empty preference is deleted instead of stored.
  Future<String?> _savePref(
    String songId, {
    int? semitones,
    String? notes,
    int? capo,
  }) async {
    final user = _user;
    if (user == null) return 'Entre novamente para salvar.';

    final current = _prefs[songId] ??
        SongPrefModel(songId: songId, updatedAt: DateTime.now());
    final updated = current.copyWith(
      semitones: semitones,
      notes: notes,
      capo: capo,
    );

    // Shows the change at once; undone below if the write fails.
    final previous = _prefs[songId];
    _prefs = {..._prefs, songId: updated};
    notifyListeners();

    final result = await FirestoreService.saveSongPref(user.id, updated);
    if (!result.success) {
      final rolledBack = {..._prefs};
      previous == null ? rolledBack.remove(songId) : rolledBack[songId] = previous;
      _prefs = rolledBack;
      notifyListeners();
      return result.error;
    }

    if (updated.isEmpty) {
      final without = {..._prefs}..remove(songId);
      _prefs = without;
      notifyListeners();
    }
    return null;
  }

  Future<void> _loadPrefs(String userId) async {
    _prefs = await FirestoreService.getAllSongPrefs(userId);
    notifyListeners();
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
