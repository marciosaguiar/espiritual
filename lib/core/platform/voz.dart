/// Gravar e tocar mensagens de voz.
///
/// A implementação de verdade está em `voz_web.dart` e usa o `MediaRecorder`
/// e o `<audio>` do navegador, por `web/audio.js`. A exportação condicional
/// mantém tudo isso fora dos aplicativos de Android e iOS, que precisariam
/// de um plugin com configuração nativa.
export 'voz_stub.dart' if (dart.library.js_interop) 'voz_web.dart';
