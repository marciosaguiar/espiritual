import 'package:cloud_firestore/cloud_firestore.dart';

/// Onde o culto está AGORA: que música, que parte, que linha.
///
/// Um documento por culto, reescrito por cima. Não há histórico de propósito:
/// é posição, não registro — ninguém vai querer saber amanhã em que linha o
/// culto estava às 19h42.
///
/// O que viaja é POSIÇÃO LÓGICA, nunca pixels: a linha é um índice de âncora
/// (ver `MapaDaMusica`), que vale igual para quem lê a cifra e para quem lê
/// só a letra, em qualquer tela e qualquer fonte.
class EstadoAoVivo {
  /// Quem está conduzindo. Vazio = ninguém, e quem estiver no culto assume.
  final String condutorId;
  final String condutorNome;

  /// Índice da música na lista do culto.
  final int musica;

  /// Índice da linha de letra dentro da música.
  final int ancora;

  /// A parte ("Refrão") e o texto da linha, só para a tela mostrar e para
  /// conferir que os dois aparelhos estão na mesma versão da música.
  final String secao;
  final String texto;

  final DateTime atualizadoEm;

  /// Depois disto sem ninguém escrever, o comando fica livre.
  ///
  /// É a proteção contra o condutor cujo celular travou ou ficou sem bateria:
  /// sem ela, o culto inteiro ficaria preso esperando alguém que já não está
  /// mais ali. 45 s é mais que o intervalo de qualquer toque normal e menos
  /// que a paciência de quem está tocando.
  static const Duration silencioMaximo = Duration(seconds: 45);

  const EstadoAoVivo({
    this.condutorId = '',
    this.condutorNome = '',
    this.musica = 0,
    this.ancora = 0,
    this.secao = '',
    this.texto = '',
    required this.atualizadoEm,
  });

  bool get temCondutor => condutorId.isNotEmpty;

  /// O condutor ainda está dando sinal de vida?
  bool vivo(DateTime agora) =>
      temCondutor && agora.difference(atualizadoEm) < silencioMaximo;

  /// Dá para assumir o comando agora?
  ///
  /// Sim quando não há condutor, quando sou eu mesmo, ou quando o condutor
  /// calou há mais de [silencioMaximo]. A regra do banco faz a MESMA conta —
  /// esconder o botão não bastaria, e deixar só a regra decidir daria um
  /// toque que falha sem explicação.
  bool podeAssumir(String meuId, DateTime agora) =>
      !temCondutor || condutorId == meuId || !vivo(agora);

  bool souOCondutor(String meuId) => condutorId == meuId;

  EstadoAoVivo copyWith({
    String? condutorId,
    String? condutorNome,
    int? musica,
    int? ancora,
    String? secao,
    String? texto,
    DateTime? atualizadoEm,
  }) {
    return EstadoAoVivo(
      condutorId: condutorId ?? this.condutorId,
      condutorNome: condutorNome ?? this.condutorNome,
      musica: musica ?? this.musica,
      ancora: ancora ?? this.ancora,
      secao: secao ?? this.secao,
      texto: texto ?? this.texto,
      atualizadoEm: atualizadoEm ?? this.atualizadoEm,
    );
  }

  /// Mudou algo que vale uma escrita?
  ///
  /// `atualizadoEm` fica de fora: ele muda sempre, e comparar com ele faria
  /// toda batida do relógio virar escrita no banco.
  bool mesmaPosicaoQue(EstadoAoVivo outro) =>
      condutorId == outro.condutorId &&
      musica == outro.musica &&
      ancora == outro.ancora;

  Map<String, dynamic> toFirestore() => {
        'condutorId': condutorId,
        'condutorNome': condutorNome,
        'musica': musica,
        'ancora': ancora,
        'secao': secao,
        'texto': texto,
        // A hora é do SERVIDOR. Com o relógio do celular, um aparelho
        // adiantado deixaria o estado "vivo" para sempre, e ninguém mais
        // conseguiria assumir o comando.
        'atualizadoEm': FieldValue.serverTimestamp(),
      };

  factory EstadoAoVivo.fromFirestore(Map<String, dynamic> data) {
    return EstadoAoVivo(
      condutorId: data['condutorId'] as String? ?? '',
      condutorNome: data['condutorNome'] as String? ?? '',
      musica: (data['musica'] as num?)?.toInt() ?? 0,
      ancora: (data['ancora'] as num?)?.toInt() ?? 0,
      secao: data['secao'] as String? ?? '',
      texto: data['texto'] as String? ?? '',
      // `serverTimestamp` chega NULO na primeira notificação local, antes de
      // o servidor responder. Tratar como "agora" evita o estado nascer
      // velho e o comando ficar livre no primeiro instante.
      atualizadoEm:
          (data['atualizadoEm'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}

/// Segura as escritas em no máximo uma a cada [intervalo].
///
/// O condutor rolando a tela gera dezenas de mudanças por segundo. Sem
/// limite, um culto de uma hora com cinco músicas passaria da cota gratuita
/// do Firestore sozinho — e não há ganho nenhum: ninguém percebe a diferença
/// entre duas e vinte atualizações por segundo.
///
/// Só o tempo entra aqui, nada de `Timer`: é o que deixa isto testável sem
/// esperar de verdade.
class LimiteDeEscrita {
  /// 500 ms = no máximo 2 escritas por segundo.
  final Duration intervalo;
  DateTime? _ultima;

  LimiteDeEscrita({this.intervalo = const Duration(milliseconds: 500)});

  /// Quanto falta para a próxima escrita poder sair. Zero = pode agora.
  Duration espera(DateTime agora) {
    final ultima = _ultima;
    if (ultima == null) return Duration.zero;
    final passou = agora.difference(ultima);
    if (passou >= intervalo) return Duration.zero;
    // Relógio que andou para trás (fuso, sincronização) não pode virar uma
    // espera gigante: aí o condutor pararia de atualizar sem motivo.
    if (passou.isNegative) return Duration.zero;
    return intervalo - passou;
  }

  bool podeAgora(DateTime agora) => espera(agora) == Duration.zero;

  /// Avisa que uma escrita saiu agora.
  void registrou(DateTime agora) => _ultima = agora;

  void esquecer() => _ultima = null;
}
