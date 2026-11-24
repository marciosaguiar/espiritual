import 'package:flutter/foundation.dart';

import '../../data/services/biblia_service.dart';
import '../../data/services/local_storage_service.dart';

/// A tela da Bíblia inteira depende deste provider, e ele é criado só quando
/// a tela abre — não em `main.dart`, junto dos outros. É o que garante que a
/// Bíblia não custe nada a quem nunca a abre.
class BibliaProvider extends ChangeNotifier {
  Traducao? _traducao;
  bool _carregando = false;
  String? _erro;
  double _fonte = LocalStorageService.fonteBiblia;

  Traducao? get traducao => _traducao;
  bool get carregando => _carregando;
  String? get erro => _erro;
  double get fonte => _fonte;

  /// Qual tradução está aberta, mesmo antes de o texto chegar.
  String _idAtual = traducoesDisponiveis.first.id;
  String get idAtual => _idAtual;

  TraducaoDisponivel get descricaoAtual => traducoesDisponiveis
      .firstWhere((t) => t.id == _idAtual,
          orElse: () => traducoesDisponiveis.first);

  /// Abre a última tradução lida neste aparelho, ou a primeira da lista.
  Future<void> iniciar() async {
    final ultima = LocalStorageService.getUltimaLeitura();
    final id = ultima?.traducao;
    final existe = id != null && traducoesDisponiveis.any((t) => t.id == id);
    await trocarTraducao(existe ? id : traducoesDisponiveis.first.id);
  }

  Future<void> trocarTraducao(String id) async {
    if (_traducao?.id == id && _erro == null) return;
    _idAtual = id;
    _carregando = true;
    _erro = null;
    notifyListeners();

    try {
      _traducao = await BibliaService.carregar(id);
      _erro = null;
    } catch (e) {
      // Sem valor padrão seguro: uma Bíblia vazia seria lida como "não tem
      // nada aqui", e o que houve foi uma falha ao baixar.
      _traducao = null;
      _erro = 'Não foi possível abrir esta tradução. '
          'Confira a internet e tente de novo.';
    }
    _carregando = false;
    notifyListeners();
  }

  /// Só para os testes de tela: põe uma tradução pronta, sem ler o arquivo.
  @visibleForTesting
  void carregarParaTeste(Traducao t) {
    _traducao = t;
    _idAtual = t.id;
    _carregando = false;
    _erro = null;
    notifyListeners();
  }

  Future<void> mudarFonte(double tamanho) async {
    _fonte = tamanho.clamp(13, 30);
    notifyListeners();
    await LocalStorageService.salvarFonteBiblia(_fonte);
  }

  Future<void> marcarLeitura(String livro, int capitulo) =>
      LocalStorageService.salvarUltimaLeitura(
        traducao: _idAtual,
        livro: livro,
        capitulo: capitulo,
      );

  /// Onde a pessoa parou, para a tela oferecer "continuar lendo".
  ({String traducao, String livro, int capitulo})? get ultimaLeitura =>
      LocalStorageService.getUltimaLeitura();
}
