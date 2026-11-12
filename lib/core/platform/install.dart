/// Whether the app is running as an installed app, and how to get there.
///
/// Only the web build has anything to say here: on Android and iOS the app is
/// already installed. The real implementation is in `install_web.dart` and is
/// picked by the conditional export below, so nothing web-only is compiled
/// into the mobile builds.
export 'install_stub.dart' if (dart.library.js_interop) 'install_web.dart';
