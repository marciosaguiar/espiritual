import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

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
import 'presentation/screens/auth/pending_screen.dart';
import 'presentation/screens/main_screen.dart';
import 'presentation/widgets/common/glass.dart';

/// Se as chaves do Firebase valem — e, quando a plataforma nem tem projeto
/// (iOS, macOS, Windows, Linux), o recado que explica isso.
///
/// Esta conferência existe porque a falta de configuração falhava em
/// silêncio: o app abria, toda chamada ao banco dava erro e as telas
/// simplesmente ficavam vazias, sem explicação em lugar nenhum.
({bool configurado, String? semProjeto}) _conferirFirebase() {
  try {
    final o = DefaultFirebaseOptions.currentPlatform;
    final valem = !o.apiKey.startsWith('YOUR_') &&
        o.apiKey.length > 20 &&
        !o.appId.contains('000000000000');
    return (configurado: valem, semProjeto: null);
  } on UnsupportedError catch (e) {
    // O recado vem do próprio `firebase_options.dart`, que sabe o nome do
    // projeto e o que precisa ser rodado. Mostrar a tela genérica de "chaves
    // de exemplo" aqui mandaria procurar chave onde não há nenhuma.
    return (configurado: false, semProjeto: e.message);
  } catch (e) {
    return (configurado: false, semProjeto: '$e');
  }
}

void main() async {
  // Desliga a integração do Flutter com o histórico do navegador.
  //
  // Por padrão o Flutter empilha uma entrada própria no histórico logo que
  // começa, para que o botão "voltar" do navegador feche telas do app. No
  // aplicativo instalado no iPhone isso tem um preço alto: existir uma
  // entrada anterior é justamente o que faz o WebKit aceitar o gesto de
  // arrastar da borda esquerda, e durante o gesto ele mostra o documento
  // anterior — a tela de abertura — deslizando por baixo. O `PopScope` segura
  // o Flutter, mas não o gesto, porque quem o desenha é o WebKit.
  //
  // Sem entrada nenhuma não há para onde voltar, e o gesto deixa de existir.
  // O que se perde: endereço por tela e o botão "voltar" do navegador — nada
  // disso é usado aqui, porque a navegação é por abas e por telas que abrem
  // por cima.
  //
  // Em Android e iOS nativos esta chamada não faz nada: o próprio pacote tem
  // uma versão vazia para fora da web.
  setUrlStrategy(null);

  WidgetsFlutterBinding.ensureInitialized();

  // Initialize localization for pt_BR dates
  await initializeDateFormatting('pt_BR', null);

  // Initialize local storage
  await LocalStorageService.init();

  final firebase = _conferirFirebase();
  String? startupError;
  if (firebase.configurado) {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );

      // CACHE NO APARELHO. Sem isto, cada abertura do app relia do servidor
      // tudo o que as quatro escutas de `main_screen` alcançam — e leitura é
      // a cota que aperta no plano grátis (50 mil por dia). Sem cache, TODA
      // reconexão de escuta é cobrada como consulta nova; com cache, só a
      // que ficou desligada mais de 30 minutos.
      //
      // Medido no emulador, com o banco do tamanho do ministério (40
      // músicas, 109 cultos na janela, 50 mensagens, 3 equipes): a segunda
      // abertura baixava 202 documentos do servidor e passou a baixar ZERO —
      // os 202 vêm do disco, e as quatro consultas recebem do servidor uma
      // resposta vazia, só confirmando que nada mudou.
      //
      // Duas coisas que esta linha também resolve: o app abre com o
      // repertório e a escala na tela mesmo sem internet, e a abertura não
      // espera a rede para desenhar.
      //
      // O limite conhecido é a SEGUNDA ABA. O cache é de aba única, e a
      // segunda aba não consegue a trava do IndexedDB. Medido: ela avisa no
      // console (`failed-precondition`) e cai sozinha para o cache em
      // memória, que é exatamente o que o app fazia antes — ninguém fica com
      // tela vazia. Como no iPhone o app instalado é uma janela só, esse
      // caso é o do computador com duas abas abertas.
      //
      // Sem `cacheSizeBytes`: o padrão do Firestore (40 MB) é cem vezes o
      // que este ministério ocupa, e um teto apertado só traria o risco de o
      // SDK ficar jogando fora o que acabou de guardar.
      FirebaseFirestore.instance.settings =
          const Settings(persistenceEnabled: true);
    } catch (e) {
      startupError = '$e';
    }
  }

  // Set preferred orientations
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  if (!firebase.configurado || startupError != null) {
    runApp(
        _SetupNeededApp(error: startupError, semProjeto: firebase.semProjeto));
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

  /// O recado de quando a plataforma não tem projeto nenhum no Firebase —
  /// compilar nativo para iOS ou macOS, por exemplo. Nulo no caso comum.
  final String? semProjeto;

  const _SetupNeededApp({this.error, this.semProjeto});

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
                  Text(
                    semProjeto == null
                        ? 'Falta conectar o ${AppStrings.appName}\n'
                            'ao banco de dados'
                        : 'O ${AppStrings.appName} não roda\n'
                            'nesta plataforma',
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    semProjeto ??
                        (error == null
                            ? 'As chaves do Firebase ainda são as de exemplo, '
                                'então o app não tem onde guardar os dados. '
                                'Nada do que você fizer aqui seria salvo.'
                            : 'O Firebase está configurado, mas não respondeu:'),
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
                  // O recado da plataforma sem projeto já traz o passo a
                  // passo dentro dele, com o nome do projeto certo. Repetir
                  // a receita genérica aqui embaixo daria duas instruções
                  // diferentes na mesma tela.
                  if (semProjeto == null)
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
        // Entrou, mas o líder ainda não liberou. As regras do banco não
        // devolvem nada para quem está pendente, então mandar essa pessoa
        // para o app seria mostrar cinco abas vazias sem explicação.
        if (!auth.aprovado) return const PendingScreen();
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
