import 'package:flutter/foundation.dart';

import '../../data/models/saude_model.dart';
import '../../data/services/saude_service.dart';

/// A saúde do sistema, carregada UMA VEZ por abertura do app.
///
/// Uma vez, e não em escuta: os carimbos mudam uma vez por dia, e uma escuta
/// sobre eles custaria leitura a cada reconexão para saber o que não mudou. O
/// líder que quiser conferir agora toca em "Conferir de novo".
///
/// Só para líder. Quem não aprova cadastro nem mexe na Cloudflare não tem o
/// que fazer com esta informação, e enchê-lo de diagnóstico é o jeito de ele
/// parar de ler a tela.
class SaudeProvider extends ChangeNotifier {
  SaudeDoSistema? _saude;
  bool _carregando = false;
  bool _jaTentou = false;

  SaudeDoSistema? get saude => _saude;
  bool get carregando => _carregando;

  /// Já houve uma tentativa nesta sessão? Evita recarregar a cada rebuild.
  bool get jaTentou => _jaTentou;

  /// Há algo quebrado que mereça o aviso vermelho no Início?
  bool get temAlarme => _saude?.temAlarme ?? false;

  ItemDeSaude? get pior => _saude?.pior;

  /// Carrega, se ainda não carregou nesta sessão.
  Future<void> carregarUmaVez() async {
    if (_jaTentou || _carregando) return;
    await conferir();
  }

  /// Carrega de novo, sempre. É o botão "Conferir de novo".
  Future<void> conferir() async {
    _carregando = true;
    _jaTentou = true;
    notifyListeners();

    final worker = await SaudeService.doWorker();
    final carimbos = await SaudeService.carimbos();

    _saude = SaudeDoSistema.avaliar(
      worker: worker,
      carimbos: carimbos,
      agora: DateTime.now(),
    );
    _carregando = false;
    notifyListeners();
  }
}
