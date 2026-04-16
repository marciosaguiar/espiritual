import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';
import '../../core/utils/crypto_utils.dart';
import 'local_storage_service.dart';

class AuthService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static const String _collection = 'users';

  /// Register a new user.
  /// Role is always [UserRole.levita] — admins are promoted by an existing admin.
  static Future<({bool success, String? error, UserModel? user})> register({
    required String name,
    required String password,
    UserInstrument instrument = UserInstrument.other,
  }) async {
    try {
      // Check if name is already taken
      final existing = await _db
          .collection(_collection)
          .where('name', isEqualTo: name.trim())
          .limit(1)
          .get();

      if (existing.docs.isNotEmpty) {
        return (success: false, error: 'Este nome já está em uso', user: null);
      }

      final id = CryptoUtils.generateId();
      final user = UserModel(
        id: id,
        name: name.trim(),
        passwordHash: CryptoUtils.hashPassword(password),
        role: UserRole.levita, // always levita on self-registration
        instrument: instrument,
        createdAt: DateTime.now(),
      );

      await _db.collection(_collection).doc(id).set(user.toFirestoreCreate());
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
      final snapshot = await _db
          .collection(_collection)
          .where('name', isEqualTo: name.trim())
          .limit(1)
          .get();

      if (snapshot.docs.isEmpty) {
        return (success: false, error: 'Nome ou senha incorretos', user: null);
      }

      final data = snapshot.docs.first.data();
      final storedHash = data['passwordHash'] as String?;

      if (storedHash == null || !CryptoUtils.verifyPassword(password, storedHash)) {
        return (success: false, error: 'Nome ou senha incorretos', user: null);
      }

      final user = UserModel.fromFirestore(data);

      if (user.isBlocked) {
        return (
          success: false,
          error: 'Sua conta foi bloqueada. Fale com o líder do ministério.',
          user: null
        );
      }

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
  static Stream<List<UserModel>> getAllUsers({int limit = 100}) {
    return _db
        .collection(_collection)
        .orderBy('name')
        .limit(limit)
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

  /// Block or unblock a user (admin only).
  static Future<bool> setUserBlocked(String userId, bool blocked) async {
    try {
      await _db.collection(_collection).doc(userId).update({
        'isBlocked': blocked,
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Promote or demote a user's role (admin only).
  static Future<bool> setUserRole(String userId, UserRole role) async {
    try {
      await _db.collection(_collection).doc(userId).update({
        'role': role.name,
      });
      return true;
    } catch (_) {
      return false;
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
}
