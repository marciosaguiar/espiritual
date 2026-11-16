/// Inscrever o aparelho para receber aviso de mensagem nova, e saber quando
/// alguém tocou na notificação.
///
/// Importação condicional como em `install.dart` e `voz.dart`: a web tem Web
/// Push, e o resto não tem nada.
export 'avisos_stub.dart' if (dart.library.js_interop) 'avisos_web.dart';
