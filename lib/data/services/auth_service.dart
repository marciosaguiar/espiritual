import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';
import '../../core/utils/crypto_utils.dart';
import 'local_storage_service.dart';

class AuthService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static const String _collection = 'users';

  /// Looks a user up by name, ignoring case and surrounding spaces.
  ///
  /// Falls back to the exact-name field so accounts created before
  /// `nameLower` existed keep working.
  static Future<Map<String, dynamic>?> _findByName(String name) async {
    final trimmed = name.trim();
    final lower = UserModel.normalizeName(trimmed);

    final byLower = await _db
        .collection(_collection)
        .where('nameLower', isEqualTo: lower)
        .limit(1)
        .get();
    if (byLower.docs.isNotEmpty) return byLower.docs.first.data();

    final byExact = await _db
        .collection(_collection)
        .where('name', isEqualTo: trimmed)
        .limit(1)
        .get();
    if (byExact.docs.isNotEmpty) return byExact.docs.first.data();

    return null;
  }

  /// Register a new user.
  ///
  /// The role is decided by the server state, never by the sign-up form: the
  /// first person to join leads the ministry, everyone after joins as a levita
  /// and can be promoted by a leader.
  static Future<({bool success, String? error, UserModel? user})> register({
    required String name,
    required String password,
    UserInstrument instrument = UserInstrument.other,
  }) async {
    try {
      if (await _findByName(name) != null) {
        return (success: false, error: 'Este nome já está em uso', user: null);
      }

      final role = await hasAdmin() ? UserRole.levita : UserRole.admin;

      final id = CryptoUtils.generateId();
      final user = UserModel(
        id: id,
        name: name.trim(),
        passwordHash: CryptoUtils.hashPassword(password),
        role: role,
        instrument: instrument,
        createdAt: DateTime.now(),
      );

      await _db.collection(_collection).doc(id).set(user.toFirestore());
      await LocalStorageService.saveSession(user);

      return (success: true, error: null, user: user);
    } on FirebaseException catch (e) {
      return (success: false, error: 'Erro de conexão: ${e.message}', user: null);
    } catch (e) {
      return (success: false, error: 'Erro inesperado: $e', user: null);
    }
  }

  /// Login with name and password
  static Future<({bool success, String? error, UserModel? user})> login({
    required String name,
    required String password,
  }) async {
    try {
      final data = await _findByName(name);

      if (data == null) {
        return (success: false, error: 'Nome ou senha incorretos', user: null);
      }

      final storedHash = data['passwordHash'] as String?;

      if (storedHash == null || !CryptoUtils.verifyPassword(password, storedHash)) {
        return (success: false, error: 'Nome ou senha incorretos', user: null);
      }

      final user = UserModel.fromFirestore(data);
      await LocalStorageService.saveSession(user);

      return (success: true, error: null, user: user);
    } on FirebaseException catch (e) {
      return (success: false, error: 'Erro de conexão: ${e.message}', user: null);
    } catch (e) {
      return (success: false, error: 'Erro inesperado: $e', user: null);
    }
  }

  /// Logout current user
  static Future<void> logout() async {
    await LocalStorageService.clearSession();
  }

  /// Update user profile
  static Future<bool> updateUser(UserModel user) async {
    try {
      await _db.collection(_collection).doc(user.id).update({
        'instrument': user.instrument.name,
        'photoUrl': user.photoUrl,
        'favoriteSongs': user.favoriteSongs,
        'savedTones': user.savedTones,
      });
      await LocalStorageService.saveSession(user);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Toggle favorite song for user
  static Future<UserModel> toggleFavorite(UserModel user, String songId) async {
    final favorites = List<String>.from(user.favoriteSongs);
    if (favorites.contains(songId)) {
      favorites.remove(songId);
    } else {
      favorites.add(songId);
    }
    final updated = user.copyWith(favoriteSongs: favorites);
    await _db.collection(_collection).doc(user.id).update({
      'favoriteSongs': favorites,
    });
    await LocalStorageService.saveSession(updated);
    return updated;
  }

  /// Save preferred tone for a song
  static Future<UserModel> saveSongTone(
      UserModel user, String songId, int semitones) async {
    final tones = Map<String, int>.from(user.savedTones);
    tones[songId] = semitones;
    final updated = user.copyWith(savedTones: tones);
    await _db.collection(_collection).doc(user.id).update({
      'savedTones': tones,
    });
    await LocalStorageService.saveSession(updated);
    return updated;
  }

  /// Get all users (admin only)
  static Stream<List<UserModel>> getAllUsers() {
    return _db
        .collection(_collection)
        .orderBy('name')
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => UserModel.fromFirestore(doc.data()))
            .toList());
  }

  /// Get user by ID
  static Future<UserModel?> getUserById(String id) async {
    try {
      final doc = await _db.collection(_collection).doc(id).get();
      if (!doc.exists) return null;
      return UserModel.fromFirestore(doc.data()!);
    } catch (_) {
      return null;
    }
  }

  /// Check if any admin exists (for first-run setup)
  static Future<bool> hasAdmin() async {
    final snap = await _db
        .collection(_collection)
        .where('role', isEqualTo: 'admin')
        .limit(1)
        .get();
    return snap.docs.isNotEmpty;
  }

  /// How many leaders the ministry has. Used to refuse removing the last one,
  /// which would lock everybody out of the admin features.
  static Future<int> adminCount() async {
    final snap = await _db
        .collection(_collection)
        .where('role', isEqualTo: 'admin')
        .get();
    return snap.docs.length;
  }

  /// Promote or demote a member. Leaders only (enforced by the UI and, once
  /// server-side auth is in place, by the security rules).
  static Future<({bool success, String? error})> setUserRole(
    UserModel user,
    UserRole role,
  ) async {
    if (user.role == role) return (success: true, error: null);

    try {
      if (role == UserRole.levita && await adminCount() <= 1) {
        return (
          success: false,
          error: 'O ministério precisa de pelo menos um líder.'
        );
      }
      await _db
          .collection(_collection)
          .doc(user.id)
          .update({'role': role.name});
      return (success: true, error: null);
    } on FirebaseException catch (e) {
      return (success: false, error: 'Erro de conexão: ${e.message}');
    } catch (e) {
      return (success: false, error: 'Não foi possível alterar a função: $e');
    }
  }
}
