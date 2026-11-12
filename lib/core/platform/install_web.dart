import 'dart:js_interop';

/// How the person could install the app, if at all.
enum InstallRoute {
  /// Nothing to do — already running as an app.
  naoSeAplica,

  /// Chrome and friends: the browser can show the invitation itself.
  conviteDoNavegador,

  /// Safari on the iPhone: no invitation exists, only instructions.
  instrucoesIphone,

  /// Some other browser: generic instructions.
  instrucoesGenericas,
}

// Everything below is defined in `web/index.html`. Keeping the browser
// checks there, in plain JavaScript, means this file needs no interop beyond
// four boolean calls — and the install event has to be captured there anyway,
// because the browser fires it before Flutter exists.

@JS('levitaEstaInstalado')
external bool _estaInstalado();

@JS('levitaEhSafariDeIphone')
external bool _ehSafariDeIphone();

@JS('levitaPodeConvidar')
external bool _podeConvidar();

@JS('levitaConvidarInstalacao')
external bool _convidar();

/// Running as an installed app rather than inside a browser tab.
bool get estaInstalado {
  try {
    return _estaInstalado();
  } catch (_) {
    // index.html did not load its hooks: treat as not installed. The worst
    // case is offering an installation that already happened.
    return false;
  }
}

InstallRoute get caminhoDeInstalacao {
  try {
    if (_estaInstalado()) return InstallRoute.naoSeAplica;
    if (_podeConvidar()) return InstallRoute.conviteDoNavegador;
    if (_ehSafariDeIphone()) return InstallRoute.instrucoesIphone;
    return InstallRoute.instrucoesGenericas;
  } catch (_) {
    return InstallRoute.naoSeAplica;
  }
}

/// Opens the browser's own install invitation. Returns whether it opened.
Future<bool> convidarParaInstalar() async {
  try {
    return _convidar();
  } catch (_) {
    return false;
  }
}
