import 'dart:convert';

import '../../core/platform/armazem.dart';
import '../models/hino_da_biblioteca.dart';

/// Os hinos da biblioteca que ESTE aparelho já tem — o índice e a letra de
/// cada um —, no armazém local (IndexedDB), e não no Firestore.
///
/// Por que fora do cache do Firestore: o cache dele só responde depois de
/// `Firebase.initializeApp` (que a abertura não espera mais) e só guarda o que
/// uma consulta já pediu. Aqui, abrir "o hino 15" sem internet é uma leitura
/// de disco, e a preparação em segundo plano enche isto aos poucos.
///
/// Cada letra leva a MARCA da importação de que veio (`IndiceDoHinario.marca`).
/// Quando o líder importa de novo para corrigir um texto, a marca muda e a
/// cópia daqui deixa de valer — mostrar o texto velho depois de uma correção
/// seria dizer que a correção não funcionou.
///
/// Nada aqui lança: ler devolve nulo, gravar não faz nada. Cópia que falha é só
/// uma baixada a mais.
class HinosLocais {
  const HinosLocais._();

  static String _chaveDoIndice(String hinario) => 'hindice:$hinario';
  static String _chaveDoHino(String hinario, int n) => 'hino:$hinario:$n';

  // ─── índice ───────────────────────────────────────────────────────────────

  static Future<IndiceDoHinario?> lerIndice(String hinario) async {
    try {
      final texto = await Armazem.ler(_chaveDoIndice(hinario));
      if (texto == null) return null;
      final j = jsonDecode(texto) as Map;
      final titulos = <int, String>{};
      (j['t'] as Map).forEach((k, v) {
        final n = int.tryParse('$k');
        if (n != null && v is String) titulos[n] = v;
      });
      final quando = DateTime.tryParse('${j['a']}');
      return IndiceDoHinario(
          hinario: hinario, titulos: titulos, atualizadoEm: quando);
    } catch (_) {
      return null;
    }
  }

  static Future<void> guardarIndice(IndiceDoHinario indice) async {
    try {
      await Armazem.gravar(
        _chaveDoIndice(indice.hinario),
        jsonEncode({
          't': {for (final e in indice.titulos.entries) '${e.key}': e.value},
          'a': indice.atualizadoEm?.toUtc().toIso8601String(),
        }),
      );
    } catch (_) {}
  }

  // ─── letras ───────────────────────────────────────────────────────────────

  /// O hino guardado, se a marca ainda vale. [marcaAtual] nula = não conferir
  /// (quando não há índice para comparar).
  static Future<HinoDaBiblioteca?> lerHino(
    String hinario,
    int numero, {
    String? marcaAtual,
  }) async {
    try {
      final texto = await Armazem.ler(_chaveDoHino(hinario, numero));
      if (texto == null) return null;
      final j = jsonDecode(texto) as Map;
      if (marcaAtual != null && j['m'] != marcaAtual) return null;
      final titulo = j['t'];
      final letra = j['l'];
      if (titulo is! String || letra is! String || letra.trim().isEmpty) {
        return null;
      }
      return HinoDaBiblioteca(
          hinario: hinario, numero: numero, titulo: titulo, letra: letra);
    } catch (_) {
      return null;
    }
  }

  static Future<void> guardarHino(HinoDaBiblioteca h, String marca) async {
    try {
      await Armazem.gravar(
        _chaveDoHino(h.hinario, h.numero),
        jsonEncode({'m': marca, 't': h.titulo, 'l': h.letra}),
      );
    } catch (_) {}
  }

  static Future<void> guardarHinos(
      Iterable<HinoDaBiblioteca> hinos, String marca) async {
    for (final h in hinos) {
      await guardarHino(h, marca);
    }
  }

  /// Esquece tudo o que há deste hinário (a biblioteca foi reimportada, ou a
  /// pessoa perdeu o acesso).
  static Future<void> esquecerHinario(String hinario) async {
    try {
      await Armazem.apagar(_chaveDoIndice(hinario));
      for (final k in await Armazem.chaves('hino:$hinario:')) {
        await Armazem.apagar(k);
      }
    } catch (_) {}
  }

  /// Quantos hinos deste hinário estão guardados com a [marca] dada.
  /// Serve ao relatório "o que funciona sem internet".
  static Future<int> quantosGuardados(String hinario, String marca) async {
    try {
      var n = 0;
      for (final k in await Armazem.chaves('hino:$hinario:')) {
        final texto = await Armazem.ler(k);
        if (texto != null && jsonDecode(texto)['m'] == marca) n++;
      }
      return n;
    } catch (_) {
      return 0;
    }
  }
}
