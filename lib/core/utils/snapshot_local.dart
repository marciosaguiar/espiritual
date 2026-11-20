import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../platform/armazem.dart';

/// A cópia que o aparelho guarda do que o banco mandou (músicas, cultos,
/// pessoas, mensagens), para o app ABRIR COM OS DADOS NA TELA sem esperar a
/// rede — nem o Firebase terminar de ligar.
///
/// Por que existe, se o Firestore já tem cache persistente: o cache do
/// Firestore só responde depois de `Firebase.initializeApp`, e na web esse
/// passo espera o Auth confirmar a sessão no Google (uma ida e volta de rede).
/// Medido na rodada anterior, é esse espera que separa 2 s de 5 s na segunda
/// abertura de um celular lento. A cópia daqui é lida direto do IndexedDB.
///
/// **Nunca é a verdade, só o que se mostra enquanto a verdade não chega.** O
/// banco responde logo depois e substitui tudo; por isso a cópia pode ser
/// velha sem causar dano, e por isso uma cópia ilegível é simplesmente
/// ignorada.
///
/// Timestamp não vira JSON — a mesma armadilha do `toJson`/`toFirestore` dos
/// modelos — então é escrito como `{"$ts": [segundos, nanos]}` e volta como
/// Timestamp. Nada aqui lança: guardar devolve falso, ler devolve nulo.
class SnapshotLocal {
  const SnapshotLocal._();

  static const String _prefixo = 'snap:';
  static const int _versao = 1;

  static String _chave(String nome) => '$_prefixo$nome';

  /// Guarda [docs] sob [nome]. Devolve se gravou.
  static Future<bool> guardar(
    String nome,
    List<Map<String, dynamic>> docs, {
    DateTime? agora,
  }) async {
    try {
      final texto = jsonEncode({
        'v': _versao,
        'em': (agora ?? DateTime.now()).toUtc().toIso8601String(),
        'docs': docs.map(_codificar).toList(),
      });
      return await Armazem.gravar(_chave(nome), texto);
    } catch (_) {
      // Valor que não sabemos escrever: sem cópia, o app só espera o banco.
      return false;
    }
  }

  /// Lê os documentos guardados sob [nome], ou nulo se não há (ou não dá para
  /// ler — cópia de outra versão, texto cortado).
  static Future<List<Map<String, dynamic>>?> ler(String nome) async {
    final r = await _lerTudo(nome);
    return r?.docs;
  }

  /// De quando é a cópia de [nome], ou nulo.
  static Future<DateTime?> quando(String nome) async =>
      (await _lerTudo(nome))?.em;

  static Future<({List<Map<String, dynamic>> docs, DateTime em})?> _lerTudo(
      String nome) async {
    try {
      final texto = await Armazem.ler(_chave(nome));
      if (texto == null) return null;
      final mapa = jsonDecode(texto);
      if (mapa is! Map || mapa['v'] != _versao) return null;
      final docs = mapa['docs'];
      final em = DateTime.tryParse('${mapa['em']}');
      if (docs is! List || em == null) return null;
      return (
        docs: [
          for (final d in docs) (_decodificar(d) as Map).cast<String, dynamic>(),
        ],
        em: em,
      );
    } catch (_) {
      return null;
    }
  }

  /// Esquece a cópia de [nome]. Usado quando a pessoa perde o acesso: o banco
  /// recusaria tudo, mas a cópia continuaria no celular.
  static Future<void> esquecer(String nome) => Armazem.apagar(_chave(nome));

  /// Esquece todas as cópias.
  static Future<void> esquecerTodas() async {
    for (final k in await Armazem.chaves(_prefixo)) {
      await Armazem.apagar(k);
    }
  }

  // ─── conversão ────────────────────────────────────────────────────────────

  static Object? _codificar(Object? v) {
    if (v == null || v is String || v is num || v is bool) return v;
    if (v is Timestamp) {
      return {
        r'$ts': [v.seconds, v.nanoseconds],
      };
    }
    if (v is DateTime) {
      return {r'$dt': v.toUtc().toIso8601String()};
    }
    if (v is Map) {
      return {for (final e in v.entries) '${e.key}': _codificar(e.value)};
    }
    if (v is Iterable) return v.map(_codificar).toList();
    // Tipo desconhecido: melhor não gravar nada do que gravar errado.
    throw ArgumentError('Não sei guardar ${v.runtimeType}');
  }

  static Object? _decodificar(Object? v) {
    if (v is Map) {
      if (v.length == 1 && v.containsKey(r'$ts')) {
        final par = v[r'$ts'] as List;
        return Timestamp((par[0] as num).toInt(), (par[1] as num).toInt());
      }
      if (v.length == 1 && v.containsKey(r'$dt')) {
        return DateTime.parse(v[r'$dt'] as String);
      }
      return {for (final e in v.entries) '${e.key}': _decodificar(e.value)};
    }
    if (v is List) return v.map(_decodificar).toList();
    return v;
  }
}
