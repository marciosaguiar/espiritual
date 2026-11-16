import 'dart:js_interop';

// As funções moram em `web/tela_acesa.js`. Ver lá por que o pedido tem de
// ser repetido quando o app volta ao primeiro plano.
@JS('levitaManterTelaAcesa')
external JSFunction? get _manter;

@JS('levitaSoltarTela')
external JSFunction? get _soltar;

@JS('levitaTelaEstaAcesa')
external JSFunction? get _estaAcesa;

/// Pede para a tela não apagar. Devolve 'ok', 'negado', 'sem-suporte' ou
/// 'erro' — a tela usa isso para explicar o que fazer no iPhone antigo.
Future<String> manterTelaAcesa() async {
  final f = _manter;
  if (f == null) return 'sem-suporte';
  try {
    final r = await (f.callAsFunction(null) as JSPromise).toDart;
    final v = r.dartify();
    return v is String ? v : 'erro';
  } catch (_) {
    return 'erro';
  }
}

void soltarTela() {
  try {
    _soltar?.callAsFunction(null);
  } catch (_) {
    // Já soltou, ou a página não tem o script: nada a fazer.
  }
}

bool telaEstaAcesa() {
  try {
    return _estaAcesa?.callAsFunction(null).dartify() == true;
  } catch (_) {
    return false;
  }
}
