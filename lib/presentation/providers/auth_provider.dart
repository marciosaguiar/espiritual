import 'dart:async';

import 'package:flutter/foundation.dart';
import '../../core/platform/marcas.dart';
import '../../core/utils/snapshot_local.dart';
import '../../data/models/arrangement_model.dart';
import '../../data/models/user_model.dart';
import '../../data/services/app_firebase.dart';
import '../../data/services/auth_service.dart';
import '../../data/services/firestore_service.dart';
import '../../data/services/avisos_service.dart';
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

  /// Entrou, mas ainda não passou pelo líder. Enquanto for verdade, o app
  /// mostra a tela de espera: as regras do banco não devolvem nada mesmo, e
  /// sem esta checagem a pessoa veria cinco abas vazias achando que quebrou.
  bool get pendente => _user?.isPendente ?? false;
  bool get removido => _user?.isRemovido ?? false;
  bool get aprovado => _user?.aprovado ?? false;

  StreamSubscription<UserModel?>? _meuCadastro;

  /// Fica de olho no próprio cadastro para a aprovação valer na hora.
  ///
  /// Sem isto, quem acabou de se cadastrar ficaria parado no "aguarde" mesmo
  /// depois de aprovado, até fechar e abrir o app — e nada na tela mandaria
  /// fazer isso. Vale também para o contrário: líder rebaixado perde as telas
  /// de líder no mesmo instante, sem precisar entrar de novo.
  void _ouvirProprioCadastro(String id) {
    _meuCadastro?.cancel();
    _meuCadastro = AuthService.watchUser(id).listen((perfil) {
      if (perfil == null || _user == null || perfil.id != _user!.id) return;
      if (perfil.role == _user!.role && perfil.name == _user!.name) return;

      final saiu = _user!.aprovado && !perfil.aprovado;
      _user = perfil;
      if (saiu) {
        // Cortar o acesso no banco não basta: o repertório salvo para tocar
        // sem internet continuaria no celular. Some junto.
        _prefs = {};
        LocalStorageService.limparTudoDoMinisterio();
        // E o aparelho continuaria recebendo aviso de cada mensagem do chat
        // de um ministério do qual a pessoa já não faz parte. A regra do
        // banco não pegaria isso: quem manda é o robô, que é líder.
        AvisosService.esquecerEsteAparelho();
      } else {
        LocalStorageService.saveSession(perfil);
      }
      notifyListeners();
    }, onError: (_) {
      // Leitura do próprio cadastro negada ou sem rede: a tela atual continua
      // valendo. Não há valor padrão seguro para inventar aqui.
    });
  }

  @override
  void dispose() {
    _relogioDasPessoas?.cancel();
    _escutaPessoas?.cancel();
    _meuCadastro?.cancel();
    super.dispose();
  }

  /// Restores the session on app start.
  ///
  /// Firebase keeps the signed-in account on the device, so it — not the local
  /// copy — decides whether someone is logged in. The local copy is only used
  /// to fill the screens while offline, when the profile cannot be fetched.
  Future<void> checkSession() async {
    // 1) Abre no cadastro guardado NO APARELHO, sem esperar o Firebase.
    //
    // O Firebase leva a abertura inteira para ligar (e, sem internet, bem
    // mais). A pessoa que já entrou antes tem o cadastro no celular: a tela
    // dela pode sair agora, com as músicas e a escala guardadas, e o Firebase
    // confirma logo em seguida. Se ele disser que não há conta (o iPhone
    // apagou a sessão, ou a pessoa saiu por outro aparelho), a tela de entrar
    // aparece — é o único caso em que o que se mostrou antes estava errado, e
    // não expõe nada: o que o banco guarda continua atrás das regras.
    var abriuPeloAparelho = false;
    if (!AppFirebase.ligado) {
      final guardado = LocalStorageService.getSession();
      if (guardado != null) {
        _user = guardado;
        _status = AuthStatus.authenticated;
        abriuPeloAparelho = true;
        marcar('sessao-resolvida');
        notifyListeners();
      }
    }

    final erroAoLigar = await AppFirebase.pronto;
    // Firebase fora do ar: `main` troca o app pela tela que explica. Seguir
    // aqui só falaria com um SDK que não existe.
    if (erroAoLigar != null) return;

    final account = AuthService.currentAuthUser;

    if (account == null) {
      // No account: drop any profile left over from an older version.
      await LocalStorageService.clearSession();
      _user = null;
      _status = AuthStatus.unauthenticated;
      marcar('sessao-resolvida');
      notifyListeners();
      return;
    }

    // Opens on the cached profile, without waiting for the network.
    //
    // This used to set `loading` and then await a Firestore read before
    // releasing the screen, so every start showed the splash for as long as
    // that round trip took — seconds on mobile data, with the profile already
    // on the device. An installed web app is reloaded by the system more often
    // than a native one, and each reload paid that price again.
    //
    // O cadastro guardado só vale se for DESTA conta: outra pessoa pode ter
    // entrado neste aparelho depois.
    var cached = LocalStorageService.getSession();
    if (cached != null && cached.id != account.uid) cached = null;
    if (cached != null) {
      _user = cached;
      _status = AuthStatus.authenticated;
      if (!abriuPeloAparelho) marcar('sessao-resolvida');
      notifyListeners();
    } else {
      // Nothing cached: there is no screen to show yet, so the wait is real.
      _user = null;
      _status = AuthStatus.loading;
      notifyListeners();
    }

    // Now refresh from the server, with the app already usable.
    final fresh = await AuthService.getUserById(account.uid);

    if (fresh == null && cached == null) {
      _errorMessage =
          'Não foi possível carregar seu perfil. Verifique a internet.';
      _status = AuthStatus.unauthenticated;
      notifyListeners();
      return;
    }

    final profile = fresh ?? cached!;
    _user = profile;
    _status = AuthStatus.authenticated;
    await LocalStorageService.saveSession(profile);
    _ouvirProprioCadastro(profile.id);
    notifyListeners();

    await conferirRecuperacao();
    await _loadPrefs(profile.id);
  }

  /// As pessoas do ministério, para resolver NOME por id.
  ///
  /// Uma escuta só, no app todo, e é economia: o chat já abria a dele, e a
  /// Escala e o Início passaram a precisar da mesma lista para dizer quem
  /// falta confirmar. Três escutas sobre ~15 documentos custariam o triplo de
  /// leitura pela mesma informação.
  ///
  /// Por que resolver por id e não ler o nome gravado no culto: o gerador da
  /// agenda fixa monta o culto a partir da equipe, que guarda só ids, e grava
  /// `userName` vazio. E nome copiado dentro do culto fica errado quando a
  /// pessoa corrige o próprio nome.
  List<UserModel> _pessoas = const [];
  List<UserModel> get pessoas => _pessoas;

  Map<String, String> _nomes = const {};

  /// Nome de cada pessoa, por id. É o que as telas passam para
  /// `ScaleLevita.nomeCom`.
  Map<String, String> get nomes => _nomes;

  StreamSubscription<List<UserModel>>? _escutaPessoas;

  void ouvirPessoas() {
    _escutaPessoas?.cancel();
    _escutaPessoas = AuthService.watchEscalaveis().listen((lista) {
      _pessoas = lista;
      _nomes = {for (final p in lista) p.id: p.name};
      _guardarPessoas();
      notifyListeners();
    }, onError: (_) {
      // Sem a lista, as telas caem no nome copiado dentro do culto e, na
      // falta dele, em "Alguém". É leitura com valor padrão seguro.
    });
  }

  Timer? _relogioDasPessoas;

  void _guardarPessoas() {
    _relogioDasPessoas?.cancel();
    _relogioDasPessoas = Timer(const Duration(seconds: 2), () {
      SnapshotLocal.guardar('pessoas', _pessoas.map((p) => p.toJson()).toList());
    });
  }

  /// Põe na tela os nomes que o aparelho guardou, antes de o banco responder.
  /// Sem isto o cartão do culto diria "Alguém" no lugar de cada nome até a
  /// primeira resposta do servidor.
  Future<int> restaurarPessoasDoAparelho() async {
    final docs = await SnapshotLocal.ler('pessoas');
    if (docs == null || _pessoas.isNotEmpty) return 0;
    try {
      _pessoas = [for (final d in docs) UserModel.fromJson(d)];
    } catch (_) {
      return 0;
    }
    _nomes = {for (final p in _pessoas) p.id: p.name};
    notifyListeners();
    return _pessoas.length;
  }

  /// O e-mail de recuperação desta conta, ou nulo quando ela ainda usa o
  /// endereço interno (`nome@levitas.app`), que não recebe e-mail nenhum.
  String? _emailDeRecuperacao;
  String? get emailDeRecuperacao => _emailDeRecuperacao;

  /// Confere no Firebase se a conta já tem e-mail de verdade.
  ///
  /// Roda na abertura do app porque o endereço muda FORA do app: a pessoa
  /// cadastra aqui, recebe um link e clica nele quando quiser — às vezes dias
  /// depois, no computador. Não existe momento melhor para descobrir.
  Future<void> conferirRecuperacao() async {
    final u = _user;
    if (u == null) return;
    final email = await AuthService.conferirEmailDeRecuperacao(u);
    if (email == _emailDeRecuperacao) return;
    _emailDeRecuperacao = email;
    notifyListeners();
  }

  /// Cadastra ou troca o e-mail de recuperação. Nulo quando dá certo.
  Future<String?> definirEmailDeRecuperacao({
    required String email,
    required String senhaAtual,
  }) async {
    final u = _user;
    if (u == null) return 'Entre novamente para cadastrar o e-mail.';
    final r = await AuthService.definirEmailDeRecuperacao(
      user: u,
      email: email,
      senhaAtual: senhaAtual,
    );
    return r.error;
  }

  /// Register new user
  Future<bool> register({
    required String name,
    required String password,
    UserInstrument instrument = UserInstrument.other,
    List<UserInstrument>? instruments,
    String? emailDeRecuperacao,
  }) async {
    _status = AuthStatus.loading;
    _errorMessage = null;
    notifyListeners();

    final result = await AuthService.register(
      name: name,
      password: password,
      instrument: instrument,
      instruments: instruments,
    );

    if (result.success && result.user != null) {
      _user = result.user;
      _status = AuthStatus.authenticated;
      _ouvirProprioCadastro(result.user!.id);

      // O e-mail do cadastro é opcional e NÃO pode derrubar a criação da
      // conta: se o envio falhar, a pessoa entrou e resolve isso depois em
      // Perfil. Falhar aqui seria perder a conta por causa de um extra.
      final email = emailDeRecuperacao?.trim() ?? '';
      if (email.isNotEmpty) {
        await AuthService.definirEmailDeRecuperacao(
          user: result.user!,
          email: email,
          senhaAtual: password,
        );
      }

      // Avisa os líderes. Sem isto, um cadastro novo ficava esperando até
      // alguém abrir a tela Membros por conta própria — e quem espera
      // aprovação não vê nada do app, então o silêncio parece defeito.
      await AvisosService.avisarPedidoDeEntrada();

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
      _ouvirProprioCadastro(result.user!.id);
      notifyListeners();
      await conferirRecuperacao();
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
    // Antes de desconectar: a escuta do próprio cadastro passaria a ler sem
    // conta, as regras recusariam, e sobraria um erro no console a cada saída.
    await _meuCadastro?.cancel();
    _meuCadastro = null;
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
    // O toque pode vir antes de o banco terminar de ligar (a abertura sai com
    // a cópia do aparelho); a escrita espera, o app não.
    await AppFirebase.pronto;
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

    await AppFirebase.pronto;
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

  /// Tons e anotações: primeiro o que o aparelho já tem (na hora, sem rede),
  /// depois o servidor — e só substitui se ele de fato respondeu. Uma falha de
  /// rede não pode esvaziar os tons que a pessoa já via.
  Future<void> _loadPrefs(String userId) async {
    final doAparelho = await FirestoreService.getPrefsDoAparelho(userId);
    if (doAparelho.isNotEmpty && _prefs.isEmpty) {
      _prefs = doAparelho;
      notifyListeners();
    }
    final doServidor = await FirestoreService.lerPrefsDoServidor(userId);
    if (doServidor != null) {
      _prefs = doServidor;
      notifyListeners();
    }
  }

  /// Update user profile
  Future<bool> updateProfile({
    UserInstrument? instrument,
    List<UserInstrument>? instruments,
    String? photoUrl,
    ModoLeitura? leitura,
  }) async {
    if (_user == null) return false;
    final updated = _user!.copyWith(
      instrument: instrument,
      instruments: instruments,
      photoUrl: photoUrl,
      leitura: leitura,
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
