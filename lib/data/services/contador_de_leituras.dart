import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/platform/armazem.dart';
import '../../core/utils/uso_de_leituras.dart';

/// Conta as leituras que o app provoca e as grava, agregadas por dia, em
/// `usoDiario/{dia}` — para saber o que o plano grátis está gastando, de
/// verdade, em produção.
///
/// **Barato de propósito.** Quem conta é cada aparelho, na memória; o que vai
/// para o banco é UMA escrita agregada (com `FieldValue.increment`) quando o app
/// vai para segundo plano e de quinze em quinze minutos com o app à vista, se
/// houver o que gravar. Com 30 pessoas são algumas centenas de escritas por dia
/// (de 20 mil grátis), e nenhuma leitura: quem lê esse documento é o modo de
/// economia, UMA vez a cada dez minutos por aparelho.
///
/// **É uma estimativa**, e ela guarda duas contas — com e sem a regra dos 30
/// minutos (ver `uso_de_leituras.dart`). A fatura de verdade está no painel de
/// uso do Firebase: a conta que ficar mais perto dele diz se a regra vale.
///
/// Nada aqui lança nem trava uma tela: contar é o que menos pode atrapalhar.
class ContadorDeLeituras {
  ContadorDeLeituras._({
    DateTime Function()? agora,
    Future<void> Function(String dia, UsoDoDia delta)? gravador,
  })  : agora = agora ?? DateTime.now,
        _gravador = gravador ?? _gravarNoFirestore;

  static ContadorDeLeituras instancia = ContadorDeLeituras._();

  /// Só os testes trocam.
  static ContadorDeLeituras paraTeste({
    required DateTime Function() agora,
    required Future<void> Function(String dia, UsoDoDia delta) gravador,
  }) =>
      ContadorDeLeituras._(agora: agora, gravador: gravador);

  static const String _chaveNoArmazem = 'uso:estado';

  final DateTime Function() agora;
  final Future<void> Function(String dia, UsoDoDia delta) _gravador;

  /// A última vez que cada consulta foi confirmada pelo servidor.
  final Map<String, DateTime> _ultimaSincronia = {};

  /// Consultas que a volta do app (depois de um tempo em segundo plano) manda
  /// recontar na próxima notificação do servidor.
  final Set<String> _recomecoPendente = {};

  UsoDoDia _pendente = const UsoDoDia();
  DateTime? _ultimaGravacao;
  Timer? _relogio;
  bool _gravando = false;

  /// O que ainda não foi gravado.
  UsoDoDia get pendente => _pendente;
  bool get temPendente =>
      _pendente.leituras > 0 || _pendente.semRegra > 0 || _pendente.aberturas > 0;

  /// Uma notificação do SERVIDOR (não do cache) de uma escuta ou consulta.
  ///
  /// [primeiraDaInstancia]: é a primeira vez que o servidor responde a ESTA
  /// escuta — é aí que se paga o resultado inteiro, quando passou do prazo.
  void notificacao({
    required String fonte,
    required String consulta,
    required bool primeiraDaInstancia,
    required int total,
    required int mudancas,
  }) {
    final agoraMesmo = agora();
    final recomeco = primeiraDaInstancia || _recomecoPendente.remove(consulta);
    final c = custoDaNotificacao(
      recomeco: recomeco,
      ultimaSincronia: _ultimaSincronia[consulta],
      agora: agoraMesmo,
      totalDeDocumentos: total,
      mudancas: mudancas,
    );
    _ultimaSincronia[consulta] = agoraMesmo;
    _somar(fonte, c.comRegra, c.semRegra);
  }

  /// Uma leitura pontual (`get`): custa o que veio, no mínimo uma.
  void umaVez(String fonte, int documentos) {
    final n = documentos < 1 ? 1 : documentos;
    _somar(fonte, n, n);
  }

  void _somar(String fonte, int comRegra, int semRegra) {
    if (comRegra <= 0 && semRegra <= 0) return;
    _pendente = _pendente.somando(UsoDoDia(
      leituras: comRegra,
      semRegra: semRegra,
      porFonte: {fonte: comRegra},
    ));
    _guardar();
  }

  /// O app abriu (ou voltou depois de mais de 30 minutos).
  void abertura() {
    _pendente = _pendente.somando(const UsoDoDia(aberturas: 1));
    _guardar();
  }

  /// O app foi para segundo plano: as escutas estavam em dia ATÉ AGORA, e é daqui
  /// que se conta o tempo desligada.
  void aoIrParaSegundoPlano() {
    final t = agora();
    for (final k in _ultimaSincronia.keys.toList()) {
      _ultimaSincronia[k] = t;
    }
    unawaited(descarregar());
  }

  /// O app voltou à tela: toda escuta que o SDK religar vai ter a regra dos 30
  /// minutos conferida na primeira resposta.
  void aoVoltar() {
    _recomecoPendente.addAll(_ultimaSincronia.keys);
  }

  /// Liga a gravação periódica (a cada 15 min, só se houver o que gravar).
  void iniciar() {
    _relogio ??= Timer.periodic(const Duration(minutes: 15), (_) {
      if (_pendente.leituras >= 20 || _pendente.aberturas > 0) {
        unawaited(descarregar());
      }
    });
    unawaited(_carregar());
  }

  void parar() {
    _relogio?.cancel();
    _relogio = null;
  }

  /// Grava o que está pendente, agregado. Em falha, o pendente fica para depois.
  Future<void> descarregar() async {
    if (_gravando || !temPendente) return;
    _gravando = true;
    final delta = _pendente;
    try {
      await _gravador(diaDaCota(agora()), delta);
      // Soma que chegou DURANTE a gravação não se perde: tira só o gravado.
      _pendente = UsoDoDia(
        leituras: _pendente.leituras - delta.leituras,
        semRegra: _pendente.semRegra - delta.semRegra,
        aberturas: _pendente.aberturas - delta.aberturas,
        porFonte: {
          for (final e in _pendente.porFonte.entries)
            e.key: e.value - (delta.porFonte[e.key] ?? 0),
        }..removeWhere((_, v) => v <= 0),
      );
      _ultimaGravacao = agora();
      _guardar();
    } catch (_) {
      // Sem rede ou sem permissão: tenta na próxima. Contar não pode incomodar.
    } finally {
      _gravando = false;
    }
  }

  DateTime? get ultimaGravacao => _ultimaGravacao;

  // ─── guardar entre aberturas ──────────────────────────────────────────────

  Future<void> _guardar() => Armazem.gravar(
        _chaveNoArmazem,
        jsonEncode({
          'sinc': {
            for (final e in _ultimaSincronia.entries)
              e.key: e.value.toUtc().toIso8601String(),
          },
          'pend': {
            'l': _pendente.leituras,
            's': _pendente.semRegra,
            'a': _pendente.aberturas,
            'f': _pendente.porFonte,
          },
        }),
      );

  Future<void> _carregar() async {
    try {
      final t = await Armazem.ler(_chaveNoArmazem);
      if (t == null) return;
      final j = Map<String, dynamic>.from(jsonDecode(t) as Map);
      for (final e in (j['sinc'] as Map? ?? {}).entries) {
        final d = DateTime.tryParse('${e.value}');
        if (d != null) _ultimaSincronia.putIfAbsent('${e.key}', () => d);
      }
      final p = j['pend'];
      if (p is Map) {
        _pendente = _pendente.somando(UsoDoDia(
          leituras: (p['l'] as num?)?.toInt() ?? 0,
          semRegra: (p['s'] as num?)?.toInt() ?? 0,
          aberturas: (p['a'] as num?)?.toInt() ?? 0,
          porFonte: {
            for (final e in ((p['f'] as Map?) ?? {}).entries)
              '${e.key}': (e.value as num?)?.toInt() ?? 0,
          },
        ));
      }
    } catch (_) {
      // Estado ilegível: recomeça do zero. É só uma estimativa.
    }
  }

  static Future<void> _gravarNoFirestore(String dia, UsoDoDia d) async {
    await FirebaseFirestore.instance.collection('usoDiario').doc(dia).set({
      'leituras': FieldValue.increment(d.leituras),
      'leiturasSemRegra': FieldValue.increment(d.semRegra),
      'aberturas': FieldValue.increment(d.aberturas),
      if (d.porFonte.isNotEmpty)
        'porFonte': {
          for (final e in d.porFonte.entries) e.key: FieldValue.increment(e.value),
        },
      'atualizadoEm': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// O uso do dia, lido do banco: UMA leitura.
  static Future<UsoDoDia?> lerDoDia(String dia) async {
    try {
      final doc =
          await FirebaseFirestore.instance.collection('usoDiario').doc(dia).get();
      return UsoDoDia.fromMap(doc.data());
    } catch (_) {
      return null;
    }
  }
}
