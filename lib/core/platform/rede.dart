/// Se o aparelho diz estar com internet, e quando isso muda.
///
/// `navigator.onLine` é um palpite do navegador: "falso" é quase sempre
/// verdade (modo avião, sem sinal), mas "verdadeiro" só quer dizer que há uma
/// interface de rede — dentro de uma igreja com sinal ruim ele fica
/// verdadeiro com nada passando. Por isso o app NUNCA confia só nele: toda
/// ação tenta enviar com prazo, e o que não chega fica na fila.
library;

export 'rede_stub.dart' if (dart.library.js_interop) 'rede_web.dart';
