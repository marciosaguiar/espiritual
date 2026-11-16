import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/leitura_do_chat.dart';

/// Até onde cada pessoa leu o chat. É o que acende os dois tiques azuis.
class LeiturasService {
  LeiturasService._();

  static const String _colecao = 'chatLeituras';
  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  /// Até quando este aparelho já marcou como lido.
  ///
  /// Guardado na memória para não escrever duas vezes a mesma coisa: o chat
  /// chama `marcarLido` a cada mensagem que chega, e sem esta conferência
  /// uma conversa animada viraria uma escrita por mensagem recebida, vezes
  /// cada pessoa com o chat aberto.
  static DateTime? _jaMarcado;

  /// Com quantas pessoas o ministério tem para ler. ~15 documentos: a escuta
  /// custa uma leitura por documento ao começar, e uma por mudança.
  static Stream<List<LeituraDoChat>> escutar() {
    return _db.collection(_colecao).snapshots().map((s) =>
        s.docs.map((d) => LeituraDoChat.fromFirestore(d.data())).toList());
  }

  /// Marca o chat como lido até a mensagem mais recente.
  ///
  /// Não devolve erro: é marcador de leitura, não conteúdo. Se falhar, o pior
  /// caso é alguém continuar aparecendo como "ainda não viu" — e isso se
  /// conserta na próxima abertura. Avisar na tela seria assustar sem ter o
  /// que fazer.
  static Future<void> marcarLido({
    required String userId,
    required String userName,
    required DateTime? ultimaMensagem,
  }) async {
    if (userId.isEmpty || ultimaMensagem == null) return;
    final jaMarcado = _jaMarcado;
    if (jaMarcado != null && !ultimaMensagem.isAfter(jaMarcado)) return;
    _jaMarcado = ultimaMensagem;
    try {
      await _db.collection(_colecao).doc(userId).set(LeituraDoChat(
            userId: userId,
            userName: userName,
            lidoAte: ultimaMensagem,
          ).toFirestore());
    } catch (_) {
      // Sem rede: tenta de novo na próxima mensagem.
      _jaMarcado = jaMarcado;
    }
  }

  /// Esquece o que já foi marcado. Usado ao sair da conta, para a próxima
  /// pessoa que entrar no mesmo aparelho não herdar o marcador.
  static void esquecer() => _jaMarcado = null;
}
