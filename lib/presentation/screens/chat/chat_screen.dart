import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../providers/auth_provider.dart';
import '../../providers/chat_provider.dart';
import '../../providers/songs_provider.dart';
import '../../providers/scale_provider.dart';
import '../../widgets/common/error_banner.dart';
import '../../widgets/chat/voz.dart';
import '../../../data/models/leitura_do_chat.dart';
import '../../../data/models/user_model.dart';
import '../../../data/services/avisos_service.dart';
import '../../../data/services/firestore_service.dart';
import '../../../data/services/leituras_service.dart';
import '../../../core/platform/voz.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/models/message_model.dart';
import '../../../data/models/song_model.dart';
import '../../../data/models/scale_model.dart';

/// Liquid Glass chat palette (translucent surfaces over the app backdrop).
class _Wa {
  // Frosted, translucent header surfaces.
  static const headerLight = Color(0x9EFFFFFF); // white ~62%
  static const headerDark = Color(0x8C141019); // dark  ~55%
  // Glass bubbles.
  static const inBubbleLight = Color(0xCCFFFFFF); // white 80%
  static const inBubbleDark = Color(0x1FFFFFFF); // white 12%
  static const outBubbleLight = Color(0x3D1565C0); // brand blue ~24%
  static const outBubbleDark = Color(0x4D5E92F3); // blue light  ~30%
  static const textLight = Color(0xFF14202B);
  static const textDark = Color(0xFFEAF0F6);
  static const metaLight = Color(0xFF5B6B7A);
  static const metaDark = Color(0xFF9FB0BF);
  // Accent (send button, highlights). Brand blue instead of WhatsApp green.
  static const sendGreen = AppColors.blue;
  static const pillLight = Color(0x8CFFFFFF); // white 55%
  static const pillDark = Color(0x14FFFFFF); // white 8%
  static const dateChipLight = Color(0xCCFFFFFF);
  static const dateChipDark = Color(0x59141019);
  static const noticeLight = Color(0xE6FFF4D2);
  static const noticeDark = Color(0x33FFE08A);

  /// Per-sender name colors used above incoming bubbles (group chat).
  static const nameColors = [
    Color(0xFF00A884),
    Color(0xFF53BDEB),
    Color(0xFFF15C6D),
    Color(0xFF7F66FF),
    Color(0xFFE542A3),
    Color(0xFFF4A027),
    Color(0xFF1F9D55),
    Color(0xFF8B5CF6),
    Color(0xFF0EA5E9),
    Color(0xFFEF6C33),
  ];

  static Color nameColor(String name) {
    if (name.isEmpty) return nameColors.first;
    return nameColors[name.hashCode.abs() % nameColors.length];
  }
}

class ChatScreen extends StatefulWidget {
  /// Liga as escutas do banco (leituras, "visto por"). Desligado só pelo
  /// roteiro que fotografa as telas sem Firebase.
  final bool escutas;

  const ChatScreen({super.key, this.escutas = true});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _messageCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  bool _showSongSearch = false;
  final _songSearchCtrl = TextEditingController();

  // In-chat message search
  bool _searchMode = false;
  final _searchCtrl = TextEditingController();

  ChatProvider? _chat;
  AuthProvider? _auth;
  int _lastMessageCount = 0;

  /// A mensagem que estou respondendo, ou nulo.
  MessageModel? _respondendoA;

  final _focoDaMensagem = FocusNode();

  /// Até onde cada pessoa leu, e quem é o ministério.
  ///
  /// As duas escutas começam ao abrir o chat: ~15 documentos cada, e é delas
  /// que saem os dois tiques azuis e a lista de quem mencionar. Sem a lista
  /// de pessoas, "visto por" não teria contra quem comparar.
  List<LeituraDoChat> _leituras = const [];
  /// As pessoas do ministério vêm do `AuthProvider`, que mantém UMA escuta
  /// para o app todo. Esta tela tinha a sua, e a Escala e o Início passaram a
  /// precisar da mesma lista: três escutas sobre os mesmos ~15 documentos
  /// custariam o triplo de leitura pela mesma informação.
  List<UserModel> _pessoas = const [];
  StreamSubscription<List<LeituraDoChat>>? _escutaLeituras;

  /// Quem foi mencionado nesta mensagem que estou escrevendo: nome → uid.
  ///
  /// Guardado à parte do texto porque é o uid que o Worker usa. Ler o @nome
  /// do texto no envio não serviria: nome se repete e muda.
  final Map<String, String> _mencionados = {};

  /// O pedaço depois do "@" que estou digitando, ou nulo.
  String? _procurandoMencao;

  // "typing…" presence broadcast
  Timer? _typingStopTimer;
  bool _broadcasting = false;

  @override
  void initState() {
    super.initState();
    _chat = context.read<ChatProvider>();
    _auth = context.read<AuthProvider>();
    _lastMessageCount = _chat!.messages.length;
    // Scroll to the bottom only when a new message actually arrives.
    _chat!.addListener(_onMessagesChanged);
    // Broadcast typing presence as the user types.
    _messageCtrl.addListener(_handleTyping);
    // Re-filter results as the search query changes.
    _searchCtrl.addListener(_onSearchChanged);
    // O "@" no texto abre a lista de quem mencionar.
    _messageCtrl.addListener(_olharPorMencao);

    if (widget.escutas) {
      _escutaLeituras = LeiturasService.escutar().listen((l) {
        if (mounted) setState(() => _leituras = l);
      }, onError: (_) {
        // Sem as leituras, as bolhas ficam com um tique cinza. É o pior caso
        // seguro: nunca dois tiques azuis adivinhados.
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _marcarComoLido();
      });
    }
  }

  void _onMessagesChanged() {
    final count = _chat?.messages.length ?? 0;
    if (count != _lastMessageCount) {
      _lastMessageCount = count;
      _scrollToBottom();
      // Mensagem nova com o chat aberto já conta como lida: a pessoa está
      // olhando para ela.
      _marcarComoLido();
    }
  }

  /// Marca o chat como lido até a mensagem mais recente.
  ///
  /// O serviço engole a chamada repetida (ele guarda até onde já marcou), por
  /// isso aqui se pode chamar sem medo a cada mensagem que chega.
  void _marcarComoLido() {
    final eu = _auth?.user;
    final mensagens = _chat?.messages ?? const <MessageModel>[];
    if (eu == null || mensagens.isEmpty) return;
    LeiturasService.marcarLido(
      userId: eu.id,
      userName: eu.name,
      ultimaMensagem: mensagens.last.timestamp,
    );
  }

  /// Vê se o texto tem um "@" sendo digitado, e abre a lista.
  void _olharPorMencao() {
    final texto = _messageCtrl.text;
    final cursor = _messageCtrl.selection.baseOffset;
    if (cursor <= 0 || cursor > texto.length) {
      if (_procurandoMencao != null) setState(() => _procurandoMencao = null);
      return;
    }
    final antes = texto.substring(0, cursor);
    // O "@" tem de estar no começo ou depois de um espaço: um e-mail no meio
    // do recado não abre a lista.
    final casa = RegExp(r'(?:^|\s)@([\p{L} ]{0,20})$', unicode: true)
        .firstMatch(antes);
    final novo = casa?.group(1);
    if (novo != _procurandoMencao) {
      setState(() => _procurandoMencao = novo);
    }
  }

  /// Põe o nome escolhido no texto e guarda o uid.
  void _escolherMencao(UserModel pessoa) {
    final texto = _messageCtrl.text;
    final cursor = _messageCtrl.selection.baseOffset.clamp(0, texto.length);
    final antes = texto.substring(0, cursor);
    final casa = RegExp(r'@([\p{L} ]{0,20})$', unicode: true).firstMatch(antes);
    if (casa == null) return;
    final inicio = casa.start;
    final novoTexto =
        '${texto.substring(0, inicio)}@${pessoa.name} ${texto.substring(cursor)}';
    _mencionados[pessoa.name] = pessoa.id;
    _messageCtrl.value = TextEditingValue(
      text: novoTexto,
      selection: TextSelection.collapsed(
          offset: inicio + pessoa.name.length + 2),
    );
    setState(() => _procurandoMencao = null);
  }

  /// Os uid mencionados que ainda estão escritos no texto.
  ///
  /// Conferir o texto é o que impede mandar menção de alguém cujo "@nome" a
  /// pessoa apagou depois de escolher na lista.
  List<String> _mencoesNoTexto() {
    final texto = _messageCtrl.text;
    final saida = <String>{};
    _mencionados.forEach((nome, uid) {
      if (texto.contains('@$nome')) saida.add(uid);
    });
    return saida.toList();
  }

  void _onSearchChanged() => setState(() {});

  void _handleTyping() {
    final u = _auth?.user;
    if (u == null) return;
    if (!_broadcasting) {
      _broadcasting = true;
      _chat?.setTyping(userId: u.id, userName: u.name, typing: true);
    }
    _typingStopTimer?.cancel();
    _typingStopTimer = Timer(const Duration(seconds: 3), _stopTyping);
  }

  void _stopTyping() {
    _typingStopTimer?.cancel();
    if (!_broadcasting) return;
    _broadcasting = false;
    final u = _auth?.user;
    if (u != null) {
      _chat?.setTyping(userId: u.id, userName: u.name, typing: false);
    }
  }

  void _enterSearch() => setState(() {
        _searchMode = true;
        _showSongSearch = false;
      });

  void _exitSearch() => setState(() {
        _searchMode = false;
        _searchCtrl.clear();
      });

  @override
  void dispose() {
    _chat?.removeListener(_onMessagesChanged);
    _messageCtrl.removeListener(_handleTyping);
    _messageCtrl.removeListener(_olharPorMencao);
    _escutaLeituras?.cancel();
    _focoDaMensagem.dispose();
    _searchCtrl.removeListener(_onSearchChanged);
    _typingStopTimer?.cancel();
    _stopTyping();
    _messageCtrl.dispose();
    _scrollCtrl.dispose();
    _songSearchCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendMessage({String? linkedSongId, String? linkedSongName}) async {
    final text = _messageCtrl.text.trim();
    if (text.isEmpty && linkedSongId == null) return;

    final auth = context.read<AuthProvider>();
    final chat = context.read<ChatProvider>();

    if (auth.user == null) return;

    final citada = _respondendoA;
    final mencoes = _mencoesNoTexto();
    final error = await chat.sendMessage(
      userId: auth.user!.id,
      userName: auth.user!.name,
      text: text.isEmpty ? '🎵 Compartilhou uma música' : text,
      linkedSongId: linkedSongId,
      linkedSongName: linkedSongName,
      respondendoA: citada,
      mencoes: mencoes,
    );

    if (!mounted) return;

    if (error != null) {
      // O texto fica no campo para a pessoa poder tentar de novo, em vez de
      // ser apagado junto com a mensagem que nunca saiu.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), backgroundColor: AppColors.red),
      );
      return;
    }
    // A citação e as menções só se limpam quando a mensagem SAIU: tentar de
    // novo sem o contexto não é tentar a mesma coisa.
    setState(() {
      _respondendoA = null;
      _procurandoMencao = null;
    });
    _mencionados.clear();

    _messageCtrl.clear();
    _stopTyping();
    setState(() => _showSongSearch = false);
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _showInsertSongInScaleDialog(SongModel song) {
    final scaleProvider = context.read<ScaleProvider>();
    final upcoming = scaleProvider.getUpcomingScales(limit: 5);

    if (upcoming.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nenhum culto agendado')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Inserir na Escala',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 16)),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Adicionar "${song.name}" em qual culto?',
                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
                ),
                const SizedBox(height: 12),
                ...upcoming.map((scale) => ListTile(
                      title: Text(
                        scale.serviceType,
                        style: const TextStyle(
                            fontFamily: 'Poppins', fontSize: 13),
                      ),
                      subtitle: Text(
                        DateFormat("dd/MM 'às' HH:mm").format(scale.date),
                        style: const TextStyle(fontFamily: 'Poppins', fontSize: 11),
                      ),
                      leading: const Icon(Icons.church_rounded,
                          color: AppColors.blue),
                      onTap: () async {
                        Navigator.pop(ctx);
                        final scaleP = context.read<ScaleProvider>();
                        // Acrescenta dentro de uma transação: dois líderes
                        // adicionando ao mesmo tempo acabam com as duas
                        // músicas, não com uma só.
                        final error = await scaleP.addSong(
                          scale.id,
                          ScaleSong(songId: song.id),
                        );
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(error ??
                                  '${song.name} adicionada ao culto!'),
                              backgroundColor: error == null
                                  ? AppColors.success
                                  : AppColors.red,
                            ),
                          );
                        }
                      },
                    )),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final chat = context.watch<ChatProvider>();
    final songs = context.watch<SongsProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // A lista vem do provider, que a escuta uma vez para o app todo. Guardada
    // no estado porque os métodos de desenho das bolhas já a usam de vários
    // lugares, e passar por parâmetro mudaria dez assinaturas.
    _pessoas = auth.pessoas;

    final headerColor = isDark ? _Wa.headerDark : _Wa.headerLight;

    // Who is typing right now (fresh and excluding myself).
    final me = auth.user?.id;
    final now = DateTime.now();
    final typingNames = chat.typing
        .where((t) =>
            t.userId != me &&
            t.userName.isNotEmpty &&
            now.difference(t.updatedAt).inSeconds < 6)
        .map((t) => t.userName)
        .toList();
    final typingLabel = _typingLabel(typingNames);

    // In-chat search filtering.
    final query = _searchCtrl.text.trim().toLowerCase();
    final searching = _searchMode && query.isNotEmpty;
    final visible = searching
        ? chat.messages
            .where((m) =>
                m.text.toLowerCase().contains(query) ||
                (m.linkedSongName?.toLowerCase().contains(query) ?? false))
            .toList()
        : chat.messages;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: _searchMode
          ? _buildSearchAppBar(headerColor, isDark)
          : _buildNormalAppBar(
              headerColor, typingLabel, chat.messages.isNotEmpty, isDark),
      body: Column(
        children: [
          ErrorBanner.maybe(chat.error, onRetry: chat.retry),
          // As fixadas ficam à vista, fora da rolagem: foram fixadas
          // justamente para não se perderem conversa acima.
          if (!_searchMode && chat.fixadas.isNotEmpty)
            _Fixadas(
              mensagens: chat.fixadas,
              isDark: isDark,
              podeDesafixar: auth.isAdmin,
              aoTocar: auth.isAdmin ? _perguntarSobreFixar : null,
            ),
          if (_showSongSearch && !_searchMode)
            _buildSongSearchPanel(auth, songs, isDark),
          Expanded(
            child: chat.isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.blue))
                : _buildMessages(visible, auth, songs, isDark,
                    showNotice: !searching, searching: searching),
          ),
          if (_gravandoVoz) _tarjaGravando(isDark),
          if (!_searchMode) _buildInputBar(isDark),
        ],
      ),
    );
  }

  // Estado da gravação, só para desenhar a tarja: quem manda é o botão.
  bool _gravandoVoz = false;
  bool _vozVaiCancelar = false;
  int _vozMs = 0;

  /// Envia o áudio gravado. O áudio e a mensagem vão num lote só — ver
  /// `FirestoreService.enviarAudio`.
  Future<void> _enviarVoz(AudioGravado audio) async {
    final auth = context.read<AuthProvider>();
    final eu = auth.user;
    if (eu == null) return;

    final r = await FirestoreService.enviarAudio(
      userId: eu.id,
      userName: eu.name,
      bytes: audio.bytes,
      tipo: audio.tipo,
      duracaoMs: audio.duracaoMs,
    );
    if (r.success && r.mensagemId != null) {
      // Depois de gravado, e sem esperar: o áudio já está no chat de quem
      // tem o app aberto. O aviso é para quem está com o app fechado, e uma
      // falha nele não pode virar erro na tela de quem acabou de enviar.
      AvisosService.avisarDoChat(r.mensagemId!);
    }
    if (!mounted) return;
    if (!r.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(r.error ?? 'Não foi possível enviar o áudio.'),
            backgroundColor: AppColors.red),
      );
    }
  }

  /// A tarja de "gravando", acima da barra de digitar.
  Widget _tarjaGravando(bool isDark) {
    final s = (_vozMs / 1000).floor();
    final tempo = '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
    final cancelando = _vozVaiCancelar;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: (cancelando ? AppColors.red : AppColors.blue)
          .withValues(alpha: isDark ? 0.18 : 0.10),
      child: Row(
        children: [
          Icon(cancelando ? Icons.delete_outline_rounded : Icons.mic_rounded,
              size: 18, color: cancelando ? AppColors.red : AppColors.blue),
          const SizedBox(width: 10),
          Text(
            tempo,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: isDark
                  ? AppColors.textPrimaryDark
                  : AppColors.textPrimaryLight,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              cancelando
                  ? 'Solte para cancelar'
                  : 'Arraste para o lado para cancelar · máximo 2 minutos',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12,
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondaryLight,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String? _typingLabel(List<String> names) {
    if (names.isEmpty) return null;
    if (names.length == 1) return '${names.first} está digitando…';
    if (names.length == 2) {
      return '${names[0]} e ${names[1]} estão digitando…';
    }
    return 'várias pessoas estão digitando…';
  }

  PreferredSizeWidget _buildNormalAppBar(Color headerColor, String? typingLabel,
      bool hasMessages, bool isDark) {
    final fg = isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final sub = isDark ? _Wa.metaDark : _Wa.metaLight;
    return AppBar(
      backgroundColor: headerColor,
      foregroundColor: fg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      titleSpacing: 0,
      centerTitle: false,
      systemOverlayStyle:
          isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      title: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: AppColors.blue.withOpacity(0.15),
            child: const Icon(Icons.groups_rounded,
                color: AppColors.blue, size: 22),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Ministério de Louvor',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: fg,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  typingLabel ?? 'mensagens em tempo real',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11.5,
                    color: typingLabel != null ? AppColors.blue : sub,
                    fontStyle: typingLabel != null
                        ? FontStyle.italic
                        : FontStyle.normal,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        if (hasMessages)
          IconButton(
            tooltip: 'Buscar mensagens',
            icon: const Icon(Icons.search_rounded),
            onPressed: _enterSearch,
          ),
      ],
    );
  }

  PreferredSizeWidget _buildSearchAppBar(Color headerColor, bool isDark) {
    final fg = isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final sub = isDark ? _Wa.metaDark : _Wa.metaLight;
    return AppBar(
      backgroundColor: headerColor,
      foregroundColor: fg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      titleSpacing: 0,
      systemOverlayStyle:
          isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded),
        onPressed: _exitSearch,
      ),
      title: TextField(
        controller: _searchCtrl,
        autofocus: true,
        cursorColor: AppColors.blue,
        style: TextStyle(fontFamily: 'Poppins', fontSize: 16, color: fg),
        decoration: InputDecoration(
          hintText: 'Buscar mensagens…',
          hintStyle:
              TextStyle(fontFamily: 'Poppins', color: sub, fontSize: 16),
          border: InputBorder.none,
        ),
      ),
      actions: [
        if (_searchCtrl.text.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () => _searchCtrl.clear(),
          ),
      ],
    );
  }

  /// Fixar ou desafixar, pelo gesto de segurar a bolha. Só o líder chega
  /// aqui — e as regras do banco recusam qualquer outro, não só a tela.
  // ── Reações, citação e "visto por" ──────────────────────────────────────

  /// A folha que abre ao segurar a bolha: os cinco emojis e as ações.
  ///
  /// Uma folha só, e não um menu de emoji separado do menu de ações: segurar
  /// a bolha é UM gesto, e quem segurou não sabe de antemão se quer reagir
  /// ou responder.
  Future<void> _abrirAcoesDaMensagem(MessageModel msg, bool isMe) async {
    final auth = context.read<AuthProvider>();
    final meuId = auth.user?.id ?? '';
    final minha = msg.minhaReacao(meuId);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: isDark ? const Color(0xFF171C23) : Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (folha) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 14, 10, 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: MessageModel.emojisDeReacao.map((emoji) {
                  final marcado = minha == emoji;
                  return GestureDetector(
                    onTap: () {
                      Navigator.pop(folha);
                      // Tocar no que já está marcado TIRA: é o mesmo gesto
                      // para pôr e para desfazer.
                      _reagir(msg, marcado ? null : emoji);
                    },
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: marcado
                            ? AppColors.blue.withValues(alpha: 0.22)
                            : Colors.transparent,
                      ),
                      child: Text(emoji, style: const TextStyle(fontSize: 27)),
                    ),
                  );
                }).toList(),
              ),
            ),
            const Divider(height: 10),
            ListTile(
              leading: const Icon(Icons.reply_rounded),
              title: const Text('Responder',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 14)),
              onTap: () {
                Navigator.pop(folha);
                _responderA(msg);
              },
            ),
            if (isMe)
              ListTile(
                leading: const Icon(Icons.done_all_rounded),
                title: const Text('Visto por',
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 14)),
                onTap: () {
                  Navigator.pop(folha);
                  _mostrarQuemViu(msg);
                },
              ),
            // Levar para o culto é do LÍDER: a observação do culto é o
            // combinado oficial, e todo mundo escalado lê. Chat é conversa;
            // observação é decisão.
            if (auth.isAdmin && msg.text.trim().isNotEmpty)
              ListTile(
                leading: const Icon(Icons.event_note_outlined),
                title: const Text('Levar para o culto',
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 14)),
                onTap: () {
                  Navigator.pop(folha);
                  _levarParaOCulto(msg);
                },
              ),
            if (auth.isAdmin)
              ListTile(
                leading: Icon(msg.fixada
                    ? Icons.push_pin_outlined
                    : Icons.push_pin_rounded),
                title: Text(msg.fixada ? 'Desafixar' : 'Fixar no topo',
                    style: const TextStyle(
                        fontFamily: 'Poppins', fontSize: 14)),
                onTap: () {
                  Navigator.pop(folha);
                  _perguntarSobreFixar(msg);
                },
              ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }

  /// "Levar para o culto": o recado vira uma linha nas observações.
  ///
  /// POR QUE ISTO EXISTE
  ///
  /// O combinado nascia no chat — "domingo entra sem bateria", "a Ana leva o
  /// cabo" — e morria lá: em 30 dias a mensagem some, e quem abrir o culto no
  /// domingo não vê nada. Copiar à mão era o que o líder fazia, quando
  /// lembrava.
  ///
  /// O culto PADRÃO é o próximo, porque é dele que a conversa quase sempre
  /// fala. Mas a escolha existe: combinação de ensaio e de culto grande vêm
  /// na mesma conversa.
  Future<void> _levarParaOCulto(MessageModel msg) async {
    final cultos = context.read<ScaleProvider>().getUpcomingScales(limit: 8);
    if (cultos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não há culto marcado para levar o '
            'recado.')),
      );
      return;
    }

    final escolhido = await showModalBottomSheet<ScaleModel>(
      context: context,
      builder: (folha) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(
                'Levar para qual culto?',
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 15,
                    fontWeight: FontWeight.w600),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Text(
                'O recado entra nas observações do culto, com o seu nome e a '
                'data. Todo mundo escalado vê.',
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12,
                    height: 1.4,
                    color: AppColors.textSecondaryLight),
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: cultos.length,
                itemBuilder: (_, i) {
                  final c = cultos[i];
                  return ListTile(
                    leading: Icon(
                      i == 0 ? Icons.star_rounded : Icons.event_outlined,
                      color: i == 0 ? AppColors.blue : null,
                      size: 20,
                    ),
                    title: Text(
                      '${c.serviceType} · '
                      '${DateFormat("EEEE, d/MM 'às' HH:mm", 'pt_BR')
                          .format(c.date)}',
                      style: const TextStyle(
                          fontFamily: 'Poppins', fontSize: 13),
                    ),
                    subtitle: i == 0
                        ? const Text('o próximo',
                            style: TextStyle(
                                fontFamily: 'Poppins', fontSize: 11))
                        : null,
                    onTap: () => Navigator.pop(folha, c),
                  );
                },
              ),
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
    if (escolhido == null || !mounted) return;

    final eu = context.read<AuthProvider>().user;
    final erro = await context.read<ScaleProvider>().acrescentarObservacao(
          escolhido.id,
          msg.text,
          eu?.name ?? '',
        );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(erro ?? 'Recado levado para as observações do culto.'),
        backgroundColor: erro == null ? AppColors.success : AppColors.red,
      ),
    );
  }

  Future<void> _reagir(MessageModel msg, String? emoji) async {
    final meuId = context.read<AuthProvider>().user?.id ?? '';
    if (meuId.isEmpty) return;
    final erro = await FirestoreService.reagir(
        mensagemId: msg.id, meuId: meuId, emoji: emoji);
    if (erro == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(erro), backgroundColor: AppColors.red),
    );
  }

  void _responderA(MessageModel msg) {
    setState(() => _respondendoA = msg);
    _focoDaMensagem.requestFocus();
  }

  /// Quem reagiu com o quê. Nome e emoji, sem hora: a hora da reação não
  /// interessa a ninguém, e guardá-la custaria um campo por reação.
  Future<void> _mostrarQuemReagiu(MessageModel msg) async {
    if (!msg.temReacoes) return;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final nomes = {for (final u in _pessoas) u.id: u.name};
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: isDark ? const Color(0xFF171C23) : Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text('Reações',
                  style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 15,
                      fontWeight: FontWeight.w600)),
            ),
            ...msg.reacoes.entries.map((e) => ListTile(
                  dense: true,
                  leading: Text(e.value, style: const TextStyle(fontSize: 20)),
                  title: Text(nomes[e.key] ?? 'Alguém',
                      style: const TextStyle(
                          fontFamily: 'Poppins', fontSize: 14)),
                )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// "Visto por" e "Ainda não viu", com a hora de quem viu.
  Future<void> _mostrarQuemViu(MessageModel msg) async {
    final r = quemViu(
        mensagem: msg, leituras: _leituras, aprovados: _pessoas);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: isDark ? const Color(0xFF171C23) : Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Text(
                r.viram.isEmpty
                    ? 'Ninguém viu ainda'
                    : 'Visto por ${r.viram.length} '
                        '${r.viram.length == 1 ? 'pessoa' : 'pessoas'}',
                style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 15,
                    fontWeight: FontWeight.w600),
              ),
            ),
            ...r.viram.map((v) => ListTile(
                  dense: true,
                  leading: const Icon(Icons.done_all_rounded,
                      size: 18, color: Color(0xFF53BDEB)),
                  title: Text(v.userName,
                      style: const TextStyle(
                          fontFamily: 'Poppins', fontSize: 14)),
                  trailing: Text(
                    DateFormat('HH:mm').format(v.lidoAte),
                    style: const TextStyle(
                        fontFamily: 'Poppins', fontSize: 12),
                  ),
                )),
            if (r.naoViram.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 12, 20, 4),
                child: Text('Ainda não viu',
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
              ),
              ...r.naoViram.map((nome) => ListTile(
                    dense: true,
                    leading: const Icon(Icons.done_rounded,
                        size: 18, color: Colors.grey),
                    title: Text(nome,
                        style: const TextStyle(
                            fontFamily: 'Poppins', fontSize: 14)),
                  )),
            ],
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  bool? _vistaPorTodos(MessageModel msg) {
    // Nulo enquanto as leituras não chegaram: um tique cinza é mais honesto
    // que dois azuis adivinhados.
    if (_pessoas.isEmpty) return null;
    return vistaPorTodos(
        mensagem: msg, leituras: _leituras, aprovados: _pessoas);
  }

  Future<void> _perguntarSobreFixar(MessageModel msg) async {
    final fixar = !msg.fixada;
    final chat = context.read<ChatProvider>();
    final eu = context.read<AuthProvider>().user?.id ?? '';

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(fixar ? 'Fixar esta mensagem?' : 'Desafixar?'),
        content: Text(
          fixar
              ? 'Ela vai para o topo do chat e NÃO some depois de 30 dias. '
                  'É o jeito de guardar uma combinação importante.'
              : 'Ela sai do topo e volta a sumir 30 dias depois de ter sido '
                  'enviada.',
          style: const TextStyle(fontFamily: 'Poppins', fontSize: 13.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.blue),
            child: Text(fixar ? 'Fixar' : 'Desafixar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final erro = await chat.fixar(msg, fixar, eu);
    if (!mounted) return;
    if (erro != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(erro), backgroundColor: AppColors.red),
      );
    }
  }

  Widget _buildMessages(List<MessageModel> messages, AuthProvider auth,
      SongsProvider songs, bool isDark,
      {bool showNotice = true, bool searching = false}) {
    if (messages.isEmpty) {
      if (searching) {
        return Center(
          child: Text(
            'Nenhuma mensagem encontrada',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 13,
              color: isDark ? _Wa.metaDark : _Wa.metaLight,
            ),
          ),
        );
      }
      return Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 40),
              const _EncryptionNotice(),
              const SizedBox(height: 24),
              Icon(Icons.chat_bubble_outline_rounded,
                  size: 52,
                  color: isDark ? Colors.white24 : Colors.black26),
              const SizedBox(height: 12),
              Text(
                'Nenhuma mensagem ainda.\nDiga olá ao ministério! 👋',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  color: isDark ? _Wa.metaDark : _Wa.metaLight,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final headerCount = showNotice ? 1 : 0;
    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.fromLTRB(6, 10, 6, 8),
      itemCount: messages.length + headerCount,
      itemBuilder: (ctx, index) {
        // First item: WhatsApp-style "encryption" notice.
        if (showNotice && index == 0) {
          return const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: _EncryptionNotice(),
          );
        }
        final i = index - headerCount;
        final msg = messages[i];
        final prev = i > 0 ? messages[i - 1] : null;
        final next = i < messages.length - 1 ? messages[i + 1] : null;
        final isMe = msg.userId == auth.user?.id;

        final showDate =
            prev == null || !_isSameDay(prev.timestamp, msg.timestamp);
        // A ordem importa: checar prev antes deixa o analisador saber que
        // prev não é nulo no resto da expressão.
        final isFirstOfGroup =
            prev == null || showDate || prev.userId != msg.userId;
        final isLastOfGroup = next == null ||
            next.userId != msg.userId ||
            !_isSameDay(msg.timestamp, next.timestamp);

        return Column(
          children: [
            if (showDate) _WaDateChip(date: msg.timestamp, isDark: isDark),
            // Segurar a bolha abre as reações e as ações; arrastar para a
            // direita responde citando. Os dois gestos são os do WhatsApp, e
            // é o que esta equipe já sabe de cor.
            GestureDetector(
              onLongPress: () => _abrirAcoesDaMensagem(msg, isMe),
              // Arrasto HORIZONTAL não briga com a rolagem vertical da lista.
              onHorizontalDragEnd: (d) {
                // Só para a direita, e só com empurrão de verdade: um
                // arrasto curto é quase sempre tentativa de rolar.
                if (d.primaryVelocity != null && d.primaryVelocity! > 250) {
                  _responderA(msg);
                }
              },
              child: _WaMessageBubble(
                message: msg,
                isMe: isMe,
                isDark: isDark,
                showName: isFirstOfGroup && !isMe,
                showTail: isFirstOfGroup,
                showAvatar: isLastOfGroup && !isMe,
                meuId: auth.user?.id ?? '',
                vistaPorTodos: isMe ? _vistaPorTodos(msg) : null,
                onVerReacoes: () => _mostrarQuemReagiu(msg),
                onVerQuemViu: isMe ? () => _mostrarQuemViu(msg) : null,
                onSongTap: msg.linkedSongId != null
                    ? () {
                        final song = songs.getSongById(msg.linkedSongId!);
                        if (song != null && auth.isAdmin) {
                          _showInsertSongInScaleDialog(song);
                        }
                      }
                      : null,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildInputBar(bool isDark) {
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_procurandoMencao != null) _listaDeMencoes(isDark),
          if (_respondendoA != null) _faixaDaCitacao(isDark),
          _barraDeDigitar(isDark),
        ],
      ),
    );
  }

  /// Quem mencionar, enquanto se digita "@".
  ///
  /// A lista vem das pessoas aprovadas, não dos nomes do chat: quem nunca
  /// escreveu também pode ser chamado.
  Widget _listaDeMencoes(bool isDark) {
    final procura = (_procurandoMencao ?? '').trim().toLowerCase();
    final meuId = _auth?.user?.id ?? '';
    final achados = _pessoas
        .where((p) => p.id != meuId)
        .where((p) => procura.isEmpty || p.name.toLowerCase().contains(procura))
        .take(6)
        .toList();
    if (achados.isEmpty) return const SizedBox.shrink();

    return Container(
      constraints: const BoxConstraints(maxHeight: 200),
      margin: const EdgeInsets.fromLTRB(7, 0, 7, 4),
      decoration: BoxDecoration(
        color: isDark ? _Wa.pillDark : Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 10,
              offset: const Offset(0, -2)),
        ],
      ),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 4),
        children: achados
            .map((pessoa) => ListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  leading: CircleAvatar(
                    radius: 14,
                    backgroundColor:
                        _Wa.nameColor(pessoa.name).withValues(alpha: 0.2),
                    child: Text(
                      pessoa.name.isEmpty ? '?' : pessoa.name[0].toUpperCase(),
                      style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: _Wa.nameColor(pessoa.name)),
                    ),
                  ),
                  title: Text(pessoa.name,
                      style: const TextStyle(
                          fontFamily: 'Poppins', fontSize: 13.5)),
                  subtitle: Text(
                    'avisa mesmo com o chat silenciado',
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 11,
                        color: isDark ? _Wa.metaDark : _Wa.metaLight),
                  ),
                  onTap: () => _escolherMencao(pessoa),
                ))
            .toList(),
      ),
    );
  }

  /// A mensagem que estou respondendo, acima do campo.
  Widget _faixaDaCitacao(bool isDark) {
    final msg = _respondendoA!;
    return Container(
      margin: const EdgeInsets.fromLTRB(7, 0, 7, 4),
      padding: const EdgeInsets.fromLTRB(10, 7, 4, 7),
      decoration: BoxDecoration(
        color: isDark ? _Wa.pillDark : _Wa.pillLight,
        borderRadius: BorderRadius.circular(12),
        border:
            Border(left: BorderSide(color: _Wa.nameColor(msg.userName), width: 3)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Respondendo a ${msg.userName}',
                  style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: _Wa.nameColor(msg.userName)),
                ),
                Text(
                  msg.temAudio ? '🎤 Mensagem de voz' : msg.text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12.5,
                      color: isDark ? _Wa.metaDark : _Wa.metaLight),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Cancelar a resposta',
            icon: Icon(Icons.close_rounded,
                size: 18, color: isDark ? _Wa.metaDark : _Wa.metaLight),
            onPressed: () => setState(() => _respondendoA = null),
          ),
        ],
      ),
    );
  }

  Widget _barraDeDigitar(bool isDark) {
    return Padding(
        padding: const EdgeInsets.fromLTRB(7, 4, 7, 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Pill: attach-song toggle + text field
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: isDark ? _Wa.pillDark : _Wa.pillLight,
                  borderRadius: BorderRadius.circular(24),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Tooltip(
                      message: 'Buscar e compartilhar música',
                      child: IconButton(
                        onPressed: () => setState(
                            () => _showSongSearch = !_showSongSearch),
                        icon: Icon(
                          _showSongSearch
                              ? Icons.close_rounded
                              : Icons.music_note_rounded,
                          color: _showSongSearch
                              ? _Wa.sendGreen
                              : (isDark ? _Wa.metaDark : _Wa.metaLight),
                          size: 24,
                        ),
                        splashRadius: 22,
                      ),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _messageCtrl,
                        focusNode: _focoDaMensagem,
                        maxLines: 5,
                        minLines: 1,
                        textCapitalization: TextCapitalization.sentences,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 15,
                          color: isDark ? _Wa.textDark : _Wa.textLight,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Mensagem',
                          hintStyle: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 15,
                            color: isDark ? _Wa.metaDark : _Wa.metaLight,
                          ),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 11),
                        ),
                        onSubmitted: (_) => _sendMessage(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 6),
            // Enviar quando há texto; microfone quando não há. É a troca que
            // o WhatsApp faz, e evita dois botões disputando o mesmo canto.
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _messageCtrl,
              builder: (context, value, _) {
                final hasText = value.text.trim().isNotEmpty;
                if (!hasText && vozSuportada) {
                  return BotaoDeVoz(
                    isDark: isDark,
                    aoMudar: (gravando, vaiCancelar, ms) {
                      if (!mounted) return;
                      setState(() {
                        _gravandoVoz = gravando;
                        _vozVaiCancelar = vaiCancelar;
                        _vozMs = ms;
                      });
                    },
                    aoGravar: _enviarVoz,
                  );
                }
                return GestureDetector(
                  onTap: hasText ? _sendMessage : null,
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: hasText
                          ? _Wa.sendGreen
                          : _Wa.sendGreen.withOpacity(0.55),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.send_rounded,
                        size: 22, color: Colors.white),
                  ),
                );
              },
            ),
          ],
        ),
    );
  }

  Widget _buildSongSearchPanel(
      AuthProvider auth, SongsProvider songs, bool isDark) {
    final results = songs.repertorio.where((s) {
      final q = _songSearchCtrl.text.toLowerCase();
      if (q.isEmpty) return true;
      return s.name.toLowerCase().contains(q) ||
          s.artist.toLowerCase().contains(q);
    }).toList();

    return Material(
      color: isDark
          ? const Color(0xF21A1016)
          : Colors.white.withOpacity(0.92),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.library_music_rounded,
                    size: 18, color: _Wa.sendGreen),
                const SizedBox(width: 6),
                Text(
                  auth.isAdmin
                      ? 'Enviar no chat ou adicionar à escala'
                      : 'Compartilhar uma música no chat',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isDark ? _Wa.textDark : _Wa.textLight,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () {
                    setState(() => _showSongSearch = false);
                    _songSearchCtrl.clear();
                  },
                  child: Icon(Icons.close_rounded,
                      size: 18, color: isDark ? _Wa.metaDark : _Wa.metaLight),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _songSearchCtrl,
              autofocus: true,
              onChanged: (v) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Nome ou artista...',
                prefixIcon: const Icon(Icons.search_rounded, size: 18),
                isDense: true,
                filled: true,
                fillColor: isDark ? Colors.grey.shade800 : Colors.grey.shade100,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 130,
              child: results.isEmpty
                  ? Center(
                      child: Text(
                        'Nenhuma música encontrada',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 12,
                          color: isDark ? _Wa.metaDark : _Wa.metaLight,
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: results.length,
                      itemBuilder: (_, i) {
                        final song = results[i];
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(song.name,
                              style: const TextStyle(
                                  fontFamily: 'Poppins', fontSize: 13)),
                          subtitle: Text(
                              '${song.artist} • ${song.originalKey}',
                              style: const TextStyle(
                                  fontFamily: 'Poppins', fontSize: 11)),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Tooltip(
                                message: 'Enviar no chat',
                                child: GestureDetector(
                                  onTap: () => _sendMessage(
                                    linkedSongId: song.id,
                                    linkedSongName: song.name,
                                  ),
                                  child: const Icon(Icons.send_rounded,
                                      size: 20, color: _Wa.sendGreen),
                                ),
                              ),
                              if (auth.isAdmin) ...[
                                const SizedBox(width: 14),
                                Tooltip(
                                  message: 'Adicionar à escala',
                                  child: GestureDetector(
                                    onTap: () =>
                                        _showInsertSongInScaleDialog(song),
                                    child: const Icon(
                                        Icons.calendar_month_rounded,
                                        size: 20,
                                        color: AppColors.red),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}

// ─── Encryption-style notice ───────────────────────────────────────────────

/// A faixa das mensagens fixadas, no topo do chat.
///
/// Fora da rolagem de propósito: uma mensagem é fixada porque precisa ser
/// vista, e dentro da lista ela voltaria a subir conversa acima em um dia.
class _Fixadas extends StatelessWidget {
  final List<MessageModel> mensagens;
  final bool isDark;
  final bool podeDesafixar;
  final void Function(MessageModel)? aoTocar;

  const _Fixadas({
    required this.mensagens,
    required this.isDark,
    required this.podeDesafixar,
    this.aoTocar,
  });

  @override
  Widget build(BuildContext context) {
    final corTexto =
        isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final corFraca =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 112),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.white.withValues(alpha: 0.55),
        border: Border(
          bottom: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.06),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.push_pin_rounded, size: 13, color: corFraca),
              const SizedBox(width: 5),
              Text(
                mensagens.length == 1
                    ? 'Fixada'
                    : '${mensagens.length} fixadas',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: corFraca,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: mensagens.length,
              itemBuilder: (_, i) {
                final m = mensagens[i];
                return InkWell(
                  onTap: aoTocar == null ? null : () => aoTocar!(m),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: RichText(
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            text: TextSpan(
                              children: [
                                TextSpan(
                                  text: '${m.userName}: ',
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: corTexto,
                                  ),
                                ),
                                TextSpan(
                                  text: m.text,
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 12.5,
                                    height: 1.35,
                                    color: corTexto,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (podeDesafixar)
                          Padding(
                            padding: const EdgeInsets.only(left: 6, top: 1),
                            child: Icon(Icons.close_rounded,
                                size: 14, color: corFraca),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _EncryptionNotice extends StatelessWidget {
  const _EncryptionNotice();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 32),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isDark ? _Wa.noticeDark : _Wa.noticeLight,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_delete_outlined,
                size: 13, color: isDark ? _Wa.metaDark : const Color(0xFF8A7B3D)),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                // A promessa precisa estar à vista: quem conta uma decisão
                // importante no chat tem de saber que ela some.
                'As mensagens somem depois de 30 dias. '
                'Fixe o que for importante.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 11,
                  color:
                      isDark ? _Wa.metaDark : const Color(0xFF8A7B3D),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Date chip ─────────────────────────────────────────────────────────────

class _WaDateChip extends StatelessWidget {
  final DateTime date;
  final bool isDark;
  const _WaDateChip({required this.date, required this.isDark});

  String get _label {
    final now = DateTime.now();
    if (date.year == now.year &&
        date.month == now.month &&
        date.day == now.day) {
      return 'HOJE';
    }
    final yesterday = now.subtract(const Duration(days: 1));
    if (date.year == yesterday.year &&
        date.month == yesterday.month &&
        date.day == yesterday.day) {
      return 'ONTEM';
    }
    return DateFormat('dd/MM/yyyy').format(date);
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: isDark ? _Wa.dateChipDark : _Wa.dateChipLight,
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.25 : 0.08),
              blurRadius: 2,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Text(
          _label,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 11,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.3,
            color: isDark ? _Wa.metaDark : _Wa.metaLight,
          ),
        ),
      ),
    );
  }
}

// ─── Message bubble ────────────────────────────────────────────────────────

class _WaMessageBubble extends StatelessWidget {
  final MessageModel message;
  final bool isMe;
  final bool isDark;
  final bool showName;
  final bool showTail;
  final bool showAvatar;
  final VoidCallback? onSongTap;

  /// Quem sou eu, para saber em qual emoji a minha reação está marcada.
  final String meuId;

  /// Todos os aprovados já viram? Só nas MINHAS mensagens, e nulo quando
  /// ainda não se sabe (as leituras não chegaram).
  final bool? vistaPorTodos;

  final VoidCallback? onVerReacoes;
  final VoidCallback? onVerQuemViu;

  const _WaMessageBubble({
    required this.message,
    required this.isMe,
    required this.isDark,
    required this.showName,
    required this.showTail,
    required this.showAvatar,
    this.onSongTap,
    this.meuId = '',
    this.vistaPorTodos,
    this.onVerReacoes,
    this.onVerQuemViu,
  });

  @override
  Widget build(BuildContext context) {
    final maxWidth = MediaQuery.of(context).size.width * 0.80;
    final bubbleColor = isMe
        ? (isDark ? _Wa.outBubbleDark : _Wa.outBubbleLight)
        : (isDark ? _Wa.inBubbleDark : _Wa.inBubbleLight);
    final textColor = isDark ? _Wa.textDark : _Wa.textLight;
    final metaColor = isDark ? _Wa.metaDark : _Wa.metaLight;

    final tailPad = showTail ? 11.0 : 9.0;

    return Padding(
      padding: EdgeInsets.only(
        top: showTail ? 6 : 1.5,
        left: 8,
        right: 8,
      ),
      child: Row(
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe)
            SizedBox(
              width: 34,
              child: showAvatar
                  ? CircleAvatar(
                      radius: 14,
                      backgroundColor: _Wa.nameColor(message.userName)
                          .withOpacity(0.22),
                      child: Text(
                        message.userName.isNotEmpty
                            ? message.userName[0].toUpperCase()
                            : '?',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: _Wa.nameColor(message.userName),
                        ),
                      ),
                    )
                  : null,
            ),
          Flexible(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: CustomPaint(
                painter: _BubblePainter(
                  color: bubbleColor,
                  isMe: isMe,
                  showTail: showTail,
                  isDark: isDark,
                ),
                child: Padding(
                  padding: EdgeInsets.only(
                    top: 6,
                    bottom: 5,
                    left: isMe ? 9 : tailPad,
                    right: isMe ? tailPad : 9,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (showName)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Text(
                            message.userName,
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: _Wa.nameColor(message.userName),
                            ),
                          ),
                        ),
                      // O pedaço citado, quando é resposta a outra
                      // mensagem. Fica ACIMA do texto, como no WhatsApp: é o
                      // contexto, e lê-se antes da resposta.
                      if (message.temCitacao)
                        Container(
                          margin: const EdgeInsets.only(bottom: 5),
                          padding: const EdgeInsets.fromLTRB(8, 5, 8, 6),
                          decoration: BoxDecoration(
                            color: (isDark ? Colors.white : Colors.black)
                                .withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(6),
                            border: Border(
                              left: BorderSide(
                                color: _Wa.nameColor(
                                    message.respondeANome ?? ''),
                                width: 3,
                              ),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                message.respondeANome ?? '',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: _Wa.nameColor(
                                      message.respondeANome ?? ''),
                                ),
                              ),
                              Text(
                                message.respondeATexto ?? '',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 12.5,
                                  height: 1.25,
                                  color: metaColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      // Mensagem de voz: o player no lugar do texto.
                      if (message.temAudio)
                        BolhaDeVoz(
                          mensagem: message,
                          isMe: isMe,
                          isDark: isDark,
                        ),
                      // O texto vem antes do cartão da música: quem compartilha
                      // escreve o recado ("essa cabe no domingo") e o cartão é
                      // o anexo, não o contrário.
                      Wrap(
                        alignment: WrapAlignment.end,
                        crossAxisAlignment: WrapCrossAlignment.end,
                        children: [
                          if (!message.temAudio)
                            Text(
                              message.text,
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 14.5,
                                height: 1.3,
                                color: textColor,
                              ),
                            ),
                          Padding(
                            padding: const EdgeInsets.only(left: 8, top: 2),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  DateFormat('HH:mm').format(message.timestamp),
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 11,
                                    color: metaColor,
                                  ),
                                ),
                                // Os tiques só nas MINHAS mensagens: nas dos
                                // outros eles não querem dizer nada para mim.
                                //
                                // Um cinza = está no banco. Dois azuis = todos
                                // os aprovados abriram o chat depois dela.
                                // Antes havia um ✓✓ fixo, que prometia
                                // confirmação de leitura sem nada registrar.
                                if (isMe)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 3),
                                    child: Icon(
                                      vistaPorTodos == true
                                          ? Icons.done_all_rounded
                                          : Icons.done_rounded,
                                      size: 14,
                                      color: vistaPorTodos == true
                                          ? const Color(0xFF53BDEB)
                                          : metaColor,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (message.temReacoes)
                        Padding(
                          padding: const EdgeInsets.only(top: 5),
                          child: GestureDetector(
                            onTap: onVerReacoes,
                            child: Wrap(
                              spacing: 4,
                              runSpacing: 4,
                              children: message.contagemDeReacoes.map((r) {
                                final minha =
                                    message.minhaReacao(meuId) == r.emoji;
                                return Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: minha
                                        ? AppColors.blue.withValues(alpha: 0.22)
                                        : (isDark ? Colors.white : Colors.black)
                                            .withValues(alpha: 0.07),
                                    borderRadius: BorderRadius.circular(999),
                                    border: minha
                                        ? Border.all(
                                            color: AppColors.blue
                                                .withValues(alpha: 0.6))
                                        : null,
                                  ),
                                  child: Text(
                                    r.quantas > 1
                                        ? '${r.emoji} ${r.quantas}'
                                        : r.emoji,
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      height: 1.25,
                                      color: textColor,
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                      if (message.hasSong && message.linkedSongName != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: _LinkedSongCard(
                            name: message.linkedSongName!,
                            isMe: isMe,
                            isDark: isDark,
                            onTap: onSongTap,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LinkedSongCard extends StatelessWidget {
  final String name;
  final bool isMe;
  final bool isDark;
  final VoidCallback? onTap;

  const _LinkedSongCard({
    required this.name,
    required this.isMe,
    required this.isDark,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = isMe ? Colors.white : _Wa.sendGreen;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6, top: 1),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        decoration: BoxDecoration(
          color: (isMe ? Colors.white : Colors.black)
              .withOpacity(isDark ? 0.10 : (isMe ? 0.18 : 0.05)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.music_note_rounded,
                size: 16,
                color: isMe
                    ? (isDark ? Colors.white : _Wa.textLight)
                    : _Wa.sendGreen),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                name,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: isMe
                      ? (isDark ? _Wa.textDark : _Wa.textLight)
                      : (isDark ? _Wa.textDark : _Wa.textLight),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 4),
              Icon(Icons.add_circle_outline_rounded, size: 14, color: accent),
            ],
          ],
        ),
      ),
    );
  }
}

/// Paints a WhatsApp-style bubble: rounded rectangle with a small tail at the
/// top corner on the sender's side (only when [showTail] is true).
class _BubblePainter extends CustomPainter {
  final Color color;
  final bool isMe;
  final bool showTail;
  final bool isDark;

  _BubblePainter({
    required this.color,
    required this.isMe,
    required this.showTail,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const radius = 10.0;
    const tailW = 7.0;
    const tailH = 9.0;

    final path = Path();

    if (!showTail) {
      path.addRRect(RRect.fromRectAndRadius(
        Offset.zero & size,
        const Radius.circular(radius),
      ));
    } else if (isMe) {
      // Bubble body inset from the right to leave room for the tail.
      final rect = Rect.fromLTWH(0, 0, size.width - tailW, size.height);
      path.addRRect(RRect.fromRectAndCorners(
        rect,
        topLeft: const Radius.circular(radius),
        topRight: const Radius.circular(2),
        bottomLeft: const Radius.circular(radius),
        bottomRight: const Radius.circular(radius),
      ));
      // Tail pointing up-right
      path.moveTo(size.width - tailW, 0);
      path.lineTo(size.width, 0);
      path.lineTo(size.width - tailW, tailH);
      path.close();
    } else {
      final rect = Rect.fromLTWH(tailW, 0, size.width - tailW, size.height);
      path.addRRect(RRect.fromRectAndCorners(
        rect,
        topLeft: const Radius.circular(2),
        topRight: const Radius.circular(radius),
        bottomLeft: const Radius.circular(radius),
        bottomRight: const Radius.circular(radius),
      ));
      // Tail pointing up-left
      path.moveTo(tailW, 0);
      path.lineTo(0, 0);
      path.lineTo(tailW, tailH);
      path.close();
    }

    // Soft shadow + translucent fill + hairline glass border.
    canvas.drawShadow(
        path, Colors.black.withOpacity(isDark ? 0.35 : 0.16), 1.0, false);
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withOpacity(isDark ? 0.12 : 0.55),
    );
  }

  @override
  bool shouldRepaint(covariant _BubblePainter old) =>
      old.color != color ||
      old.isMe != isMe ||
      old.showTail != showTail ||
      old.isDark != isDark;
}
