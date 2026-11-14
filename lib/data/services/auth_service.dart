import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/user_model.dart';
import 'local_storage_service.dart';

/// Sign-in, sign-up and the user profile.
///
/// The password is handled entirely by Firebase Authentication: it never
/// reaches this code and no hash is stored in Firestore. Because Firebase
/// identifies people by e-mail and this ministry signs in with a name, the
/// address is derived from the name — see [UserModel.emailForName]. The login
/// screen still asks only for a name and a password.
class AuthService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static const String _collection = 'users';

  /// Minimum the app accepts. Firebase itself requires 6.
  static const int minPasswordLength = 6;

  /// The signed-in account, or null.
  static User? get currentAuthUser => _auth.currentUser;

  /// Fires on sign-in, sign-out and token refresh.
  static Stream<User?> authStateChanges() => _auth.authStateChanges();

  // ─── Register ─────────────────────────────────────────────────────────────

  /// Creates an account.
  ///
  /// Everyone joins as a levita — the security rules refuse any other role on
  /// sign-up, because the app's address is public and otherwise a stranger
  /// could register straight into the leader role through the API. The first
  /// leader is promoted once in the Firebase console; from then on leaders
  /// promote the others from the Members screen.
  static Future<({bool success, String? error, UserModel? user})> register({
    required String name,
    required String password,
    UserInstrument instrument = UserInstrument.other,
  }) async {
    final trimmed = name.trim();
    if (trimmed.length < 3) {
      return (
        success: false,
        error: 'O nome precisa ter ao menos 3 letras.',
        user: null
      );
    }
    if (password.length < minPasswordLength) {
      return (
        success: false,
        error: 'A senha precisa ter no mínimo $minPasswordLength caracteres.',
        user: null
      );
    }

    final email = UserModel.emailForName(trimmed);

    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      final uid = credential.user!.uid;

      final user = UserModel(
        id: uid,
        name: trimmed,
        email: email,
        role: UserRole.levita,
        instrument: instrument,
        createdAt: DateTime.now(),
      );

      await _db.collection(_collection).doc(uid).set(user.toFirestore());
      await LocalStorageService.saveSession(user);

      return (success: true, error: null, user: user);
    } on FirebaseAuthException catch (e) {
      return (success: false, error: _messageFor(e), user: null);
    } on FirebaseException catch (e) {
      return (
        success: false,
        error: 'Não foi possível salvar seu perfil: ${e.message}',
        user: null
      );
    }
  }

  // ─── Login ────────────────────────────────────────────────────────────────

  /// Signs in with the name and password typed on the login screen.
  static Future<({bool success, String? error, UserModel? user})> login({
    required String name,
    required String password,
  }) async {
    final email = UserModel.emailForName(name);

    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      final uid = credential.user!.uid;

      final user = await getUserById(uid);
      if (user == null) {
        // Account exists in Firebase but has no profile document — only
        // possible if the profile write failed during sign-up. Rebuild it
        // instead of leaving the person locked out of their own account.
        final rebuilt = UserModel(
          id: uid,
          name: name.trim(),
          email: email,
          role: UserRole.levita,
          createdAt: DateTime.now(),
        );
        await _db.collection(_collection).doc(uid).set(rebuilt.toFirestore());
        await LocalStorageService.saveSession(rebuilt);
        return (success: true, error: null, user: rebuilt);
      }

      await LocalStorageService.saveSession(user);
      return (success: true, error: null, user: user);
    } on FirebaseAuthException catch (e) {
      return (success: false, error: _messageFor(e), user: null);
    } on FirebaseException catch (e) {
      return (
        success: false,
        error: 'Erro de conexão: ${e.message}',
        user: null
      );
    }
  }

  static Future<void> logout() async {
    await _auth.signOut();
    await LocalStorageService.clearSession();
  }

  // ─── Password ─────────────────────────────────────────────────────────────

  /// Changes the signed-in user's own password, after confirming the current
  /// one. This is the only password change an app is allowed to make.
  static Future<({bool success, String? error})> changePassword({
    required UserModel user,
    required String currentPassword,
    required String newPassword,
  }) async {
    if (newPassword.length < minPasswordLength) {
      return (
        success: false,
        error: 'A nova senha precisa ter no mínimo $minPasswordLength caracteres.'
      );
    }

    final account = _auth.currentUser;
    if (account == null) {
      return (success: false, error: 'Entre novamente para trocar a senha.');
    }

    try {
      // Firebase requires a recent sign-in before a password change.
      await account.reauthenticateWithCredential(
        EmailAuthProvider.credential(
          email: UserModel.emailForName(user.name),
          password: currentPassword,
        ),
      );
      await account.updatePassword(newPassword);
      return (success: true, error: null);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
        return (success: false, error: 'A senha atual está incorreta.');
      }
      return (success: false, error: _messageFor(e));
    }
  }

  /// Why a leader can no longer set someone else's password.
  ///
  /// Firebase Authentication only lets an account change its own password; a
  /// reset for someone else needs the Admin SDK, which must run on a server
  /// (Cloud Functions) and cannot run inside the app. The addresses here are
  /// internal (`@levitas.app`), so the e-mail reset link has nowhere to go
  /// either. Until that server exists, this is the honest answer to show.
  static const String leaderResetUnavailable =
      'A troca de senha de outra pessoa não é mais feita pelo app: agora quem '
      'guarda as senhas é o Firebase, e ele só permite que cada pessoa mude a '
      'sua. Peça para ela entrar e usar Perfil → Alterar minha senha. Se ela '
      'não consegue entrar de jeito nenhum, é preciso habilitar a redefinição '
      'no servidor.';

  // ─── Profile ──────────────────────────────────────────────────────────────

  static Future<bool> updateUser(UserModel user) async {
    try {
      await _db.collection(_collection).doc(user.id).update({
        'instrument': user.instrument.name,
        'photoUrl': user.photoUrl,
        'favoriteSongs': user.favoriteSongs,
        if (user.leitura != null) 'leitura': user.leitura!.name,
      });
      await LocalStorageService.saveSession(user);
      return true;
    } catch (_) {
      return false;
    }
  }

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

  static Stream<List<UserModel>> getAllUsers() {
    return _db
        .collection(_collection)
        .orderBy('name')
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => UserModel.fromFirestore(doc.data()))
            .toList());
  }

  static Future<UserModel?> getUserById(String id) async {
    try {
      final doc = await _db.collection(_collection).doc(id).get();
      if (!doc.exists) return null;
      return UserModel.fromFirestore(doc.data()!);
    } catch (_) {
      return null;
    }
  }

  // ─── Roles ────────────────────────────────────────────────────────────────

  static Future<bool> hasAdmin() async {
    final snap = await _db
        .collection(_collection)
        .where('role', isEqualTo: 'admin')
        .limit(1)
        .get();
    return snap.docs.isNotEmpty;
  }

  /// How many leaders the ministry has. Used to refuse removing the last one,
  /// which would lock everybody out of the leader-only screens.
  static Future<int> adminCount() async {
    final snap = await _db
        .collection(_collection)
        .where('role', isEqualTo: 'admin')
        .get();
    return snap.docs.length;
  }

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
    }
  }

  // ─── Errors ───────────────────────────────────────────────────────────────

  /// Turns a Firebase code into something a person can act on.
  ///
  /// The codes mention e-mail because that is how Firebase identifies the
  /// account; the messages say "nome", which is what the person actually typed.
  static String _messageFor(FirebaseAuthException e) {
    switch (e.code) {
      case 'email-already-in-use':
        return 'Este nome já está em uso. Escolha outro.';
      case 'invalid-email':
        return 'Esse nome não pode ser usado. Use letras e números.';
      case 'weak-password':
        return 'Senha muito fraca. Use ao menos $minPasswordLength caracteres.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Nome ou senha incorretos.';
      case 'user-disabled':
        return 'Esta conta foi desativada. Fale com o líder do ministério.';
      case 'too-many-requests':
        return 'Muitas tentativas. Espere alguns minutos e tente de novo.';
      case 'network-request-failed':
        return 'Sem conexão. Verifique a internet e tente de novo.';
      case 'requires-recent-login':
        return 'Por segurança, saia e entre novamente antes de trocar a senha.';
      case 'operation-not-allowed':
        return 'O login por senha não está habilitado no Firebase '
            '(Authentication → Sign-in method → E-mail/senha).';
      default:
        return e.message ?? 'Não foi possível concluir. Tente novamente.';
    }
  }
}
