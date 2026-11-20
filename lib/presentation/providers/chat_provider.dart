import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../core/utils/crypto_utils.dart';
import '../../core/utils/origem_do_dado.dart';
import '../../core/utils/snapshot_local.dart';
import '../../data/models/aviso_de_sincronia.dart';
import '../../data/models/message_model.dart';
import '../../data/services/avisos_de_sincronia.dart';
import '../../data/services/avisos_service.dart';
import '../../data/services/firestore_service.dart';

typedef TypingUser = ({String userId, String userName, DateTime updatedAt});

class ChatProvider extends ChangeNotifier {
  List<MessageModel> _messages = [];
  bool _isLoading = false;
  String? _error;
  List<TypingUser> _typing = [];

  StreamSubscription<({List<MessageModel> itens, bool doCache})>? _messagesSub;
  StreamSubscription<List<TypingUser>>? _typingSub;

  /// A conversa: o que ainda não venceu, fixadas incluídas.
  ///
  /// Esconder aqui faz a promessa "some depois de 30 dias" valer já na
  /// próxima abertura do app, sem depender da faxina que apaga de verdade.
  /// Se a faxina parar, a conversa continua sumindo da tela — o pior caso é
  /// ocupar banco, não mostrar recado velho.
  List<MessageModel> get messages {
    final agora = DateTime.now();
    return _messages.where((m) => !m.venceu(agora)).toList();
  }

  /// As fixadas, que vão no topo do chat e não vencem.
  List<MessageModel> get fixadas =>
      _messages.where((m) => m.fixada).toList();

  /// Fixar/desafixar. Devolve null quando dá certo, ou o motivo.
  Future<String?> fixar(MessageModel mensagem, bool fixar, String porQuemId) async {
    final r = await FirestoreService.fixarMensagem(mensagem, fixar, porQuemId);
    return r.error;
  }
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// Users currently typing (best-effort, filtered for freshness by callers).
  List<TypingUser> get typing => _typing;

  /// Põe mensagens na memória sem falar com o banco (testes e captura de
  /// telas).
  @visibleForTesting
  void carregarParaTeste(List<MessageModel> mensagens) {
    _messages = mensagens;
    _isLoading = false;
    _error = null;
    notifyListeners();
  }

  void listenToMessages({Stream<({List<MessageModel> itens, bool doCache})>? fonte}) {
    if (_messagesSub != null) return;
    _isLoading = true;
    _messagesSub = (fonte ?? FirestoreService.watchMessagesComOrigem()).listen((r) {
      // Vazio vindo do cache não é resposta: não apaga a conversa da tela.
      if (ignorarVazioDoCache(
          doCache: r.doCache, vazio: r.itens.isEmpty, jaTemDados: _messages.isNotEmpty)) {
        return;
      }
      final messages = r.itens;
      _messages = messages;
      _isLoading = false;
      _error = null;
      if (!r.doCache) _guardarNoAparelho(messages);
      notifyListeners();
    }, onError: (e) {
      _isLoading = false;
      _error = 'Erro ao carregar mensagens';
      notifyListeners();
    });
  }

  void listenToTyping() {
    if (_typingSub != null) return;
    _typingSub = FirestoreService.watchTyping().listen((list) {
      _typing = list;
      notifyListeners();
    }, onError: (e) {
      // Presence is best-effort; ignore.
    });
  }

  Future<void> setTyping({
    required String userId,
    required String userName,
    required bool typing,
  }) {
    return FirestoreService.setTyping(
      userId: userId,
      userName: userName,
      typing: typing,
    );
  }

  /// Drops the listener and attaches a new one.
  ///
  /// The listener guards against stacking subscriptions, so after a failure it
  /// would never reconnect on its own — "Tentar de novo" needs this.
  void retry() {
    _messagesSub?.cancel();
    _messagesSub = null;
    _error = null;
    notifyListeners();
    listenToMessages();
  }

  Timer? _relogioDaCopia;

  void _guardarNoAparelho(List<MessageModel> mensagens) {
    _relogioDaCopia?.cancel();
    _relogioDaCopia = Timer(const Duration(seconds: 2), () {
      // Só o que já chegou ao banco: guardar uma mensagem que ainda espera
      // (e pode ser recusada) a faria reaparecer, já "enviada", na próxima
      // abertura.
      SnapshotLocal.guardar('mensagens', [
        for (final m in mensagens)
          if (!m.pendente) m.toFirestore(),
      ]);
    });
  }

  /// Põe na tela a conversa que o aparelho guardou, antes de o banco
  /// responder. Devolve quantas mensagens eram.
  Future<int> restaurarDoAparelho() async {
    final docs = await SnapshotLocal.ler('mensagens');
    if (docs == null || _messages.isNotEmpty) return 0;
    try {
      _messages = [for (final d in docs) MessageModel.fromFirestore(d)];
    } catch (_) {
      return 0;
    }
    _isLoading = false;
    notifyListeners();
    return _messages.length;
  }

  @override
  void dispose() {
    _relogioDaCopia?.cancel();
    _messagesSub?.cancel();
    _typingSub?.cancel();
    super.dispose();
  }

  /// Sends a message. Returns null on success, or the message to show.
  ///
  /// A failed send used to vanish: the bubble never appeared and nothing said
  /// why, which with no connection is most of the time.
  Future<String?> sendMessage({
    required String userId,
    required String userName,
    required String text,
    String? linkedSongId,
    String? linkedSongName,
    MessageModel? respondendoA,
    List<String> mencoes = const [],
  }) async {
    if (text.trim().isEmpty) return 'Escreva algo antes de enviar.';

    final message = FirestoreService.createMessage(
      userId: userId,
      userName: userName,
      text: text.trim(),
      linkedSongId: linkedSongId,
      linkedSongName: linkedSongName,
      respondendoA: respondendoA,
      mencoes: mencoes,
    );

    // O aviso vem DEPOIS de a mensagem estar gravada, e de propósito sem
    // `await`: quem enviou já vê a mensagem na tela, e esperar o
    // mini-servidor da Cloudflare para isso seria atraso sem motivo. Uma
    // falha aqui não volta como erro — ver o comentário em AvisosService.
    //
    // Sem internet a mensagem fica na fila do próprio Firestore (que
    // sobrevive a fechar o app), aparece com o relógio de "pendente" e o
    // aviso sai quando ela chegar. Se chegar mais de 2 minutos depois o
    // servidor dos avisos recusa — é a trava dele contra reavisar mensagem
    // velha, e está certa: ninguém quer o "oi" de uma hora atrás.
    final result = await FirestoreService.sendMessage(
      message,
      aoConfirmar: () => AvisosService.avisarDoChat(message.id),
      aoFalhar: (erro) => _mensagemNaoEnviada(message, erro),
    );
    if (result.success && !result.pendente) {
      AvisosService.avisarDoChat(message.id);
    }
    return result.error;
  }

  /// O banco recusou uma mensagem que estava esperando a internet. Ela some
  /// da tela, e a pessoa não pode ficar sem saber: o aviso guarda o texto para
  /// ela poder copiar e mandar de novo.
  void _mensagemNaoEnviada(MessageModel m, String erro) {
    final texto = m.text.length > 160 ? '${m.text.substring(0, 160)}…' : m.text;
    AvisosDeSincronia.instancia.adicionar([
      AvisoDeSincronia(
        id: CryptoUtils.generateId(),
        tipo: TipoDeRecado.acaoNaoEnviada,
        criadoEm: DateTime.now(),
        titulo: 'Uma mensagem do chat não foi enviada',
        texto: '$erro\n\nO que você escreveu: "$texto"',
      ),
    ]);
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
