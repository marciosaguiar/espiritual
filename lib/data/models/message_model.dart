import 'package:cloud_firestore/cloud_firestore.dart';

enum MessageType { text, song, system, audio }

class MessageModel {
  final String id;
  final String userId;
  final String userName;
  final String text;
  final MessageType type;
  final String? linkedSongId;
  final String? linkedSongName;
  final DateTime timestamp;

  /// Fixada pelo líder: não expira e aparece no topo do chat.
  ///
  /// O chat é conversa de combinação — "quem leva o cabo?", "ensaio às 19h" —
  /// e some depois de 30 dias de propósito. Fixar é como se diz "isto aqui
  /// não é recado do dia, é decisão".
  final bool fixada;
  final String? fixadaPor;

  /// Quando esta mensagem deixa de valer. Nulo em mensagem fixada.
  ///
  /// Guardado no documento, e não calculado na hora de ler, porque quem
  /// apaga é uma faxina que roda fora do app: ela precisa saber o prazo sem
  /// reimplementar a regra.
  final DateTime? expiraEm;

  /// Mensagem de voz: só a FICHA fica aqui.
  ///
  /// Os bytes moram em `audios/{audioId}`, um documento à parte, e só são
  /// baixados quando alguém toca no play. Juntos, cada abertura do chat
  /// baixaria todos os áudios da conversa — meio mega por minuto de voz,
  /// no 4G de quem só queria ler um recado.
  final String? audioId;
  final int? audioDuracaoMs;

  /// O formato em que foi gravado (`audio/mp4`, `audio/webm;codecs=opus`).
  ///
  /// Guardado porque o aparelho que toca pode não ser o que gravou: um
  /// iPhone antigo não toca webm. Com o formato à mão, a bolha diz que não
  /// toca, em vez de um play que não faz nada.
  final String? audioTipo;

  const MessageModel({
    required this.id,
    required this.userId,
    required this.userName,
    required this.text,
    this.type = MessageType.text,
    this.linkedSongId,
    this.linkedSongName,
    required this.timestamp,
    this.fixada = false,
    this.fixadaPor,
    this.expiraEm,
    this.audioId,
    this.audioDuracaoMs,
    this.audioTipo,
  });

  bool get temAudio => audioId != null;

  /// Duração no formato do WhatsApp: 0:07, 1:32.
  String get audioDuracao {
    final ms = audioDuracaoMs ?? 0;
    final total = (ms / 1000).round();
    final min = total ~/ 60;
    final seg = total % 60;
    return '$min:${seg.toString().padLeft(2, '0')}';
  }

  /// Quanto tempo uma conversa dura.
  static const Duration validade = Duration(days: 30);

  /// Já passou do prazo neste instante? Mensagem fixada nunca passa.
  ///
  /// Função pura: a tela esconde o que venceu já na próxima abertura, sem
  /// esperar a faxina. Assim a promessa "some depois de 30 dias" vale desde
  /// o primeiro dia, e a faxina cuida de apagar de verdade.
  bool venceu(DateTime agora) {
    if (fixada) return false;
    final prazo = expiraEm ?? timestamp.add(validade);
    return agora.isAfter(prazo);
  }

  MessageModel copyWith({
    bool? fixada,
    String? fixadaPor,
    DateTime? expiraEm,
    bool limparFixacao = false,
  }) {
    return MessageModel(
      id: id,
      userId: userId,
      userName: userName,
      text: text,
      type: type,
      linkedSongId: linkedSongId,
      linkedSongName: linkedSongName,
      timestamp: timestamp,
      audioId: audioId,
      audioDuracaoMs: audioDuracaoMs,
      audioTipo: audioTipo,
      fixada: limparFixacao ? false : (fixada ?? this.fixada),
      fixadaPor: limparFixacao ? null : (fixadaPor ?? this.fixadaPor),
      expiraEm: limparFixacao
          ? timestamp.add(validade)
          : (expiraEm ?? this.expiraEm),
    );
  }

  bool get hasSong => linkedSongId != null;

  Map<String, dynamic> toFirestore() {
    return {
      'id': id,
      'userId': userId,
      'userName': userName,
      'text': text,
      'type': type.name,
      'linkedSongId': linkedSongId,
      'linkedSongName': linkedSongName,
      'timestamp': Timestamp.fromDate(timestamp),
      'audioId': audioId,
      'audioDuracaoMs': audioDuracaoMs,
      'audioTipo': audioTipo,
      'fixada': fixada,
      'fixadaPor': fixadaPor,
      // Nulo quando fixada: é o que a faxina lê para saber o que poupar.
      'expiraEm': expiraEm == null ? null : Timestamp.fromDate(expiraEm!),
    };
  }

  factory MessageModel.fromFirestore(Map<String, dynamic> data) {
    return MessageModel(
      id: data['id'] as String,
      userId: data['userId'] as String,
      userName: data['userName'] as String,
      text: data['text'] as String,
      type: MessageType.values.firstWhere(
        (t) => t.name == (data['type'] as String? ?? 'text'),
        orElse: () => MessageType.text,
      ),
      linkedSongId: data['linkedSongId'] as String?,
      linkedSongName: data['linkedSongName'] as String?,
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      // Mensagem gravada antes desta mudança não tem os campos: não está
      // fixada, e o prazo sai do próprio horário dela.
      audioId: data['audioId'] as String?,
      audioDuracaoMs: (data['audioDuracaoMs'] as num?)?.toInt(),
      audioTipo: data['audioTipo'] as String?,
      fixada: data['fixada'] as bool? ?? false,
      fixadaPor: data['fixadaPor'] as String?,
      expiraEm: (data['expiraEm'] as Timestamp?)?.toDate(),
    );
  }
}
