import 'package:flutter/foundation.dart';

/// Fora da web: uma tabela em memória. Espelha `armazem_web.dart`.
class Armazem {
  const Armazem._();

  static final Map<String, String> _tabela = {};

  /// Fora da web não há service worker: nada a esperar.
  static bool servicoDeCacheAtivo() => true;

  static Future<String?> ler(String chave) async => _tabela[chave];

  static Future<bool> gravar(String chave, String texto) async {
    _tabela[chave] = texto;
    return true;
  }

  static Future<bool> apagar(String chave) async {
    _tabela.remove(chave);
    return true;
  }

  static Future<List<String>> chaves(String prefixo) async =>
      _tabela.keys.where((k) => k.startsWith(prefixo)).toList();

  static Future<({int usado, int cota})?> estimativa() async => null;

  static Future<bool> pedirPersistencia() async => false;

  /// Esvazia tudo: só para os testes começarem do zero.
  @visibleForTesting
  static void esvaziar() => _tabela.clear();
}
