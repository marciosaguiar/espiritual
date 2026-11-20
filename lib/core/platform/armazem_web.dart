import 'dart:convert';
import 'dart:js_interop';

import 'package:flutter/foundation.dart';

@JS('levitaArmazemLer')
external JSPromise<JSString?> _ler(JSString chave);

@JS('levitaArmazemGravar')
external JSPromise<JSBoolean> _gravar(JSString chave, JSString texto);

@JS('levitaArmazemApagar')
external JSPromise<JSBoolean> _apagar(JSString chave);

@JS('levitaArmazemChaves')
external JSPromise<JSString> _chaves(JSString prefixo);

@JS('levitaArmazemEstimativa')
external JSPromise<JSString> _estimativa();

@JS('levitaArmazemPersistir')
external JSPromise<JSBoolean> _persistir();

@JS('levitaServicoAtivo')
external JSBoolean _servicoAtivo();

/// IndexedDB, por `web/offline.js`.
class Armazem {
  const Armazem._();

  /// O service worker (o cache do app) já controla esta página?
  static bool servicoDeCacheAtivo() {
    try {
      return _servicoAtivo().toDart;
    } catch (_) {
      return false;
    }
  }

  static Future<String?> ler(String chave) async {
    try {
      return (await _ler(chave.toJS).toDart)?.toDart;
    } catch (_) {
      return null;
    }
  }

  static Future<bool> gravar(String chave, String texto) async {
    try {
      return (await _gravar(chave.toJS, texto.toJS).toDart).toDart;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> apagar(String chave) async {
    try {
      return (await _apagar(chave.toJS).toDart).toDart;
    } catch (_) {
      return false;
    }
  }

  static Future<List<String>> chaves(String prefixo) async {
    try {
      final json = (await _chaves(prefixo.toJS).toDart).toDart;
      return (jsonDecode(json) as List).cast<String>();
    } catch (_) {
      return const [];
    }
  }

  static Future<({int usado, int cota})?> estimativa() async {
    try {
      final texto = (await _estimativa().toDart).toDart;
      if (texto.isEmpty) return null;
      final m = jsonDecode(texto) as Map<String, dynamic>;
      return (usado: (m['usado'] as num).toInt(), cota: (m['cota'] as num).toInt());
    } catch (_) {
      return null;
    }
  }

  static Future<bool> pedirPersistencia() async {
    try {
      return (await _persistir().toDart).toDart;
    } catch (_) {
      return false;
    }
  }

  @visibleForTesting
  static void esvaziar() {}
}
