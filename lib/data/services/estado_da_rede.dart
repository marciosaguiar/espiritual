import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/platform/armazem.dart';
import '../../core/platform/rede.dart';
import '../../core/utils/frescor.dart';

/// O que o app sabe da internet, num lugar só.
///
/// Junta três coisas que sozinhas enganam:
/// - `navigator.onLine` (palpite do navegador: "falso" é quase sempre
///   verdade, "verdadeiro" pode ser mentira num sinal ruim);
/// - a última vez que o BANCO respondeu de fato (um snapshot que não veio do
///   cache) — essa é a prova de que os dados estão em dia;
/// - o que está na fila esperando para ser enviado.
///
/// "Atualizado há X" é a idade da última prova. Estando conectado e com uma
/// escuta aberta, o banco nos avisa de qualquer mudança — então o dado está em
/// dia até o instante em que a conexão caiu, e é esse instante que importa.
/// Por isso, enquanto há internet E o banco já respondeu nesta abertura, a
/// "última conferência" é empurrada para agora a cada minuto; ao cair, ela
/// congela, e a idade passa a crescer.
class EstadoDaRede extends ChangeNotifier {
  EstadoDaRede._();
  static final EstadoDaRede instancia = EstadoDaRede._();

  static const _chave = 'rede:ultima-conferencia';

  bool _online = true;
  DateTime? _offlineDesde;
  DateTime? _ultimaConferencia;
  bool _bancoRespondeuNestaAbertura = false;
  bool _iniciado = false;
  StreamSubscription<bool>? _assinatura;
  Timer? _relogio;

  bool get online => _online;
  DateTime? get offlineDesde => _offlineDesde;
  DateTime? get ultimaConferencia => _ultimaConferencia;

  /// Liga as escutas. Seguro de chamar de novo.
  Future<void> iniciar() async {
    if (_iniciado) return;
    _iniciado = true;
    _online = Rede.online;
    if (!_online) _offlineDesde = DateTime.now();
    final guardada = await Armazem.ler(_chave);
    if (guardada != null) {
      _ultimaConferencia = DateTime.tryParse(guardada)?.toLocal();
    }
    _assinatura = Rede.mudancas.listen(_aoMudar);
    _relogio = Timer.periodic(const Duration(minutes: 1), (_) => _batida());
    notifyListeners();
  }

  void _aoMudar(bool online) {
    if (online == _online) return;
    _online = online;
    _offlineDesde = online ? null : DateTime.now();
    notifyListeners();
  }

  /// O banco respondeu DE VERDADE (resposta do servidor, não do cache).
  void bancoRespondeu() {
    _bancoRespondeuNestaAbertura = true;
    _marcarConferencia();
  }

  void _batida() {
    if (_online && _bancoRespondeuNestaAbertura) _marcarConferencia();
  }

  void _marcarConferencia() {
    final agora = DateTime.now();
    // Não regrava o armazém a cada resposta: de minuto em minuto basta.
    final gravar = _ultimaConferencia == null ||
        agora.difference(_ultimaConferencia!) > const Duration(seconds: 50);
    _ultimaConferencia = agora;
    if (gravar) Armazem.gravar(_chave, agora.toUtc().toIso8601String());
    notifyListeners();
  }

  SituacaoDaRede situacao({int pendentes = 0, DateTime? pendenteDesde}) =>
      SituacaoDaRede(
        online: _online,
        offlineDesde: _offlineDesde,
        ultimaConferencia: _ultimaConferencia,
        pendentes: pendentes,
        pendenteDesde: pendenteDesde,
      );

  @visibleForTesting
  void definirParaTeste({
    bool online = true,
    DateTime? offlineDesde,
    DateTime? ultimaConferencia,
  }) {
    _online = online;
    _offlineDesde = offlineDesde;
    _ultimaConferencia = ultimaConferencia;
    notifyListeners();
  }

  @override
  void dispose() {
    _assinatura?.cancel();
    _relogio?.cancel();
    super.dispose();
  }
}
