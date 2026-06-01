import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../data/models/message_model.dart';
import '../../data/services/firestore_service.dart';

class ChatProvider extends ChangeNotifier {
  List<MessageModel> _messages = [];
  bool _isLoading = false;
  String? _error;

  StreamSubscription<List<MessageModel>>? _messagesSub;

  List<MessageModel> get messages => _messages;
  bool get isLoading => _isLoading;
  String? get error => _error;

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

  @override
  void dispose() {
    _messagesSub?.cancel();
    super.dispose();
  }

  Future<bool> sendMessage({
    required String userId,
    required String userName,
    required String text,
    String? linkedSongId,
    String? linkedSongName,
  }) async {
    if (text.trim().isEmpty) return false;

    final message = FirestoreService.createMessage(
      userId: userId,
      userName: userName,
      text: text.trim(),
      linkedSongId: linkedSongId,
      linkedSongName: linkedSongName,
    );

    return FirestoreService.sendMessage(message);
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
