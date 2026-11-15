/// Compartilhar um texto pelo menu do próprio sistema.
///
/// A implementação de verdade está em `compartilhar_web.dart` e é escolhida
/// pela exportação condicional abaixo, para nada específico da web ser
/// compilado nos aplicativos de Android e iOS.
export 'compartilhar_stub.dart'
    if (dart.library.js_interop) 'compartilhar_web.dart';
