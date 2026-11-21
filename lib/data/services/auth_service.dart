import 'dart:async';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/user_model.dart';
import 'contador_de_leituras.dart';
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
  /// Everyone joins as `pendente` and waits for a leader — the security rules
  /// refuse any other role on sign-up. The app's address is public, so without
  /// this step anyone with the link would land straight inside the chat and
  /// the schedule; and if the role could be chosen here, a stranger could
  /// register as a leader through the API.
  ///
  /// The first leader is promoted once in the Firebase console; from then on
  /// leaders approve and promote the others from the Members screen.
  static Future<({bool success, String? error, UserModel? user})> register({
    required String name,
    required String password,
    UserInstrument instrument = UserInstrument.other,
    List<UserInstrument>? instruments,
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
        role: UserRole.pendente,
        instrument: instrument,
        instruments: instruments,
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

  /// Entra com o que foi digitado na tela de login: o nome, como sempre, ou
  /// um e-mail, para quem cadastrou um de verdade.
  ///
  /// Os dois num campo só porque uma conta do Firebase tem UM endereço: quem
  /// cadastra e-mail de recuperação passa a ter o e-mail no lugar do endereço
  /// interno, e entrar pelo nome deixaria de funcionar para essa pessoa.
  static Future<({bool success, String? error, UserModel? user})> login({
    required String name,
    required String password,
  }) async {
    final email = UserModel.emailParaEntrar(name);

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
          // Entrou pelo e-mail e o perfil não existe: o nome não dá para
          // adivinhar do endereço, então fica a parte antes da arroba e a
          // pessoa corrige em Perfil. Melhor isso que travar a conta.
          name: name.contains('@') ? name.split('@').first.trim() : name.trim(),
          email: email,
          // Mesmo degrau do cadastro: um perfil refeito aqui não pode
          // valer mais do que um perfil criado pela porta da frente. Com
          // `levita` as regras recusariam a escrita, e a pessoa ficaria
          // trancada fora da própria conta.
          role: UserRole.pendente,
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
      // O Firebase exige entrada recente antes de trocar a senha.
      //
      // O endereço sai de `account.email`, NÃO do nome. Quem cadastrou um
      // e-mail de recuperação tem esse e-mail como endereço da conta, e
      // derivar do nome faria justamente essa pessoa não conseguir mais
      // trocar a senha — o defeito apareceria só em quem se protegeu.
      await account.reauthenticateWithCredential(
        EmailAuthProvider.credential(
          email: account.email ?? UserModel.emailForName(user.name),
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

  /// Por que o líder não consegue trocar a senha de outra pessoa.
  ///
  /// O Firebase só deixa cada conta trocar a própria senha. Trocar a de
  /// outro exige o Admin SDK, com uma chave de administrador do projeto — e
  /// nem o console do Firebase faz isso: lá dá para criar conta, apagar conta
  /// e mandar e-mail de recuperação, não definir a senha de uma conta que já
  /// existe.
  ///
  /// E a chave de administrador este projeto não tem de propósito: ela não
  /// serve só para trocar senha. Quem a tem assina um token para QUALQUER
  /// conta e entra como o líder do ministério. Não existe permissão menor
  /// que isso no Firebase.
  ///
  /// Daí o único caminho que sobra ser o e-mail de recuperação — e ele só
  /// pode ser cadastrado enquanto a pessoa ainda consegue entrar.
  static const String leaderResetUnavailable =
      'Ninguém troca a senha de outra pessoa — nem o líder, nem o app. O '
      'Firebase só deixa cada conta trocar a sua.\n\nSe ela ainda consegue '
      'entrar: Perfil → Conta → Alterar minha senha.\n\nSe não consegue mais, só o '
      'e-mail de recuperação resolve, e ele precisa ter sido cadastrado '
      'antes. Por isso vale pedir a quem ainda não cadastrou que faça agora, '
      'em Perfil → Conta → Recuperar a senha.';

  /// Manda o link de "esqueci minha senha" para um e-mail.
  ///
  /// Recusa o endereço interno antes de tentar, e isso não é zelo: o
  /// `@levitas.app` não é de ninguém. O Firebase aceitaria o pedido, a tela
  /// diria "enviamos o link" e a mensagem morreria no caminho — a pessoa
  /// esperando um e-mail que não existe é pior que um "não dá" na hora.
  static Future<({bool success, String? error})> enviarLinkDeSenha(
      String email) async {
    final limpo = email.trim().toLowerCase();
    if (limpo.isEmpty || !limpo.contains('@') || !limpo.contains('.')) {
      return (success: false, error: 'Digite um e-mail válido.');
    }
    if (UserModel.enderecoInterno(limpo)) {
      return (
        success: false,
        error: 'Esse endereço é interno do app e não recebe e-mail. Use o '
            'e-mail que você cadastrou em Perfil → Conta → Recuperar a senha. Se você '
            'nunca cadastrou um, fale com o líder do ministério.'
      );
    }

    try {
      // Sem isto o e-mail do Firebase chega em inglês.
      await _auth.setLanguageCode('pt-BR');
      await _auth.sendPasswordResetEmail(email: limpo);
      return (success: true, error: null);
    } on FirebaseAuthException catch (e) {
      return (success: false, error: _messageFor(e));
    }
  }

  /// Cadastra (ou troca) o e-mail de recuperação da própria conta.
  ///
  /// O endereço só passa a valer quando a pessoa clica no link que chega na
  /// caixa dela — é o `verifyBeforeUpdateEmail` que faz isso. É de propósito:
  /// um e-mail digitado errado viraria o endereço da conta, e aí a pessoa não
  /// entraria mais nem receberia o link para consertar.
  static Future<({bool success, String? error})> definirEmailDeRecuperacao({
    required UserModel user,
    required String email,
    required String senhaAtual,
  }) async {
    final limpo = email.trim().toLowerCase();
    if (limpo.isEmpty || !limpo.contains('@') || !limpo.contains('.')) {
      return (success: false, error: 'Digite um e-mail válido.');
    }
    if (UserModel.enderecoInterno(limpo)) {
      return (
        success: false,
        error: 'Esse domínio é do próprio app. Use um e-mail de verdade, '
            'desses que você abre no celular.'
      );
    }

    final account = _auth.currentUser;
    if (account == null) {
      return (success: false, error: 'Entre novamente para cadastrar o e-mail.');
    }

    try {
      await _auth.setLanguageCode('pt-BR');
      // Trocar o endereço da conta é operação sensível: o Firebase exige
      // entrada recente, e pedir a senha é também o que impede que um
      // celular esquecido desbloqueado troque o e-mail de recuperação de
      // alguém — o que seria tomar a conta.
      await account.reauthenticateWithCredential(
        EmailAuthProvider.credential(
          email: account.email ?? UserModel.emailForName(user.name),
          password: senhaAtual,
        ),
      );
      await account.verifyBeforeUpdateEmail(limpo);
      return (success: true, error: null);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
        return (success: false, error: 'A sua senha está incorreta.');
      }
      if (e.code == 'email-already-in-use') {
        return (
          success: false,
          error: 'Esse e-mail já está em uso por outra conta do app.'
        );
      }
      return (success: false, error: _messageFor(e));
    }
  }

  /// Confere se a conta já tem e-mail de verdade e grava o sim/não.
  ///
  /// O endereço só muda quando a pessoa clica no link, e isso acontece fora
  /// do app — às vezes dias depois, no computador. Então não há momento certo
  /// para gravar: quem grava é esta conferência, na abertura do app.
  ///
  /// Devolve o e-mail de recuperação quando existe, para a tela poder
  /// mostrá-lo, e nulo quando a conta ainda está no endereço interno.
  static Future<String?> conferirEmailDeRecuperacao(UserModel user) async {
    final account = _auth.currentUser;
    final endereco = account?.email;
    if (account == null || endereco == null || endereco.isEmpty) return null;

    final temDeVerdade = !UserModel.enderecoInterno(endereco);
    if (temDeVerdade == user.recuperacaoPorEmail) {
      // Nada mudou: nenhuma escrita. Esta conferência roda em toda abertura
      // do app, e uma escrita por abertura por pessoa seria cota jogada fora.
      return temDeVerdade ? endereco : null;
    }

    try {
      await _db.collection(_collection).doc(user.id).update({
        'recuperacaoPorEmail': temDeVerdade,
      });
    } catch (_) {
      // Leitura da tela não depende disto: o que importa é o endereço, que
      // veio do Firebase. O campo no banco serve ao líder, e a próxima
      // abertura tenta de novo.
    }
    return temDeVerdade ? endereco : null;
  }

  // ─── Profile ──────────────────────────────────────────────────────────────

  static Future<bool> updateUser(UserModel user) async {
    try {
      await _db.collection(_collection).doc(user.id).update({
        'instrument': user.instrument.name,
        'instruments': user.instruments.map((f) => f.name).toList(),
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
    // Favorito é preferência PESSOAL: vale na hora e o Firestore envia quando
    // houver internet (a fila dele sobrevive a fechar o app). Esperar a
    // confirmação do servidor travava o coração sem sinal.
    final escrita = _db.collection(_collection).doc(user.id).update({
      'favoriteSongs': favorites,
    });
    await LocalStorageService.saveSession(updated);
    try {
      await escrita.timeout(const Duration(seconds: 2));
    } on TimeoutException {
      unawaited(escrita.catchError((Object _) {}));
    }
    return updated;
  }

  /// Quem está esperando o líder. Consulta filtrada de propósito: o resultado
  /// quase sempre vem vazio, e o selo em Perfil não pode custar a leitura da
  /// lista inteira de membros a cada abertura do app.
  @visibleForTesting
  static Stream<List<UserModel>>? pendentesParaTeste;

  static Stream<List<UserModel>> watchPendentes() {
    // Costura de teste: o roteiro que fotografa as telas não tem banco, e o
    // selo é desenhado dentro do `build`, onde falar com o Firestore lançaria.
    final falso = pendentesParaTeste;
    if (falso != null) return falso;
    return _db
        .collection(_collection)
        .where('role', isEqualTo: 'pendente')
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => UserModel.fromFirestore(doc.data()))
            .toList());
  }

  /// O próprio cadastro, em tempo real.
  ///
  /// É o que tira a pessoa da tela de espera no segundo em que o líder
  /// aprova. Sem isto ela ficaria olhando "aguarde" até fechar e abrir o app,
  /// sem nada na tela dizendo que precisa fazer isso.
  static Stream<UserModel?> watchUser(String id) {
    return _db.collection(_collection).doc(id).snapshots().map(
          (doc) => doc.exists ? UserModel.fromFirestore(doc.data()!) : null,
        );
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

  /// Quem pode ser escalado ou entrar numa equipe.
  ///
  /// Aprovados e SEM os robôs. A faxina do chat e o servidor dos avisos
  /// entram como líderes comuns — sem este filtro eles apareciam na lista de
  /// quem escalar, e dava para pôr o robô no teclado de domingo.
  ///
  /// `getAllUsers` continua existindo e continua trazendo todo mundo: a tela
  /// Membros precisa dos robôs, para o líder poder desmarcá-los.
  /// As pessoas escaláveis lidas UMA vez. Os nomes mudam raramente, e uma
  /// escuta sempre ligada relia os ~16 cadastros inteiros cada vez que o app
  /// voltava depois de mais de 30 minutos (ver `AuthProvider.prazoDasPessoas`).
  static Future<({List<UserModel> itens, bool doServidor})?>
      lerEscalaveisUmaVez() async {
    try {
      final snap = await _db.collection(_collection).orderBy('name').get();
      final doServidor = !snap.metadata.isFromCache;
      if (doServidor) {
        ContadorDeLeituras.instancia.umaVez('pessoas', snap.docs.length);
      }
      final lista = snap.docs
          .map((d) => UserModel.fromFirestore(d.data()))
          .where((u) => u.aprovado && !u.bot)
          .toList();
      return (itens: lista, doServidor: doServidor);
    } catch (_) {
      return null;
    }
  }

  static Stream<List<UserModel>> watchEscalaveis() =>
      watchEscalaveisComOrigem().map((r) => r.itens);

  /// As pessoas escaláveis, dizendo se a notificação veio do cache do aparelho
  /// (um vazio do cache não é resposta: ver `ignorarVazioDoCache`).
  static Stream<({List<UserModel> itens, bool doCache})>
      watchEscalaveisComOrigem() => _db
          .collection(_collection)
          .orderBy('name')
          .snapshots()
          .map((snap) => (
                itens: snap.docs
                    .map((d) => UserModel.fromFirestore(d.data()))
                    .where((u) => u.aprovado && !u.bot)
                    .toList(),
                doCache: snap.metadata.isFromCache,
              ));

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
  /// Quantos líderes DE VERDADE existem.
  ///
  /// Robô não conta. A faxina do chat e o servidor dos avisos entram como
  /// líderes comuns (este projeto não usa chave de administrador), e enquanto
  /// eles contavam aqui dava para remover a última pessoa de verdade — a
  /// proteção do último líder achava que ainda havia um. O ministério ficaria
  /// com um robô como único líder, e ninguém conseguiria aprovar mais nada.
  ///
  /// O filtro é no cliente, e não no `where`: documento antigo não tem o
  /// campo `bot`, e `where('bot', '!=', true)` NÃO devolve documento sem o
  /// campo — a consulta deixaria de fora justamente os líderes humanos
  /// antigos, que são os que precisam ser contados.
  static Future<int> adminCount() async {
    final snap = await _db
        .collection(_collection)
        .where('role', isEqualTo: 'admin')
        .get();
    return snap.docs.where((d) => d.data()['bot'] != true).length;
  }

  static Future<({bool success, String? error})> setUserRole(
    UserModel user,
    UserRole role,
  ) async {
    if (user.role == role) return (success: true, error: null);

    try {
      // Rebaixar o último líder deixaria o ministério sem ninguém capaz de
      // criar culto, aprovar membro ou cadastrar música — e sem ninguém capaz
      // de desfazer isso pelo app.
      //
      // A condição olha de ONDE a pessoa está saindo, não para onde vai. Antes
      // era `role == levita`, e isso tinha dois furos: rebaixar um líder para
      // `recusado` passava batido, e aprovar um pendente (que também vira
      // levita) era recusado com "o ministério precisa de pelo menos um
      // líder", numa igreja com um líder só — ou seja, em quase todas.
      if (user.isAdmin && role != UserRole.admin && await adminCount() <= 1) {
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
