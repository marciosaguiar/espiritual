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

  /// Quem reagiu, e com quê: `{uid: '🙏'}`.
  ///
  /// Mapa na PRÓPRIA mensagem, e não numa subcoleção, por causa de leitura:
  /// o chat já escuta `messages`, então as reações chegam de graça junto das
  /// bolhas. Numa subcoleção, cada bolha custaria uma escuta a mais — com 50
  /// mensagens na tela, 50 escutas.
  ///
  /// Uma reação por pessoa por mensagem: o mapa tem a chave da pessoa, não
  /// uma lista. Tocar no mesmo emoji tira a chave.
  final Map<String, String> reacoes;

  /// Respondendo a outra mensagem: o id, o nome de quem escreveu, e um
  /// PEDAÇO do texto dela.
  ///
  /// O pedaço é copiado de propósito — é o contrário da regra da escala, que
  /// guarda referência e nunca cópia, e por dois motivos: a mensagem
  /// original some em 30 dias (a citação ficaria vazia, perdendo o sentido
  /// do que foi respondido), e resolver por id custaria uma leitura por
  /// bolha na tela.
  final String? respondeA;
  final String? respondeANome;
  final String? respondeATexto;

  /// Quem foi mencionado com @nome.
  ///
  /// Guardado como lista de uid, e não lido do texto, porque nome se repete
  /// e muda. O Worker usa isto para avisar quem silenciou o chat.
  final List<String> mencoes;

  /// Escrita ainda não confirmada pelo servidor (enviada sem internet). NÃO
  /// vai para o banco: vem dos metadados do Firestore, e é o que põe o
  /// relógio na bolha.
  final bool pendente;

  /// Os cinco emojis que o app oferece.
  ///
  /// Lista fechada, e a mesma na regra do banco: sem isso, qualquer texto
  /// entraria no mapa de reações, inclusive um parágrafo inteiro.
  static const List<String> emojisDeReacao = ['👍', '🙏', '❤️', '🔥', '😂'];

  const MessageModel({
    this.pendente = false,
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
    this.reacoes = const {},
    this.respondeA,
    this.respondeANome,
    this.respondeATexto,
    this.mencoes = const [],
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

  /// Quantas pessoas reagiram com cada emoji, na ordem da lista oficial.
  ///
  /// Ordem fixa de propósito: contagem que muda de lugar a cada reação faz a
  /// pessoa tocar no emoji errado.
  List<({String emoji, int quantas})> get contagemDeReacoes {
    final contas = <String, int>{};
    for (final emoji in reacoes.values) {
      contas[emoji] = (contas[emoji] ?? 0) + 1;
    }
    return emojisDeReacao
        .where(contas.containsKey)
        .map((e) => (emoji: e, quantas: contas[e]!))
        .toList();
  }

  /// Com que emoji eu reagi, ou nulo.
  String? minhaReacao(String meuId) => reacoes[meuId];

  bool get temReacoes => reacoes.isNotEmpty;
  bool get temCitacao => respondeA != null;
  bool mencionou(String uid) => mencoes.contains(uid);

  MessageModel copyWith({
    bool? fixada,
    String? fixadaPor,
    DateTime? expiraEm,
    Map<String, String>? reacoes,
    bool limparFixacao = false,
  }) {
    return MessageModel(
      pendente: pendente,
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
      reacoes: reacoes ?? this.reacoes,
      respondeA: respondeA,
      respondeANome: respondeANome,
      respondeATexto: respondeATexto,
      mencoes: mencoes,
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
      // Só entram quando existem: mensagem simples não ganha campo novo, e a
      // regra do banco confere o que mudou, não o que está lá.
      if (reacoes.isNotEmpty) 'reacoes': reacoes,
      if (respondeA != null) 'respondeA': respondeA,
      if (respondeANome != null) 'respondeANome': respondeANome,
      if (respondeATexto != null) 'respondeATexto': respondeATexto,
      if (mencoes.isNotEmpty) 'mencoes': mencoes,
      'fixada': fixada,
      'fixadaPor': fixadaPor,
      // Nulo quando fixada: é o que a faxina lê para saber o que poupar.
      'expiraEm': expiraEm == null ? null : Timestamp.fromDate(expiraEm!),
    };
  }

  /// Lê o mapa de reações descartando o que não se reconhece.
  ///
  /// Emoji fora da lista é ignorado em vez de aparecer na bolha: a regra do
  /// banco já o recusa, mas um documento gravado antes dela, ou mexido no
  /// console, não pode desenhar lixo na tela de todo mundo.
  static Map<String, String> _reacoesDe(Object? bruto) {
    if (bruto is! Map) return const {};
    final saida = <String, String>{};
    bruto.forEach((k, v) {
      if (k is String && v is String && emojisDeReacao.contains(v)) {
        saida[k] = v;
      }
    });
    return saida;
  }

  static List<String> _listaDeTexto(Object? bruto) {
    if (bruto is! List) return const [];
    return bruto.whereType<String>().toList();
  }

  factory MessageModel.fromFirestore(Map<String, dynamic> data,
      {bool pendente = false}) {
    return MessageModel(
      pendente: pendente,
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
      reacoes: _reacoesDe(data['reacoes']),
      respondeA: data['respondeA'] as String?,
      respondeANome: data['respondeANome'] as String?,
      respondeATexto: data['respondeATexto'] as String?,
      mencoes: _listaDeTexto(data['mencoes']),
      fixada: data['fixada'] as bool? ?? false,
      fixadaPor: data['fixadaPor'] as String?,
      expiraEm: (data['expiraEm'] as Timestamp?)?.toDate(),
    );
  }
}
