import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/constants/hinarios.dart';
import '../../core/platform/rede.dart';
import '../../core/utils/importar_hinario.dart';
import '../../data/models/hino_da_biblioteca.dart';
import '../../data/models/song_model.dart';
import '../../data/services/firestore_service.dart';
import '../../data/services/hinos_locais.dart';
import '../../data/services/local_storage_service.dart';
import '../../core/utils/crypto_utils.dart';

/// A biblioteca de hinários: o texto que o líder importou.
///
/// Fica separada de `SongsProvider` de propósito. O repertório é escutado
/// INTEIRO, em tempo real, e é isso que torna caro pôr 1.200 hinos nele (ver
/// [HinoDaBiblioteca]). Aqui nada é escutado: o índice de cada hinário é lido
/// uma vez e guardado em memória, e a letra só é lida quando alguém abre
/// aquele hino.
typedef LeitorDeIndice = Future<({IndiceDoHinario? indice, String? error})>
    Function(String hinarioId);

typedef LeitorDeHino = Future<({HinoDaBiblioteca? hino, String? error})>
    Function(String hinarioId, int numero);

typedef LeitorDeLetras = Future<({Map<int, String>? letras, String? error})>
    Function(String hinarioId);

typedef GravadorDeHinos = Future<({int gravados, String? error})> Function({
  required Hinario hinario,
  required List<HinoLido> hinos,
  required String porQuemId,
  void Function(int feitos, int total)? aoAvancar,
});

typedef GravadorDeMusica = Future<({bool success, String? error})> Function(
    SongModel musica);

class BibliotecaProvider extends ChangeNotifier {
  /// As quatro funções que falam com o banco e o relógio podem ser trocadas.
  ///
  /// Só os testes trocam. É o que permite provar o que os comentários
  /// prometem — "número fora do índice custa zero leituras", "o índice é lido
  /// uma vez" — contando as chamadas, em vez de acreditar na leitura do
  /// código: leitura é a cota que aperta neste projeto.
  BibliotecaProvider({
    LeitorDeIndice? lerIndice,
    LeitorDeHino? lerHino,
    GravadorDeHinos? gravarHinos,
    GravadorDeMusica? gravarMusica,
    LeitorDeLetras? lerLetras,
    DateTime Function()? agora,
  })  : _lerLetrasNoBanco = lerLetras ?? FirestoreService.lerTodasAsLetras,
        _lerIndiceNoBanco = lerIndice ?? FirestoreService.lerIndiceDoHinario,
        _lerHinoNoBanco = lerHino ?? FirestoreService.lerHinoDaBiblioteca,
        _gravarHinos = gravarHinos ?? FirestoreService.importarHinario,
        _gravarMusica = gravarMusica ?? FirestoreService.addSong,
        _agora = agora ?? DateTime.now;

  final LeitorDeLetras _lerLetrasNoBanco;
  final LeitorDeIndice _lerIndiceNoBanco;
  final LeitorDeHino _lerHinoNoBanco;
  final GravadorDeHinos _gravarHinos;
  final GravadorDeMusica _gravarMusica;
  final DateTime Function() _agora;

  /// Depois deste tempo o índice é lido de novo.
  ///
  /// Sem isso, um celular com o app aberto desde antes da importação nunca
  /// saberia dos hinos novos: o líder importaria o hinário e o levita
  /// continuaria vendo "ainda não está no repertório" até fechar o app. Vinte
  /// minutos é uma leitura por hinário a cada vinte — nada perto da cota.
  static const Duration validadeDoIndice = Duration(minutes: 20);

  final Map<String, IndiceDoHinario> _indices = {};
  final Map<String, DateTime> _carregadoEm = {};
  final Map<String, Future<String?>> _carregando = {};
  final Map<String, HinoDaBiblioteca> _hinos = {};

  /// Os títulos que já foram lidos. Vazio enquanto não foram — quem precisa
  /// distinguir "ainda não li" de "li e está vazio" usa [indiceCarregado].
  IndiceDoHinario indiceDe(String hinarioId) =>
      _indices[hinarioId] ?? IndiceDoHinario.vazio(hinarioId);

  bool indiceCarregado(String hinarioId) => _indices.containsKey(hinarioId);

  bool _venceu(String hinarioId, DateTime agora) {
    final quando = _carregadoEm[hinarioId];
    return quando == null || agora.difference(quando) > validadeDoIndice;
  }

  /// Lê o índice, se ainda não foi lido ou se já venceu. Devolve null quando
  /// dá certo, ou o motivo.
  ///
  /// Duas chamadas ao mesmo tempo esperam a MESMA leitura: o teclado e a tela
  /// de importar podem pedir juntos, e duas leituras do mesmo documento seria
  /// cota jogada fora.
  Future<String?> carregarIndice(String hinarioId, {bool forcar = false}) {
    if (!forcar && !_venceu(hinarioId, _agora())) {
      return Future.value(null);
    }
    // Uma atualização em segundo plano já está a caminho: não há por que
    // pedir outra, nem por que esperar por ela.
    if (!forcar && _atualizando.contains(hinarioId)) return Future.value(null);
    return _carregando[hinarioId] ??= _lerIndice(hinarioId, forcar);
  }

  final Set<String> _atualizando = {};
  final Map<String, Future<String?>> _atualizacoes = {};

  /// Espera as atualizações do índice que estão rodando em segundo plano.
  /// A tela nunca precisa disto (ela se atualiza sozinha quando chegam); é
  /// para os testes e para quem precisa saber que o banco já respondeu.
  Future<void> aguardarAtualizacoes() async {
    await Future.wait(_atualizacoes.values.toList());
  }

  Future<String?> _lerIndice(String hinarioId, bool forcar) async {
    try {
      // 1) Primeira vez nesta abertura do app: o que o APARELHO já tem
      // aparece na hora, sem rede e sem esperar o Firebase. É o que faz abrir
      // o hino 15 funcionar dentro da igreja.
      final jaEstavaEmMemoria = _indices.containsKey(hinarioId);
      if (!jaEstavaEmMemoria) {
        final local = await HinosLocais.lerIndice(hinarioId);
        if (local != null && !_indices.containsKey(hinarioId)) {
          _indices[hinarioId] = local;
          notifyListeners();
        }
      }

      // 2) Com cópia só do aparelho, o servidor atualiza em segundo plano: a
      // pessoa não espera a rede para ver o que já tem, e uma falha dela não
      // é erro. Quem PRECISA do dado novo (`forcar`, depois de importar)
      // espera.
      if (!jaEstavaEmMemoria && _indices.containsKey(hinarioId) && !forcar) {
        _carregadoEm[hinarioId] = _agora();
        _atualizando.add(hinarioId);
        final f = _lerIndiceDoBanco(hinarioId, forcar: false)
            .whenComplete(() => _atualizando.remove(hinarioId));
        _atualizacoes[hinarioId] = f;
        unawaited(f.whenComplete(() => _atualizacoes.remove(hinarioId)));
        return null;
      }
      return await _lerIndiceDoBanco(hinarioId, forcar: forcar);
    } finally {
      _carregando.remove(hinarioId);
    }
  }

  Future<String?> _lerIndiceDoBanco(String hinarioId,
      {required bool forcar}) async {
    final r = await _lerIndiceNoBanco(hinarioId);
    if (r.error != null) {
      // Com o índice já na memória, a falha da rede não é erro: o que a
      // pessoa vê continua valendo, e a próxima chamada tenta de novo.
      return (_indices.containsKey(hinarioId) && !forcar) ? null : r.error;
    }
    _indices[hinarioId] = r.indice!;
    _carregadoEm[hinarioId] = _agora();
    notifyListeners();
    await HinosLocais.guardarIndice(r.indice!);
    return null;
  }

  // ─── As letras no aparelho (a busca por trecho) ───────────────────────────

  final Map<String, Map<int, String>> _letras = {};
  final Set<String> _baixandoLetras = {};

  /// As letras que este aparelho tem do hinário — vazio se nunca as trouxe, ou
  /// se o líder importou de novo depois (a marca mudou e o que está guardado
  /// ficou velho: mostrar uma letra corrigida pela metade seria pior que
  /// oferecer baixar de novo).
  Map<int, String> letrasDe(String hinarioId) {
    final em = _letras[hinarioId];
    if (em != null) return em;
    final guardadas = LocalStorageService.letrasDoHinario(hinarioId);
    if (guardadas == null) return const {};
    if (_indices.containsKey(hinarioId) &&
        guardadas.marca != _indices[hinarioId]!.marca) {
      return const {};
    }
    return _letras[hinarioId] = guardadas.letras;
  }

  /// A busca já pode ler dentro das letras deste hinário?
  bool letrasProntas(String hinarioId) => letrasDe(hinarioId).isNotEmpty;

  bool baixandoLetras(String hinarioId) => _baixandoLetras.contains(hinarioId);

  /// Traz as letras de todos os hinos do hinário e guarda neste aparelho.
  /// Devolve null quando dá certo, ou o motivo.
  ///
  /// **Custa uma leitura por hino** (640 na Harpa), e é por isso que só roda
  /// quando a pessoa pede. Duas chamadas ao mesmo tempo não duplicam a conta.
  Future<String?> baixarLetras(Hinario hinario) async {
    if (_baixandoLetras.contains(hinario.id)) return null;
    _baixandoLetras.add(hinario.id);
    notifyListeners();
    try {
      // A marca vem do índice de AGORA; sem ele não há como saber, depois, se
      // o que ficou guardado ainda vale.
      final erroDoIndice = await carregarIndice(hinario.id);
      if (erroDoIndice != null) return erroDoIndice;
      final r = await _lerLetrasNoBanco(hinario.id);
      if (r.error != null) return r.error;
      final letras = r.letras!;
      _letras[hinario.id] = letras;
      // E cada hino fica disponível para abrir pelo número sem internet.
      final indice = indiceDe(hinario.id);
      unawaited(HinosLocais.guardarHinos([
        for (final e in letras.entries)
          if (indice.tituloDe(e.key) != null)
            HinoDaBiblioteca(
                hinario: hinario.id,
                numero: e.key,
                titulo: indice.tituloDe(e.key)!,
                letra: e.value),
      ], indice.marca));
      await LocalStorageService.salvarLetrasDoHinario(
          hinario.id, letras, indiceDe(hinario.id).marca);
      return null;
    } finally {
      _baixandoLetras.remove(hinario.id);
      notifyListeners();
    }
  }

  /// O hino da biblioteca, ou nulo se ela não o tem.
  ///
  /// Confere o índice ANTES de ler a letra: número que não está no índice
  /// custa zero leituras, e é o caso comum — o teclado digita números de
  /// hinos que ninguém importou.
  Future<({HinoDaBiblioteca? hino, String? error})> buscarHino(
    Hinario hinario,
    int numero,
  ) async {
    final chave = '${hinario.id}:$numero';
    final guardado = _hinos[chave];
    if (guardado != null) return (hino: guardado, error: null);

    final erro = await carregarIndice(hinario.id);
    if (erro != null) return (hino: null, error: erro);
    if (!indiceDe(hinario.id).tem(numero)) return (hino: null, error: null);

    // A cópia do aparelho vale enquanto a marca da importação for a mesma.
    final marca = indiceDe(hinario.id).marca;
    final local = await HinosLocais.lerHino(hinario.id, numero, marcaAtual: marca);
    if (local != null) {
      _hinos[chave] = local;
      return (hino: local, error: null);
    }
    // E as letras trazidas de uma vez para a busca por trecho.
    String? traz;
    try {
      traz = letrasDe(hinario.id)[numero];
    } catch (_) {
      // Armazenamento do aparelho indisponível: segue para o banco.
    }
    if (traz != null && traz.trim().isNotEmpty) {
      final h = HinoDaBiblioteca(
        hinario: hinario.id,
        numero: numero,
        titulo: indiceDe(hinario.id).tituloDe(numero) ?? '',
        letra: traz,
      );
      if (h.titulo.isNotEmpty) {
        _hinos[chave] = h;
        return (hino: h, error: null);
      }
    }

    // Sem cópia e sem internet: dizer logo, em vez de esperar o Firestore
    // concluir que está sem rede. A frase diz o que fazer.
    if (!Rede.online) {
      return (
        hino: null,
        error: 'Sem internet, e este hino ainda não foi baixado neste '
            'aparelho. Quando houver sinal, abra-o uma vez e ele passa a '
            'abrir sem internet.'
      );
    }
    final r = await _lerHinoNoBanco(hinario.id, numero);
    if (r.hino != null) {
      _hinos[chave] = r.hino!;
      unawaited(HinosLocais.guardarHino(r.hino!, marca));
    }
    return r;
  }

  /// Grava os hinos lidos e atualiza o que está em memória.
  ///
  /// Os hinos guardados do hinário são esquecidos e o índice é lido de novo:
  /// re-importar serve justamente para CORRIGIR texto, e mostrar a letra
  /// velha depois disso seria dizer que a correção não funcionou.
  Future<({int gravados, String? error})> importar({
    required Hinario hinario,
    required List<HinoLido> hinos,
    required String porQuemId,
    void Function(int feitos, int total)? aoAvancar,
  }) async {
    final r = await _gravarHinos(
      hinario: hinario,
      hinos: hinos,
      porQuemId: porQuemId,
      aoAvancar: aoAvancar,
    );
    // Mesmo com erro: parte pode ter entrado.
    if (r.gravados > 0) {
      _hinos.removeWhere((k, _) => k.startsWith('${hinario.id}:'));
      _letras.remove(hinario.id);
      try {
        await LocalStorageService.esquecerLetrasDoHinario(hinario.id);
      } catch (_) {
        // É só um cache de leitura: falhar em limpá-lo não pode transformar
        // numa importação com erro algo que já foi gravado no banco. A marca
        // do índice já faz o aparelho tratar as letras como velhas.
      }
      // O que o aparelho guardou DESTE hinário (índice e cada letra) é da
      // importação velha. A marca já impediria mostrá-lo, mas guardado ele só
      // ocuparia espaço — e a preparação recomeça deste hinário.
      await HinosLocais.esquecerHinario(hinario.id);
      await carregarIndice(hinario.id, forcar: true);
    }
    return r;
  }

  /// Põe o hino no repertório do ministério, criando a música.
  ///
  /// SÓ O LÍDER cria música, e é por isso que isto não é o que o teclado faz
  /// ao abrir um hino: ler não escreve. O hino vira música quando alguém
  /// decide USÁ-LO — pôr num culto, favoritar, colar uma cifra.
  ///
  /// Devolve a música criada, ou o motivo de não ter sido. O `id` é gerado
  /// aqui e a gravação é a mesma de qualquer música cadastrada.
  Future<({SongModel? musica, String? error})> porNoRepertorio(
    Hinario hinario,
    HinoDaBiblioteca hino, {
    required String? porQuemId,
  }) async {
    final musica = hino.comoMusica(
      hinario,
      id: CryptoUtils.generateId(),
      addedBy: porQuemId,
      criadaEm: _agora(),
    );
    final r = await _gravarMusica(musica);
    if (!r.success) return (musica: null, error: r.error);
    return (musica: musica, error: null);
  }
}
