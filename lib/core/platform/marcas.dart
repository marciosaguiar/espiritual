/// Marcas de tempo da abertura do app, para MEDIR onde o tempo vai.
///
/// Só existem em compilações de medição (`--dart-define=MEDIR=true`): na
/// compilação normal a condição é constante falsa, o compilador joga fora a
/// chamada, e nada disto entra no pacote nem roda no celular de ninguém. A
/// página de medição define `window.levitaMarcar`; sem ela, nada acontece.
library;

export 'marcas_stub.dart' if (dart.library.js_interop) 'marcas_web.dart';
