import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/songs_provider.dart';
import '../providers/scale_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/agenda_provider.dart';
import '../providers/auth_provider.dart';
import '../../data/models/user_model.dart';
import '../../data/services/auth_service.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/platform/avisos.dart';
import '../../../core/platform/tela_atual.dart';
import '../../data/services/avisos_service.dart';
import '../widgets/common/glass.dart';
import 'home/home_screen.dart';
import 'songs/songs_screen.dart';
import 'scale/scale_screen.dart';
import 'scale/scale_detail_screen.dart';
import 'chat/chat_screen.dart';
import 'profile/profile_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  AuthProvider? _auth;

  /// Guards against generating twice in one session.
  bool _gerou = false;

  /// Vigia se alguém tocou numa notificação do chat.
  Timer? _olhoNoAviso;

  /// Índices das abas que a notificação precisa alcançar.
  static const int _abaChat = 3;
  static const int _abaEscala = 2;

  /// Índice da aba Perfil, usado por quem precisa levar a pessoa até lá.
  static const int _abaPerfil = 4;

  late final List<Widget> _screens = [
    HomeScreen(onAbrirPerfil: () => _goToTab(_abaPerfil)),
    const SongsScreen(),
    const ScaleScreen(),
    const ChatScreen(),
    const ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    // Defer to after the first frame so provider notifyListeners() (favorites
    // sync, preview seed data) don't fire during build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _initData();
    });
    informarTelaInicial(_currentIndex == 0);
    _vigiarAvisos();
  }

  /// Leva para o Chat quando a pessoa toca numa notificação.
  ///
  /// É uma pergunta de 1 em 1 segundo, e não um `stream`, porque o pedido
  /// pode chegar por dois caminhos diferentes — o service worker avisando a
  /// página, ou o `?abrir=chat` do app que acabou de abrir — e os dois
  /// acontecem fora do Flutter. Perguntar é mais simples que fazer o
  /// JavaScript empurrar, e 1 s de atraso ninguém percebe.
  void _vigiarAvisos() {
    _olhoNoAviso = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final pedido = pediuAbrir();
      if (pedido == null) return;
      if (pedido.onde == 'chat') {
        if (_currentIndex != _abaChat) _goToTab(_abaChat);
        return;
      }
      _abrirCulto(pedido.cultoId);
    });
  }

  /// Leva ao culto que o aviso mandou abrir.
  ///
  /// É o que faz "Confirme sua presença" terminar na tela onde se confirma —
  /// um aviso que pede ação e larga a pessoa na tela de Início seria pior que
  /// nenhum aviso.
  void _abrirCulto(String cultoId) {
    _goToTab(_abaEscala);
    if (cultoId.isEmpty) return;
    final cultos = context.read<ScaleProvider>().scales;
    final culto = cultos.where((c) => c.id == cultoId).firstOrNull;
    // Culto fora da janela de leitura (60 dias atrás / 90 à frente) não está
    // na memória: a aba da Escala já é o lugar certo para procurar.
    if (culto == null) return;
    Navigator.push(
      context,
      GlassPageRoute(builder: (_) => ScaleDetailScreen(scale: culto)),
    );
  }

  void _goToTab(int index) {
    if (index < 0 || index >= _screens.length) return;
    setState(() => _currentIndex = index);
    // A faixa "Nova versão disponível" só se aplica sozinha com a pessoa no
    // Início e parada; fora dali ela pergunta. Ver tela_atual.dart.
    informarTelaInicial(index == 0);
  }

  void _initData() {
    _auth = context.read<AuthProvider>();
    final songs = context.read<SongsProvider>();
    final scale = context.read<ScaleProvider>();
    final chat = context.read<ChatProvider>();

    // Set favorites in songs provider from user data
    if (_auth!.user != null) {
      songs.setFavorites(_auth!.user!.favoriteSongs);
    }
    // Keep favorites in sync reactively (outside of build) so toggling a
    // favorite anywhere updates the Songs filter without a rebuild loop.
    _auth!.addListener(_syncFavorites);

    // Start real-time listeners
    songs.listenToSongs();
    scale.listenToScales();
    chat.listenToMessages();
    chat.listenToTyping();

    final agenda = context.read<AgendaProvider>();
    agenda.listen();

    // Regrava a inscrição dos avisos se o navegador a trocou, ou se a pessoa
    // mudou de nome. Sem isto, o aparelho continuaria na lista do robô com
    // um endereço que o serviço de push já recusa.
    final eu = _auth!.user;
    if (eu != null) {
      AvisosService.conferirNaAbertura(userId: eu.id, userName: eu.name);
    }

    if (_auth!.isAdmin) _agendarGeracao(agenda, scale);
  }

  /// Creates the services of the next four weeks that are missing.
  ///
  /// Only a leader does this — the security rules refuse it for anybody else,
  /// so a levita opening the app generates nothing. That is also the weak
  /// point of this design: if no leader opens the app for weeks, the services
  /// stop being created. A scheduled Cloud Function is the real answer, and
  /// it needs the paid plan.
  ///
  /// Waits for the first batch of services and the schedule to arrive, since
  /// generating without knowing what already exists would duplicate work (the
  /// deterministic id still prevents duplicate documents, but it would be a
  /// pile of pointless transactions).
  void _agendarGeracao(AgendaProvider agenda, ScaleProvider scale) {
    Timer(const Duration(seconds: 3), () async {
      if (!mounted || _gerou) return;
      final slots = agenda.slots;
      if (slots.isEmpty) return;
      _gerou = true;
      await scale.gerarProximos(
        slots: slots,
        equipes: agenda.teamsById,
        createdBy: _auth?.user?.id,
      );
    });
  }

  void _syncFavorites() {
    if (!mounted) return;
    context
        .read<SongsProvider>()
        .setFavorites(_auth?.user?.favoriteSongs ?? const []);
  }

  @override
  void dispose() {
    _olhoNoAviso?.cancel();
    _auth?.removeListener(_syncFavorites);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // O gesto de arrastar da borda esquerda, no app instalado, é um "voltar"
    // do navegador. Na raiz não há tela para onde voltar, e o Flutter
    // responde saindo do documento — o app recarrega do zero e a abertura
    // aparece de novo. `canPop: false` faz o gesto parar aqui dentro.
    //
    // As telas abertas por cima (detalhe do culto, Membros, Equipes) não
    // passam por aqui: elas estão acima desta rota e fecham normalmente.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (jaFechou, _) {
        if (jaFechou) return;
        // Fora do Início, o voltar faz o que a pessoa espera: volta para o
        // Início, em vez de não fazer nada.
        if (_currentIndex != 0) _goToTab(0);
      },
      child: Scaffold(
        body: IndexedStack(
          index: _currentIndex,
          children: _screens,
        ),
        bottomNavigationBar: context.watch<AuthProvider>().isAdmin
            // O selo precisa aparecer sem o líder ir procurar: quem está
            // esperando não vê NADA do app, e um pedido esquecido por dias é
            // uma pessoa achando que o app não funciona.
            ? StreamBuilder<List<UserModel>>(
                stream: AuthService.watchPendentes(),
                builder: (_, snap) => _GlassNavBar(
                  currentIndex: _currentIndex,
                  onTap: _goToTab,
                  isDark: isDark,
                  pendentes: snap.data?.length ?? 0,
                ),
              )
            : _GlassNavBar(
                currentIndex: _currentIndex,
                onTap: _goToTab,
                isDark: isDark,
              ),
      ),
    );
  }
}

class _GlassNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final bool isDark;

  /// Quantos aguardam aprovação. Só o líder recebe diferente de zero.
  final int pendentes;

  const _GlassNavBar({
    required this.currentIndex,
    required this.onTap,
    required this.isDark,
    this.pendentes = 0,
  });

  static const _items = [
    (Icons.home_outlined, Icons.home_rounded, AppStrings.home),
    (Icons.music_note_outlined, Icons.music_note_rounded, AppStrings.songs),
    (
      Icons.calendar_month_outlined,
      Icons.calendar_month_rounded,
      AppStrings.scale
    ),
    (
      Icons.chat_bubble_outline_rounded,
      Icons.chat_bubble_rounded,
      AppStrings.chat
    ),
    (Icons.person_outline_rounded, Icons.person_rounded, AppStrings.profile),
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        child: GlassContainer(
          blur: 28,
          radius: 28,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: Row(
            children: [
              for (int i = 0; i < _items.length; i++)
                Expanded(
                  child: _GlassNavItem(
                    outlined: _items[i].$1,
                    filled: _items[i].$2,
                    label: _items[i].$3,
                    selected: i == currentIndex,
                    isDark: isDark,
                    badge: i == _items.length - 1 ? pendentes : 0,
                    onTap: () => onTap(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlassNavItem extends StatelessWidget {
  final IconData outlined;
  final IconData filled;
  final String label;
  final bool selected;
  final bool isDark;
  final int badge;
  final VoidCallback onTap;

  const _GlassNavItem({
    required this.outlined,
    required this.filled,
    required this.label,
    required this.selected,
    required this.isDark,
    required this.onTap,
    this.badge = 0,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? AppColors.blue
        : (isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.symmetric(vertical: 7),
        decoration: BoxDecoration(
          color:
              selected ? AppColors.blue.withOpacity(0.14) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(selected ? filled : outlined, size: 23, color: color),
                if (badge > 0)
                  Positioned(
                    top: -4,
                    right: -7,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      constraints: const BoxConstraints(minWidth: 17),
                      decoration: BoxDecoration(
                        color: AppColors.red,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Text(
                        badge > 9 ? '9+' : '$badge',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 10.5,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
