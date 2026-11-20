import 'dart:js_interop';

// As funções moram em `web/tela_cheia.js`.
@JS('levitaAlternarTelaCheia')
external JSFunction? get _alternar;

@JS('levitaEmTelaCheia')
external JSFunction? get _em;

@JS('levitaSairDaTelaCheia')
external JSFunction? get _sair;

/// Entra ou sai da tela cheia. Devolve 'entrou', 'saiu', 'negado' ou
/// 'sem-suporte' — a tela usa isso para dizer "aperte F11" quando o navegador
/// não deixa.
Future<String> alternarTelaCheia() async {
  final f = _alternar;
  if (f == null) return 'sem-suporte';
  try {
    final r = await (f.callAsFunction(null) as JSPromise).toDart;
    final v = r.dartify();
    return v is String ? v : 'negado';
  } catch (_) {
    return 'negado';
  }
}

bool emTelaCheia() {
  try {
    return _em?.callAsFunction(null).dartify() == true;
  } catch (_) {
    return false;
  }
}

void sairDaTelaCheia() {
  try {
    _sair?.callAsFunction(null);
  } catch (_) {
    // Já saiu, ou a página não tem o script: nada a fazer.
  }
}
