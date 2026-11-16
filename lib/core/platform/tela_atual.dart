/// Conta à página em que tela o app está.
///
/// Serve a uma decisão só: a faixa "Nova versão disponível" pode se aplicar
/// sozinha quando a pessoa está no Início e parada, e nunca quando ela está
/// com a cifra aberta no meio do culto. Só a página sabe que há versão nova;
/// só o Flutter sabe em que tela a pessoa está.
export 'tela_atual_stub.dart' if (dart.library.js_interop) 'tela_atual_web.dart';
