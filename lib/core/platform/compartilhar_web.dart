import 'dart:js_interop';

/// O menu de compartilhamento do próprio aparelho, pela Web Share API.
///
/// É o que faz "compartilhar versículo" abrir o WhatsApp no iPhone, que é
/// para onde esse texto vai na prática. Só existe em contexto seguro (o app
/// é servido por HTTPS) e, no desktop, nem sempre existe — por isso a tela
/// sempre tem o copiar como caminho garantido.
@JS('navigator.share')
external JSFunction? get _share;

@JS()
@staticInterop
@anonymous
class _DadosDoShare {
  external factory _DadosDoShare({String? title, String? text, String? url});
}

bool get podeCompartilhar => _share != null;

Future<bool> compartilharTexto(String texto) async {
  final share = _share;
  if (share == null) return false;
  try {
    final resultado = share.callAsFunction(
      null,
      _DadosDoShare(text: texto) as JSAny,
    );
    if (resultado.isA<JSPromise>()) {
      await (resultado as JSPromise).toDart;
    }
    return true;
  } catch (_) {
    // A pessoa fechou o menu, ou o navegador recusou. Não é erro para
    // mostrar: a tela cai no copiar.
    return false;
  }
}
