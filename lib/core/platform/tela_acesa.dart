/// Manter a tela acesa durante o Modo Culto ao vivo.
///
/// Importação condicional como em `install.dart`, `voz.dart` e `avisos.dart`.
export 'tela_acesa_stub.dart'
    if (dart.library.js_interop) 'tela_acesa_web.dart';
