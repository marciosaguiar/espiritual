import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/ao_vivo_model.dart';

/// O estado ao vivo de um culto: ler, e escrever sem estourar a cota.
///
/// Fica num documento só, dentro do culto: `scales/{id}/aoVivo/atual`. Dentro
/// do culto, e não numa coleção à parte, porque a regra do banco precisa
/// saber de qual culto se trata para decidir quem pode escrever.
class AoVivoService {
  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  static DocumentReference<Map<String, dynamic>> _doc(String cultoId) =>
      _db.collection('scales').doc(cultoId).collection('aoVivo').doc('atual');

  /// Escuta a posição do culto. Nulo enquanto ninguém abriu o modo ao vivo.
  static Stream<EstadoAoVivo?> escutar(String cultoId) {
    return _doc(cultoId).snapshots().map((d) {
      final dados = d.data();
      if (!d.exists || dados == null) return null;
      return EstadoAoVivo.fromFirestore(dados);
    });
  }

  /// Escreve a posição, respeitando o limite de uma escrita a cada 500 ms.
  ///
  /// COMO O LIMITE FUNCIONA, e por que não é só "ignorar o excesso":
  /// jogar fora a mudança que vem depressa demais deixaria os seguidores
  /// numa linha velha — a última rolagem do condutor, justamente a que
  /// importa, seria a descartada. Então a última posição fica guardada e sai
  /// sozinha quando o intervalo fecha. Chamar isto em rajada é seguro.
  final String cultoId;
  final LimiteDeEscrita _limite;
  EstadoAoVivo? _pendente;
  EstadoAoVivo? _ultimaEnviada;
  Timer? _agendado;
  String? _erro;

  AoVivoService.doCulto(this.cultoId, {Duration? intervalo})
      : _limite = LimiteDeEscrita(
            intervalo: intervalo ?? const Duration(milliseconds: 500));

  /// O motivo da última falha de escrita, ou nulo. A tela usa para avisar
  /// que a sincronização caiu, em vez de deixar todos achando que estão
  /// juntos.
  String? get erro => _erro;

  /// Marca a posição. Devolve na hora; a escrita pode sair depois.
  void publicar(EstadoAoVivo estado, {DateTime? agora}) {
    final momento = agora ?? DateTime.now();
    // Mesma posição não se reescreve: o relógio do estado muda sempre, e sem
    // esta conferência a tela parada geraria escrita a cada quadro.
    if (_pendente == null &&
        _ultimaEnviada != null &&
        _ultimaEnviada!.mesmaPosicaoQue(estado)) {
      return;
    }
    _pendente = estado;

    if (_limite.podeAgora(momento)) {
      _enviarAgora(momento);
      return;
    }
    _agendado ??= Timer(_limite.espera(momento), () {
      _agendado = null;
      _enviarAgora(DateTime.now());
    });
  }

  Future<void> _enviarAgora(DateTime momento) async {
    final estado = _pendente;
    if (estado == null) return;
    _pendente = null;
    _limite.registrou(momento);
    _ultimaEnviada = estado;
    try {
      await _doc(cultoId).set(estado.toFirestore());
      _erro = null;
    } on FirebaseException catch (e) {
      // Sem rede, ou outro condutor assumiu e a regra recusou. Os dois casos
      // interessam à tela: ela para de dizer que está sincronizada.
      _erro = e.code == 'permission-denied'
          ? 'Outra pessoa assumiu o comando.'
          : 'Sem conexão: os outros não estão vendo a sua rolagem.';
      _ultimaEnviada = null;
    }
  }

  /// Solta o comando: ninguém conduzindo, e quem estiver no culto assume.
  Future<String?> soltarComando(EstadoAoVivo atual) async {
    _agendado?.cancel();
    _agendado = null;
    _pendente = null;
    _limite.esquecer();
    try {
      await _doc(cultoId).set(atual
          .copyWith(condutorId: '', condutorNome: '')
          .toFirestore());
      return null;
    } on FirebaseException catch (e) {
      return e.message ?? e.code;
    }
  }

  /// Fecha o modo ao vivo neste aparelho.
  void dispose() {
    _agendado?.cancel();
    _agendado = null;
    _pendente = null;
  }
}
