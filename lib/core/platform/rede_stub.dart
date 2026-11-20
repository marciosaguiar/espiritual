import 'dart:async';

import 'package:flutter/foundation.dart';

/// Fora da web: sempre "com internet" (quem decide é o prazo de cada envio).
/// Espelha `rede_web.dart`.
class Rede {
  const Rede._();

  static bool _online = true;
  static final StreamController<bool> _mudancas =
      StreamController<bool>.broadcast();

  static bool get online => _online;
  static Stream<bool> get mudancas => _mudancas.stream;

  /// Só para os testes simularem o cabo saindo e voltando.
  @visibleForTesting
  static void definir(bool online) {
    if (_online == online) return;
    _online = online;
    _mudancas.add(online);
  }
}
