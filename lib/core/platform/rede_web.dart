import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/foundation.dart';

@JS('levitaOnline')
external JSBoolean _lerOnline();

@JS('levitaOuvirRede')
external void _ouvir(JSFunction aviso);

/// `navigator.onLine` e os eventos `online`/`offline`, por `web/offline.js`.
class Rede {
  const Rede._();

  static final StreamController<bool> _mudancas =
      StreamController<bool>.broadcast();
  static bool _ligou = false;
  static bool? _forcado;

  static void _ligar() {
    if (_ligou) return;
    _ligou = true;
    try {
      _ouvir(((JSBoolean v) => _mudancas.add(v.toDart)).toJS);
    } catch (_) {
      // Página antiga, sem `offline.js`: fica o palpite de cada leitura.
    }
  }

  static bool get online {
    if (_forcado != null) return _forcado!;
    try {
      return _lerOnline().toDart;
    } catch (_) {
      return true;
    }
  }

  static Stream<bool> get mudancas {
    _ligar();
    return _mudancas.stream;
  }

  @visibleForTesting
  static void definir(bool online) {
    _forcado = online;
    _mudancas.add(online);
  }
}
