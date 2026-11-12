/// Android and iOS builds: the app is already installed, so there is nothing
/// to suggest. Mirrors the API of `install_web.dart`.

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

/// Running as an installed app rather than inside a browser tab.
bool get estaInstalado => true;

InstallRoute get caminhoDeInstalacao => InstallRoute.naoSeAplica;

/// Opens the browser's own install invitation. Returns whether it opened.
Future<bool> convidarParaInstalar() async => false;
