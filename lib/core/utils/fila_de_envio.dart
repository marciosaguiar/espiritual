/// A fila do que a pessoa fez e ainda não chegou ao banco.
///
/// POR QUE EXISTE, SE O FIRESTORE JÁ TEM UMA FILA
///
/// O Firestore guarda `set` e `update` feitos sem internet e os envia sozinho.
/// Mas confirmar presença é uma TRANSAÇÃO (ler a lista, mudar a entrada de uma
/// pessoa, gravar a lista de volta, sem apagar a confirmação de quem confirmou
/// no mesmo instante) — e transação não existe sem internet. E editar uma
/// música precisa comparar com o que está no banco ANTES de gravar, para não
/// pisar na edição de outra pessoa. Nos dois casos a decisão tem de ser
/// tomada na hora do envio, e não na hora do toque.
///
/// O QUE A FILA GARANTE
///
/// - **Nada se perde:** vai para o armazém do aparelho a cada mudança, e
///   sobrevive a fechar o app.
/// - **Uma entrada por coisa:** confirmar, desmarcar e confirmar de novo
///   offline manda UM envio, com o estado final. Duas edições da mesma música
///   viram uma, com a base da primeira.
/// - **Em ordem, sem insistir à toa:** se a rede falhou, para; recomeça quando
///   ela volta ou quando o prazo de espera acaba (de 5 s até 5 min).
/// - **Falha definitiva não fica rodando:** um envio que o banco recusa de
///   vez (a pessoa foi tirada da escala, a música não existe mais) sai da fila
///   e vira um aviso para a pessoa — nunca um erro que só o console vê.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../data/models/aviso_de_sincronia.dart';
import '../platform/armazem.dart';
import 'fusao_de_edicao.dart';

enum TipoDeAcao { presenca, musica, arranjo }

class ItemDaFila {
  final String id;
  final TipoDeAcao tipo;

  /// Quem se funde com quem: dois itens com a mesma chave são a mesma coisa.
  final String chave;
  final Map<String, dynamic> dados;
  final DateTime criadoEm;
  final int tentativas;
  final DateTime? proximaTentativa;

  const ItemDaFila({
    required this.id,
    required this.tipo,
    required this.chave,
    required this.dados,
    required this.criadoEm,
    this.tentativas = 0,
    this.proximaTentativa,
  });

  /// Uma presença: o estado FINAL que a pessoa quer ([confirmado]).
  factory ItemDaFila.presenca({
    required String id,
    required String culto,
    required String userId,
    required bool confirmado,
    required DateTime agora,
    String? rotulo,
  }) =>
      ItemDaFila(
        id: id,
        tipo: TipoDeAcao.presenca,
        chave: 'presenca:$culto:$userId',
        dados: {
          'culto': culto,
          'userId': userId,
          'confirmado': confirmado,
          if (rotulo != null) 'rotulo': rotulo,
        },
        criadoEm: agora,
      );

  /// Uma edição de campos da música ou do arranjo.
  factory ItemDaFila.edicao({
    required String id,
    required TipoDeAcao tipo,
    required String songId,
    required Map<String, CampoEditado> campos,
    required DateTime agora,
    Map<String, dynamic> extra = const {},
  }) =>
      ItemDaFila(
        id: id,
        tipo: tipo,
        chave: '${tipo.name}:$songId',
        dados: {
          'songId': songId,
          'campos': {for (final e in campos.entries) e.key: e.value.toJson()},
          ...extra,
        },
        criadoEm: agora,
      );

  Map<String, CampoEditado> get campos => {
        for (final e in ((dados['campos'] as Map?) ?? const {}).entries)
          e.key as String:
              CampoEditado.fromJson(Map<String, dynamic>.from(e.value as Map)),
      };

  /// Este item DEPOIS de [anterior], que ainda não foi enviado. Nulo quando
  /// o resultado é "não há nada a enviar" (a edição voltou ao que era).
  ItemDaFila? fundirCom(ItemDaFila anterior) {
    if (tipo == TipoDeAcao.presenca) {
      // Vale o último desejo; a hora é a do primeiro, para a fila continuar
      // em ordem.
      return ItemDaFila(
          id: id,
          tipo: tipo,
          chave: chave,
          dados: dados,
          criadoEm: anterior.criadoEm);
    }
    final juntos = juntarEdicoes(anterior.campos, campos);
    if (juntos.isEmpty) return null;
    return ItemDaFila(
      id: id,
      tipo: tipo,
      chave: chave,
      dados: {
        ...anterior.dados,
        ...dados,
        'campos': {for (final e in juntos.entries) e.key: e.value.toJson()},
      },
      criadoEm: anterior.criadoEm,
    );
  }

  ItemDaFila comTentativa(DateTime? proxima) => ItemDaFila(
      id: id,
      tipo: tipo,
      chave: chave,
      dados: dados,
      criadoEm: criadoEm,
      tentativas: tentativas + 1,
      proximaTentativa: proxima);

  ItemDaFila semEspera() => ItemDaFila(
      id: id,
      tipo: tipo,
      chave: chave,
      dados: dados,
      criadoEm: criadoEm,
      tentativas: tentativas);

  Map<String, dynamic> toJson() => {
        'id': id,
        'tipo': tipo.name,
        'chave': chave,
        'dados': dados,
        'criadoEm': criadoEm.toUtc().toIso8601String(),
        'tentativas': tentativas,
        'proxima': proximaTentativa?.toUtc().toIso8601String(),
      };

  static ItemDaFila? tentarLer(Map<String, dynamic> j) {
    try {
      return ItemDaFila(
        id: j['id'] as String,
        tipo: TipoDeAcao.values.firstWhere((t) => t.name == j['tipo']),
        chave: j['chave'] as String,
        dados: Map<String, dynamic>.from(j['dados'] as Map),
        criadoEm: DateTime.parse(j['criadoEm'] as String).toLocal(),
        tentativas: (j['tentativas'] as num?)?.toInt() ?? 0,
        proximaTentativa: j['proxima'] == null
            ? null
            : DateTime.parse(j['proxima'] as String).toLocal(),
      );
    } catch (_) {
      // Item que não se lê (versão futura do app, armazém mexido) não pode
      // derrubar a fila inteira: fica de fora.
      return null;
    }
  }
}

enum Desfecho { enviado, tentarDepois, descartado }

class ResultadoDoEnvio {
  final Desfecho desfecho;

  /// Para quem está esperando na tela: o motivo, em português. Nulo quando
  /// deu certo.
  final String? erro;

  /// Recados para a pessoa (edição que perdeu, ação que não pôde ser enviada).
  final List<AvisoDeSincronia> avisos;

  const ResultadoDoEnvio._(this.desfecho, this.erro, this.avisos);

  const ResultadoDoEnvio.enviado({List<AvisoDeSincronia> avisos = const []})
      : this._(Desfecho.enviado, null, avisos);

  /// Falta de rede, prazo vencido: tenta de novo mais tarde.
  const ResultadoDoEnvio.depois([String? motivo])
      : this._(Desfecho.tentarDepois, motivo, const []);

  /// O banco recusou de vez: não adianta tentar de novo.
  const ResultadoDoEnvio.descartado(String erro,
      {List<AvisoDeSincronia> avisos = const []})
      : this._(Desfecho.descartado, erro, avisos);
}

typedef Executor = Future<ResultadoDoEnvio> Function(ItemDaFila item);

class FilaDeEnvio extends ChangeNotifier {
  static const chaveNoArmazem = 'fila:v1';

  final Map<TipoDeAcao, Executor> executores;
  final void Function(List<AvisoDeSincronia> avisos)? aoAvisar;
  final bool Function() estaOnline;
  final DateTime Function() _agora;
  final Duration prazoDeCadaEnvio;

  FilaDeEnvio({
    required this.executores,
    this.aoAvisar,
    bool Function()? estaOnline,
    DateTime Function()? agora,
    this.prazoDeCadaEnvio = const Duration(seconds: 15),
  })  : estaOnline = estaOnline ?? (() => true),
        _agora = agora ?? DateTime.now;

  final List<ItemDaFila> _itens = [];
  final Set<String> _emEnvio = {};
  final Map<String, Completer<ResultadoDoEnvio>> _esperas = {};
  bool _processando = false;
  bool _repetir = false;

  List<ItemDaFila> get itens => List.unmodifiable(_itens);
  int get pendentes => _itens.length;

  /// A mais antiga: é dela que se conta "enviando há X".
  DateTime? get pendenteDesde => _itens.isEmpty
      ? null
      : _itens.map((i) => i.criadoEm).reduce((a, b) => a.isBefore(b) ? a : b);

  bool temPendencia(String chave) => _itens.any((i) => i.chave == chave);

  ItemDaFila? daChave(String chave) {
    for (final i in _itens) {
      if (i.chave == chave) return i;
    }
    return null;
  }

  /// Lê a fila guardada no aparelho. Chamar uma vez, ao abrir o app.
  Future<void> carregar() async {
    final texto = await Armazem.ler(chaveNoArmazem);
    _itens.clear();
    if (texto != null && texto.isNotEmpty) {
      try {
        for (final j in (jsonDecode(texto) as List)) {
          final item = ItemDaFila.tentarLer(Map<String, dynamic>.from(j as Map));
          if (item != null) _itens.add(item.semEspera());
        }
      } catch (_) {
        // Armazém ilegível: começa vazia, em vez de não abrir o app.
      }
    }
    notifyListeners();
  }

  Future<void> _salvar() => Armazem.gravar(
      chaveNoArmazem, jsonEncode(_itens.map((i) => i.toJson()).toList()));

  /// Põe [novo] na fila e tenta enviar. Espera até [espera] pelo resultado
  /// DESTE item: se chegar, devolve (e a tela pode mostrar um erro na hora,
  /// como sempre mostrou); se não, devolve nulo e o item fica pendente.
  Future<ResultadoDoEnvio?> enfileirar(
    ItemDaFila novo, {
    Duration espera = const Duration(seconds: 6),
  }) async {
    ItemDaFila? efetivo = novo;
    final anterior = _itens
        .where((i) => i.chave == novo.chave && !_emEnvio.contains(i.id))
        .firstOrNull;
    if (anterior != null) {
      efetivo = novo.fundirCom(anterior);
      _itens.remove(anterior);
      _esperas.remove(anterior.id)?.complete(const ResultadoDoEnvio.depois());
    }
    if (efetivo != null) _itens.add(efetivo);
    await _salvar();
    notifyListeners();
    if (efetivo == null) return const ResultadoDoEnvio.enviado();
    if (!estaOnline()) return null;

    final espera0 = Completer<ResultadoDoEnvio>();
    _esperas[efetivo.id] = espera0;
    unawaited(processar());
    try {
      return await espera0.future.timeout(espera);
    } on TimeoutException {
      return null;
    }
  }

  /// A rede voltou (ou a pessoa abriu o app): esquece o tempo de espera e tenta.
  Future<void> acordar() {
    for (var i = 0; i < _itens.length; i++) {
      _itens[i] = _itens[i].semEspera();
    }
    return processar();
  }

  /// Envia o que está pendente, um por vez. Para no primeiro "sem rede": os
  /// outros iriam esperar o prazo, um a um, para falhar do mesmo jeito.
  Future<void> processar() async {
    if (_processando) {
      _repetir = true;
      return;
    }
    _processando = true;
    try {
      do {
        _repetir = false;
        for (final item in List<ItemDaFila>.of(_itens)) {
          if (!_itens.any((i) => i.id == item.id)) continue;
          final agora = _agora();
          if (item.proximaTentativa != null &&
              item.proximaTentativa!.isAfter(agora)) {
            continue;
          }
          final executor = executores[item.tipo];
          if (executor == null) continue;

          _emEnvio.add(item.id);
          ResultadoDoEnvio r;
          try {
            r = await executor(item).timeout(prazoDeCadaEnvio);
          } on TimeoutException {
            r = const ResultadoDoEnvio.depois('prazo');
          } catch (e) {
            r = ResultadoDoEnvio.depois('$e');
          } finally {
            _emEnvio.remove(item.id);
          }

          if (r.desfecho == Desfecho.tentarDepois) {
            final i = _itens.indexWhere((x) => x.id == item.id);
            if (i >= 0) {
              _itens[i] = _itens[i].comTentativa(
                  agora.add(_espera(_itens[i].tentativas + 1)));
            }
            _esperas.remove(item.id)?.complete(r);
            await _salvar();
            notifyListeners();
            break; // sem rede: os outros esperam junto
          }

          _itens.removeWhere((x) => x.id == item.id);
          if (r.avisos.isNotEmpty) aoAvisar?.call(r.avisos);
          _esperas.remove(item.id)?.complete(r);
          await _salvar();
          notifyListeners();
        }
      } while (_repetir);
    } finally {
      _processando = false;
    }
  }

  /// 5 s, 10 s, 20 s… até 5 min.
  static Duration _espera(int tentativas) {
    final s = 5 * (1 << (tentativas - 1).clamp(0, 6));
    return Duration(seconds: s > 300 ? 300 : s);
  }
}
