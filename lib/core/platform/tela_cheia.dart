/// Tela cheia do navegador, para projetar a letra.
///
/// Importação condicional como em `tela_acesa.dart`, `install.dart` e
/// `voz.dart`.
export 'tela_cheia_stub.dart'
    if (dart.library.js_interop) 'tela_cheia_web.dart';
