import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'firebase_options.dart';
import 'core/constants/app_strings.dart';
import 'core/theme/app_theme.dart';
import 'data/services/local_storage_service.dart';
import 'presentation/providers/auth_provider.dart';
import 'presentation/providers/theme_provider.dart';
import 'presentation/providers/songs_provider.dart';
import 'presentation/providers/scale_provider.dart';
import 'presentation/providers/agenda_provider.dart';
import 'presentation/providers/chat_provider.dart';
import 'presentation/screens/auth/login_screen.dart';
import 'presentation/screens/main_screen.dart';
import 'presentation/widgets/common/glass.dart';

/// Whether [DefaultFirebaseOptions] carries a real project or the placeholder
/// values that ship with the template.
///
/// This check exists because the placeholders used to fail silently: the app
/// started, every request to the database failed, and the screens simply
/// stayed empty with no explanation anywhere.
bool get _firebaseConfigured {
  try {
    final o = DefaultFirebaseOptions.currentPlatform;
    return !o.apiKey.startsWith('YOUR_') &&
        o.apiKey.length > 20 &&
        !o.appId.contains('000000000000');
  } catch (_) {
    // Platform not configured at all (throws UnsupportedError).
    return false;
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize localization for pt_BR dates
  await initializeDateFormatting('pt_BR', null);

  // Initialize local storage
  await LocalStorageService.init();

  String? startupError;
  if (_firebaseConfigured) {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    } catch (e) {
      startupError = '$e';
    }
  }

  // Set preferred orientations
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  if (!_firebaseConfigured || startupError != null) {
    runApp(_SetupNeededApp(error: startupError));
    return;
  }

  runApp(const LevitaSyncApp());
}

/// Shown instead of the app when there is no Firebase project to talk to.
///
/// Says what is wrong and what to do about it, rather than leaving every
/// screen mysteriously empty.
class _SetupNeededApp extends StatelessWidget {
  final String? error;
  const _SetupNeededApp({this.error});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      // Sem título, o Flutter web apaga o título da página: a aba e o nome
      // sugerido ao salvar nos favoritos ficavam em branco.
      title: AppStrings.appName,
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF0E1116),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.cloud_off_rounded,
                      size: 48, color: Color(0xFFDDA64A)),
                  const SizedBox(height: 20),
                  const Text(
                    'Falta conectar o ${AppStrings.appName}\nao banco de dados',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    error == null
                        ? 'As chaves do Firebase ainda são as de exemplo, então '
                            'o app não tem onde guardar os dados. Nada do que '
                            'você fizer aqui seria salvo.'
                        : 'O Firebase está configurado, mas não respondeu:',
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 14,
                      color: Colors.white70,
                      height: 1.5,
                    ),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        error!,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          color: Colors.white60,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.12)),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Como resolver',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(height: 10),
                        Text(
                          'No computador, dentro da pasta do projeto:\n\n'
                          'dart pub global activate flutterfire_cli\n'
                          'flutterfire configure\n\n'
                          'Marque android, ios e web. O comando preenche as '
                          'chaves sozinho.',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            color: Colors.white70,
                            height: 1.55,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class LevitaSyncApp extends StatelessWidget {
  const LevitaSyncApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => SongsProvider()),
        ChangeNotifierProvider(create: (_) => ScaleProvider()),
        ChangeNotifierProvider(create: (_) => ChatProvider()),
        ChangeNotifierProvider(create: (_) => AgendaProvider()),
      ],
      child: Consumer<ThemeProvider>(
        builder: (ctx, themeProvider, _) {
          return MaterialApp(
            title: AppStrings.appName,
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: themeProvider.themeMode,
            // Frosted "Liquid Glass" backdrop behind every route.
            builder: (context, child) =>
                GlassBackdrop(child: child ?? const SizedBox.shrink()),
            home: const _AppEntry(),
          );
        },
      ),
    );
  }
}

class _AppEntry extends StatefulWidget {
  const _AppEntry();

  @override
  State<_AppEntry> createState() => _AppEntryState();
}

class _AppEntryState extends State<_AppEntry> {
  @override
  void initState() {
    super.initState();
    // Run after the first frame so the initial notifyListeners() inside
    // checkSession() doesn't fire during build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _checkAuth();
    });
  }

  Future<void> _checkAuth() async {
    final auth = context.read<AuthProvider>();
    await auth.checkSession();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    switch (auth.status) {
      case AuthStatus.initial:
      case AuthStatus.loading:
        return const _SplashScreen();
      case AuthStatus.authenticated:
        return const MainScreen();
      case AuthStatus.unauthenticated:
      case AuthStatus.error:
        return const LoginScreen();
    }
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF003C8F),
              Color(0xFF1565C0),
              Color(0xFF8E0000),
            ],
          ),
        ),
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.music_note_rounded,
                size: 72,
                color: Colors.white,
              ),
              SizedBox(height: 20),
              Text(
                AppStrings.appName,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 36,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: -0.5,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Ministério de Louvor Unificado',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 14,
                  color: Colors.white70,
                ),
              ),
              SizedBox(height: 48),
              SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
