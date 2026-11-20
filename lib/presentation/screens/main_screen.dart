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
import '../../../core/utils/compartilhado.dart';
import '../../data/services/avisos_service.dart';
import '../../data/services/local_storage_service.dart';
import '../widgets/common/glass.dart';
import 'home/home_screen.dart';
import 'songs/songs_screen.dart';
import 'songs/add_song_screen.dart';
import 'scale/scale_screen.dart';
import 'scale/scale_detail_screen.dart';
import 'chat/chat_screen.dart';
import 'profile/profile_screen.dart';
import 'profile/members_screen.dart';

class MainScreen extends StatefulWidget {
  /// A aba que abre primeiro. Só o roteiro de captura de telas usa algo
  /// diferente de 0.
  final int abaInicial;

  /// Liga as escutas do banco. Desligado, a tela mostra o que os providers já
  /// têm na memória — é o que permite fotografar o app sem Firebase.
  final bool escutas;

  const MainScreen({super.key, this.abaInicial = 0, this.escutas = true});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  late int _currentIndex = widget.abaInicial;
  AuthProvider? _auth;

  /// Guards against generating twice in one session.
  bool _gerou = false;

  /// Vigia se alguém tocou numa notificação do chat.
  Timer? _olhoNoAviso;

  /// Índices das abas que a notificação precisa alcançar.
  static const int _abaChat = 3;
  static const int _abaEscala = 2;

  /// Índice da aba Músicas, para os contadores do Perfil abrirem as listas
  /// que já existem lá.
  static const int _abaMusicas = 1;

  /// Índice da aba Perfil, usado por quem precisa levar a pessoa até lá.
  static const int _abaPerfil = 4;

  late final List<Widget> _screens = [
    HomeScreen(
      onAbrirPerfil: () => _goToTab(_abaPerfil),
      onAbrirChat: () => _goToTab(_abaChat),
      onAbrirEscala: () => _goToTab(_abaEscala),
      onAbrirMembros: _abrirMembros,
    ),
    const SongsScreen(),
    const ScaleScreen(),
    ChatScreen(escutas: widget.escutas),
    ProfileScreen(onAbrirMusicas: _abrirMusicasCom),
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
      // Compartilhado de outro app (só Android, com o app instalado). Vem
      // antes do pedido de notificação porque é ação direta da pessoa: ela
      // acabou de tocar em "compartilhar" e está esperando a tela abrir.
      _conferirCompartilhado();

      final pedido = pediuAbrir();
      if (pedido == null) return;
      if (pedido.onde == 'chat') {
        if (_currentIndex != _abaChat) _goToTab(_abaChat);
        return;
      }
      if (pedido.onde == 'membros') {
        _abrirMembros();
        return;
      }
      _abrirCulto(pedido.cultoId);
    });
  }

  /// Leva à tela Membros, onde o pedido de entrada é aprovado ou recusado.
  ///
  /// Só para o líder: um levita que recebesse este aviso por engano abriria
  /// uma tela onde não há botão nenhum para ele. O Worker já manda só para
  /// líderes; esta é a segunda tranca, para o caso de alguém ser rebaixado
  /// entre o envio e o toque.
  /// Abre o cadastro de música com o que outro app compartilhou.
  ///
  /// Só para líder: só o líder cria música no banco, e abrir um cadastro que
  /// a regra vai recusar no fim é a pior forma de receber alguém que acabou
  /// de tocar em "compartilhar".
  void _conferirCompartilhado() {
    final veio = compartilhado();
    if (veio == null) return;
    if (!context.read<AuthProvider>().isAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Só o líder cadastra música. Mande a cifra para ele '
            'pelo chat.'),
        duration: Duration(seconds: 4),
      ));
      return;
    }

    final uso = comoUsarCompartilhado(
      titulo: veio.titulo,
      texto: veio.texto,
      endereco: veio.endereco,
    );
    if (!uso.temAlgo) return;

    Navigator.push(
      context,
      GlassPageRoute(
        builder: (_) => AddSongScreen(
          cifraInicial: uso.cifra,
          tituloInicial: uso.titulo,
          linkInicial: uso.link,
        ),
      ),
    );
  }

  /// Abre a aba Músicas já com o filtro pedido.
  ///
  /// É o que os contadores do Perfil usam: "Favoritas" e "No celular" são
  /// filtros que já existem na aba Músicas, e o Perfil tinha cópias das duas
  /// listas no fim da tela — onde ninguém rolava.
  void _abrirMusicasCom(SongsFilter filtro) {
    context.read<SongsProvider>().setFilter(filtro);
    _goToTab(_abaMusicas);
  }

  void _abrirMembros() {
    final auth = context.read<AuthProvider>();
    _goToTab(_abaPerfil);
    if (!auth.isAdmin) return;
    Navigator.push(
      context,
      GlassPageRoute(builder: (_) => const MembersScreen()),
    );
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
    // Abrir a aba do chat é "eu vi": é o que zera a contagem de não lidas no
    // Início. Fica aqui, e não na tela do chat, porque com `IndexedStack` a
    // tela do chat é construída uma vez e nunca mais — o `initState` dela
    // rodaria no primeiro dia e nunca de novo.
    if (index == _abaChat) LocalStorageService.marcarChatVisto();
    setState(() => _currentIndex = index);
    // A faixa "Nova versão disponível" só se aplica sozinha com a pessoa no
    // Início e parada; fora dali ela pergunta. Ver tela_atual.dart.
    informarTelaInicial(index == 0);
  }

  void _initData() {
    _auth = context.read<AuthProvider>();
    if (!widget.escutas) return;
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
    // Uma escuta só da lista de pessoas, para o app todo: o chat tinha a
    // dele, e a Escala e o Início passaram a precisar da mesma coisa para
    // dizer quem ainda não confirmou.
    _auth!.ouvirPessoas();

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

  /// Cria os cultos das próximas quatro semanas que estão faltando.
  ///
  /// Só o líder faz isso — as regras recusam para qualquer outro, então um
  /// levita abrindo o app não gera nada. Isto ERA a fragilidade do desenho:
  /// sem nenhum líder abrir o app por semanas, os cultos paravam de ser
  /// criados. Hoje o Worker faz o mesmo uma vez por dia (ver "O Worker gera
  /// os cultos" no CLAUDE.md), e as duas são seguras de repetir: o id vem da
  /// data e hora, e quem já existe é recusado. Esta continua valendo porque
  /// dá resposta na hora a quem acabou de configurar a agenda.
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
