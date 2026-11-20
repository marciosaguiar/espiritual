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
import '../../../core/platform/marcas.dart';
import '../../../core/utils/fonte_mono.dart';
import '../../../core/platform/tela_atual.dart';
import '../../../core/utils/compartilhado.dart';
import '../../data/services/app_firebase.dart';
import '../../data/services/avisos_service.dart';
import '../../data/services/local_storage_service.dart';
import '../../data/services/preparo_offline.dart';
import '../../data/services/biblia_service.dart' show traducoesDisponiveis;
import '../widgets/common/faixa_de_rede.dart';
import '../widgets/common/glass.dart';
import '../widgets/common/responsivo.dart';
import 'home/home_screen.dart';
import 'songs/songs_screen.dart';
import 'songs/add_song_screen.dart';
import 'scale/scale_screen.dart';
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

  /// A fila de pedidos de entrada, criada UMA vez. Criada a cada `build`, o
  /// StreamBuilder reassinava a consulta toda vez que se trocava de aba — e
  /// cada reassinatura é leitura cobrada.
  Stream<List<UserModel>>? _pendentes;

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

  /// Onde o toque num aviso pede para abrir um culto na aba da Escala.
  final _pedidoDeCulto = ValueNotifier<PedidoDeCulto?>(null);

  /// As abas que já foram abertas.
  ///
  /// O `IndexedStack` constrói TODOS os filhos de uma vez, e as cinco abas
  /// (calendário, lista de músicas, chat, perfil…) eram montadas no primeiro
  /// quadro — MEDIDO: ~850 ms de processador a mais antes de o Início poder
  /// pedir os dados, e ainda por cima as abas escondidas medem o próprio texto
  /// e fazem o navegador baixar as fontes de emoji e de símbolos de que só
  /// elas precisam. Agora só a aba de abertura nasce pronta; cada outra é
  /// construída na primeira visita e DEPOIS fica (guarda busca, rolagem e o
  /// que foi digitado, como antes).
  late final Set<int> _construidas = {widget.abaInicial};

  late final List<Widget> _screens = [
    // Cada aba tem a largura em que se lê bem. Sem isto, num monitor de 1920
    // px o chat vira uma linha de 2.400 px e o Início, um vazio com um cartão
    // esticado. No celular nada disto tem efeito: a coluna é mais larga que a
    // tela.
    ColunaCentral(
      largura: Porte.colunaLarga,
      child: HomeScreen(
        onAbrirPerfil: () => _goToTab(_abaPerfil),
        onAbrirChat: () => _goToTab(_abaChat),
        onAbrirEscala: () => _goToTab(_abaEscala),
        onAbrirMembros: _abrirMembros,
      ),
    ),
    // Músicas e Escala têm lista E detalhe lado a lado, e usam a largura toda.
    const SongsScreen(),
    ScaleScreen(pedido: _pedidoDeCulto),
    ColunaCentral(child: ChatScreen(escutas: widget.escutas)),
    ColunaCentral(child: ProfileScreen(onAbrirMusicas: _abrirMusicasCom)),
  ];

  /// Só compilações de medição (`--dart-define=MEDIR=true`) ligam isto; na
  /// normal o compilador joga fora esta função e as chamadas a ela.
  static const bool _medindo = bool.fromEnvironment('MEDIR');
  bool _marcouInicio = false;

  /// O banco já ligou? O selo de pedidos pendentes (do líder) é uma escuta, e
  /// só pode nascer depois disso.
  bool _bancoPronto = AppFirebase.ligado;
  Timer? _timerDaAgenda;
  VoidCallback? _tiraMarcaDeInicio;

  /// Marca "inicio-com-dados": o primeiro quadro em que o Início tem cultos E
  /// músicas. É o "posso usar" que a pessoa sente — não o primeiro quadro do
  /// Flutter, que pode ser só a tela de abertura.
  void _vigiarInicioParaMedir() {
    if (!_medindo) return;
    final songs = context.read<SongsProvider>();
    final scale = context.read<ScaleProvider>();
    void conferir() {
      if (_marcouInicio || songs.songs.isEmpty || scale.scales.isEmpty) return;
      _marcouInicio = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => marcar('inicio-com-dados'));
    }

    songs.addListener(conferir);
    scale.addListener(conferir);
    _tiraMarcaDeInicio = () {
      songs.removeListener(conferir);
      scale.removeListener(conferir);
    };
    conferir();
  }

  @override
  void initState() {
    super.initState();
    _vigiarInicioParaMedir();
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
    // Quem abre é a aba da Escala, e não esta tela: em tela larga o culto
    // tem de aparecer AO LADO do calendário, e só quem está dentro do painel
    // sabe chegar nele.
    //
    // Depois do quadro: a aba da Escala pode estar sendo construída agora (é
    // construída na primeira visita), e quem escuta o pedido só existe depois
    // disso. Escrever já perderia o pedido sem aviso.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _pedidoDeCulto.value = PedidoDeCulto(culto);
    });
  }

  void _goToTab(int index) {
    if (index < 0 || index >= _screens.length) return;
    // Abrir a aba do chat é "eu vi": é o que zera a contagem de não lidas no
    // Início. Fica aqui, e não na tela do chat, porque com `IndexedStack` a
    // tela do chat é construída uma vez e nunca mais — o `initState` dela
    // rodaria no primeiro dia e nunca de novo.
    if (index == _abaChat) LocalStorageService.marcarChatVisto();
    setState(() {
      _currentIndex = index;
      _construidas.add(index);
    });
    // A faixa "Nova versão disponível" só se aplica sozinha com a pessoa no
    // Início e parada; fora dali ela pergunta. Ver tela_atual.dart.
    informarTelaInicial(index == 0);
  }

  Future<void> _initData() async {
    marcar('escutas-iniciando');
    _auth = context.read<AuthProvider>();
    if (!widget.escutas) return;
    // As escutas precisam do banco, que liga em paralelo com o desenho do app
    // (ver `AppFirebase`). Até lá a tela já mostra a cópia guardada.
    final erroAoLigar = await AppFirebase.pronto;
    if (!mounted || erroAoLigar != null) return;
    setState(() => _bancoPronto = true);
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

    // Escutas em tempo real, NA ORDEM do que o Início precisa: o cartão do
    // culto vem dos cultos, "minhas próximas músicas" das músicas. O banco
    // atende as consultas uma a uma, então a ordem é a de chegada.
    scale.listenToScales();
    songs.listenToSongs();
    // Uma escuta só da lista de pessoas, para o app todo: o chat tinha a
    // dele, e a Escala e o Início passaram a precisar da mesma coisa para
    // dizer quem ainda não confirmou.
    _auth!.ouvirPessoas();
    chat.listenToMessages();
    // "Fulano está digitando" só serve DENTRO do chat: quem a começa é a
    // própria tela do chat, na primeira visita. Era uma escuta a mais em toda
    // abertura, para um recado que quase nunca é visto.

    // A agenda fixa (horários e equipes) só serve a quem gera cultos e a quem
    // abre o Perfil: espera o Início ter os dados dele. O líder só a usa
    // 3 s depois (`_agendarGeracao`), então nada atrasa.
    final agenda = context.read<AgendaProvider>();
    _timerDaAgenda = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) agenda.listen();
    });
    // Deixa o app pronto para o culto sem sinal: cifras, letras dos hinos e a
    // Bíblia, AOS POUCOS e dentro do orçamento diário de leituras. Roda duas
    // vezes — logo depois da abertura, e de novo quando o repertório já
    // chegou — e é seguro repetir: o que já foi feito não é pedido de novo.
    Timer(const Duration(seconds: 8), _prepararOffline);
    Timer(const Duration(seconds: 60), _prepararOffline);

    // A fonte da cifra (fora do pacote de abertura) é buscada logo depois que
    // o Início já tem o que mostrar, para estar pronta quando a pessoa abrir
    // uma música. Não compete com a abertura, e dá tempo de sobra antes do
    // primeiro toque numa cifra.
    Timer(const Duration(seconds: 4), FonteMono.garantir);

    // Regrava a inscrição dos avisos se o navegador a trocou, ou se a pessoa
    // mudou de nome. Sem isto, o aparelho continuaria na lista do robô com
    // um endereço que o serviço de push já recusa.
    final eu = _auth!.user;
    if (eu != null) {
      AvisosService.conferirNaAbertura(userId: eu.id, userName: eu.name);
    }

    if (_auth!.isAdmin) _agendarGeracao(agenda, scale);
  }

  bool _preparando = false;

  Future<void> _prepararOffline() async {
    if (!mounted || _preparando) return;
    _preparando = true;
    try {
      final songs = context.read<SongsProvider>();
      final eu = _auth?.user;
      await PreparoOffline().executar(
        idsDeMusicas: [for (final m in songs.repertorio) m.id],
        hinarios: LocalStorageService.ordemDosHinariosDe(eu?.id),
        traducaoDaBiblia: LocalStorageService.getUltimaLeitura()?.traducao ??
            traducoesDisponiveis.first.id,
      );
    } catch (_) {
      // Preparação é bônus: falhar nela não pode aparecer para ninguém.
    } finally {
      _preparando = false;
    }
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
    _timerDaAgenda?.cancel();
    _tiraMarcaDeInicio?.call();
    _pedidoDeCulto.dispose();
    _auth?.removeListener(_syncFavorites);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final lateral = Porte.lateral(context);
    final larga = MediaQuery.sizeOf(context).width >= Porte.navegacaoLarga;
    final admin = context.watch<AuthProvider>().isAdmin;

    // O selo precisa aparecer sem o líder ir procurar: quem está esperando não
    // vê NADA do app, e um pedido esquecido por dias é uma pessoa achando que
    // o app não funciona.
    Widget montar(int pendentes) {
      // `AbaVisivel` conta a cada aba se é a da vez: as outras continuam
      // montadas (guardam busca e rolagem), mas não podem reagir ao Esc.
      final pilha = FaixaDeRede(
        child: IndexedStack(
          index: _currentIndex,
          children: [
            for (var i = 0; i < _screens.length; i++)
              AbaVisivel(
                visivel: i == _currentIndex,
                child: _construidas.contains(i)
                    ? _screens[i]
                    : const SizedBox.shrink(),
              ),
          ],
        ),
      );
      return Scaffold(
        // Tela larga: a navegação vai para o lado, onde há espaço, e a barra
        // de baixo some. No celular, tudo como sempre foi.
        body: lateral
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _NavLateral(
                    currentIndex: _currentIndex,
                    onTap: _goToTab,
                    isDark: isDark,
                    larga: larga,
                    pendentes: pendentes,
                  ),
                  Expanded(child: pilha),
                ],
              )
            : pilha,
        bottomNavigationBar: lateral
            ? null
            : _GlassNavBar(
                currentIndex: _currentIndex,
                onTap: _goToTab,
                isDark: isDark,
                pendentes: pendentes,
              ),
      );
    }

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
      child: admin && _bancoPronto
          ? StreamBuilder<List<UserModel>>(
              stream: _pendentes ??= AuthService.watchPendentes(),
              builder: (_, snap) => montar(snap.data?.length ?? 0),
            )
          : montar(0),
    );
  }
}

/// A navegação das telas largas: uma coluna de vidro à esquerda.
///
/// Estreita (só ícone e nome embaixo, como a barra de baixo) em tablet, e larga
/// (nome ao lado do ícone) a partir de [Porte.navegacaoLarga]. Tem o que o
/// mouse espera: a mãozinha e um realce ao passar por cima.
class _NavLateral extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final bool isDark;
  final bool larga;
  final int pendentes;

  const _NavLateral({
    required this.currentIndex,
    required this.onTap,
    required this.isDark,
    required this.larga,
    required this.pendentes,
  });

  @override
  Widget build(BuildContext context) {
    final cor =
        isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    return SafeArea(
      right: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 0, 12),
        child: GlassContainer(
          blur: 28,
          radius: 28,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
          child: SizedBox(
            width: larga ? 196 : 68,
            child: Column(
              children: [
                if (larga)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 4, 10, 0),
                    child: Row(
                      children: [
                        const Icon(Icons.music_note_rounded,
                            size: 24, color: AppColors.blue),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            AppStrings.appName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: cor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  const Icon(Icons.music_note_rounded,
                      size: 26, color: AppColors.blue),
                const SizedBox(height: 18),
                for (var i = 0; i < _abas.length; i++)
                  _ItemLateral(
                    outlined: _abas[i].$1,
                    filled: _abas[i].$2,
                    label: _abas[i].$3,
                    selected: i == currentIndex,
                    isDark: isDark,
                    larga: larga,
                    badge: i == _abas.length - 1 ? pendentes : 0,
                    onTap: () => onTap(i),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ItemLateral extends StatelessWidget {
  final IconData outlined;
  final IconData filled;
  final String label;
  final bool selected;
  final bool isDark;
  final bool larga;
  final int badge;
  final VoidCallback onTap;

  const _ItemLateral({
    required this.outlined,
    required this.filled,
    required this.label,
    required this.selected,
    required this.isDark,
    required this.larga,
    required this.onTap,
    this.badge = 0,
  });

  @override
  Widget build(BuildContext context) {
    final cor = selected
        ? AppColors.blue
        : (isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight);

    final icone = Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(selected ? filled : outlined, size: 23, color: cor),
        if (badge > 0)
          Positioned(
            top: -5,
            right: -8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
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
    );

    final texto = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontFamily: 'Poppins',
        fontSize: larga ? 14 : 10.5,
        fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
        color: cor,
      ),
    );

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: AoPassarOMouse(
        onTap: onTap,
        builder: (context, passando) => AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          margin: const EdgeInsets.symmetric(vertical: 2),
          padding: larga
              ? const EdgeInsets.symmetric(horizontal: 12, vertical: 12)
              : const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.blue.withValues(alpha: 0.14)
                : (passando
                    ? (isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : Colors.black.withValues(alpha: 0.05))
                    : Colors.transparent),
            borderRadius: BorderRadius.circular(18),
          ),
          child: larga
              ? Row(children: [icone, const SizedBox(width: 12), Expanded(child: texto)])
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [icone, const SizedBox(height: 3), texto],
                ),
        ),
      ),
    );
  }
}

/// As cinco abas, na ordem da barra de baixo e da navegação lateral.
const _abas = [
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

  static const _items = _abas;

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
