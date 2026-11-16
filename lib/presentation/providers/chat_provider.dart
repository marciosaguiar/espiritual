import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../data/models/message_model.dart';
import '../../data/services/avisos_service.dart';
import '../../data/services/firestore_service.dart';

typedef TypingUser = ({String userId, String userName, DateTime updatedAt});

class ChatProvider extends ChangeNotifier {
  List<MessageModel> _messages = [];
  bool _isLoading = false;
  String? _error;
  List<TypingUser> _typing = [];

  StreamSubscription<List<MessageModel>>? _messagesSub;
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

  void listenToMessages() {
    if (_messagesSub != null) return;
    _isLoading = true;
    _messagesSub = FirestoreService.watchMessages().listen((messages) {
      _messages = messages;
      _isLoading = false;
      _error = null;
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

  @override
  void dispose() {
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
  }) async {
    if (text.trim().isEmpty) return 'Escreva algo antes de enviar.';

    final message = FirestoreService.createMessage(
      userId: userId,
      userName: userName,
      text: text.trim(),
      linkedSongId: linkedSongId,
      linkedSongName: linkedSongName,
    );

    final result = await FirestoreService.sendMessage(message);
    if (result.success) {
      // O aviso vem DEPOIS de a mensagem estar gravada, e de propósito sem
      // `await`: quem enviou já vê a mensagem na tela, e esperar o
      // mini-servidor da Cloudflare para isso seria atraso sem motivo. Uma
      // falha aqui não volta como erro — ver o comentário em AvisosService.
      AvisosService.avisarDoChat(message.id);
    }
    return result.error;
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
