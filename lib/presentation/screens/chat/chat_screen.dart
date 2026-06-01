import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../providers/auth_provider.dart';
import '../../providers/chat_provider.dart';
import '../../providers/songs_provider.dart';
import '../../providers/scale_provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/models/message_model.dart';
import '../../../data/models/song_model.dart';
import '../../../data/models/scale_model.dart';

/// WhatsApp-like color palette, scoped to the chat screen so the rest of the
/// app keeps its own (Quadrangular) identity.
class _Wa {
  static const headerLight = Color(0xFF008069);
  static const headerDark = Color(0xFF1F2C34);
  static const bgLight = Color(0xFFEFEAE2);
  static const bgDark = Color(0xFF0B141A);
  static const inBubbleLight = Color(0xFFFFFFFF);
  static const inBubbleDark = Color(0xFF202C33);
  static const outBubbleLight = Color(0xFFD9FDD3);
  static const outBubbleDark = Color(0xFF005C4B);
  static const textLight = Color(0xFF111B21);
  static const textDark = Color(0xFFE9EDEF);
  static const metaLight = Color(0xFF667781);
  static const metaDark = Color(0xFF8696A0);
  static const sendGreen = Color(0xFF00A884);
  static const pillLight = Color(0xFFFFFFFF);
  static const pillDark = Color(0xFF2A3942);
  static const dateChipLight = Color(0xFFFFFFFF);
  static const dateChipDark = Color(0xFF182229);
  static const noticeLight = Color(0xFFFFF4D2);
  static const noticeDark = Color(0xFF182433);

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
  const ChatScreen({super.key});

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
  }

  void _onMessagesChanged() {
    final count = _chat?.messages.length ?? 0;
    if (count != _lastMessageCount) {
      _lastMessageCount = count;
      _scrollToBottom();
    }
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

    await chat.sendMessage(
      userId: auth.user!.id,
      userName: auth.user!.name,
      text: text.isEmpty ? '🎵 Compartilhou uma música' : text,
      linkedSongId: linkedSongId,
      linkedSongName: linkedSongName,
    );

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
                        DateFormat('dd/MM/yyyy').format(scale.date),
                        style: const TextStyle(fontFamily: 'Poppins', fontSize: 11),
                      ),
                      leading: const Icon(Icons.church_rounded,
                          color: AppColors.blue),
                      onTap: () async {
                        Navigator.pop(ctx);
                        final scaleP = context.read<ScaleProvider>();
                        final songs = scale.songs.toList();
                        songs.add(ScaleSong(
                          songId: song.id,
                          songName: song.name,
                          artist: song.artist,
                          key: song.originalKey,
                        ));
                        final updated = scale.copyWith(songs: songs);
                        await scaleP.updateScale(updated);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                  '${song.name} adicionada ao culto!'),
                              backgroundColor: AppColors.success,
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

    final bg = isDark ? _Wa.bgDark : _Wa.bgLight;
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
      backgroundColor: bg,
      appBar: _searchMode
          ? _buildSearchAppBar(headerColor)
          : _buildNormalAppBar(
              headerColor, typingLabel, chat.messages.isNotEmpty),
      body: Stack(
        children: [
          // Wallpaper (doodle pattern) behind everything
          Positioned.fill(child: _ChatWallpaper(isDark: isDark)),
          Column(
            children: [
              if (_showSongSearch && !_searchMode)
                _buildSongSearchPanel(auth, songs, isDark),
              Expanded(
                child: chat.isLoading
                    ? const Center(
                        child: CircularProgressIndicator(color: _Wa.sendGreen))
                    : _buildMessages(visible, auth, songs, isDark,
                        showNotice: !searching, searching: searching),
              ),
              if (!_searchMode) _buildInputBar(isDark),
            ],
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

  PreferredSizeWidget _buildNormalAppBar(
      Color headerColor, String? typingLabel, bool hasMessages) {
    return AppBar(
      backgroundColor: headerColor,
      foregroundColor: Colors.white,
      surfaceTintColor: headerColor,
      elevation: 0,
      titleSpacing: 0,
      centerTitle: false,
      systemOverlayStyle: SystemUiOverlayStyle.light,
      title: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: Colors.white.withOpacity(0.22),
            child: const Icon(Icons.groups_rounded,
                color: Colors.white, size: 22),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'Ministério de Louvor',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  typingLabel ?? 'mensagens em tempo real',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11.5,
                    color: typingLabel != null ? Colors.white : Colors.white70,
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

  PreferredSizeWidget _buildSearchAppBar(Color headerColor) {
    return AppBar(
      backgroundColor: headerColor,
      foregroundColor: Colors.white,
      surfaceTintColor: headerColor,
      elevation: 0,
      titleSpacing: 0,
      systemOverlayStyle: SystemUiOverlayStyle.light,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded),
        onPressed: _exitSearch,
      ),
      title: TextField(
        controller: _searchCtrl,
        autofocus: true,
        cursorColor: Colors.white,
        style: const TextStyle(
            fontFamily: 'Poppins', fontSize: 16, color: Colors.white),
        decoration: const InputDecoration(
          hintText: 'Buscar mensagens…',
          hintStyle: TextStyle(
              fontFamily: 'Poppins', color: Colors.white70, fontSize: 16),
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
        final isFirstOfGroup =
            showDate || prev == null || prev.userId != msg.userId;
        final isLastOfGroup = next == null ||
            next.userId != msg.userId ||
            !_isSameDay(msg.timestamp, next.timestamp);

        return Column(
          children: [
            if (showDate) _WaDateChip(date: msg.timestamp, isDark: isDark),
            _WaMessageBubble(
              message: msg,
              isMe: isMe,
              isDark: isDark,
              showName: isFirstOfGroup && !isMe,
              showTail: isFirstOfGroup,
              showAvatar: isLastOfGroup && !isMe,
              onSongTap: msg.linkedSongId != null
                  ? () {
                      final song = songs.getSongById(msg.linkedSongId!);
                      if (song != null && auth.isAdmin) {
                        _showInsertSongInScaleDialog(song);
                      }
                    }
                  : null,
            ),
          ],
        );
      },
    );
  }

  Widget _buildInputBar(bool isDark) {
    return SafeArea(
      top: false,
      child: Padding(
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
            // Round green send button — only this rebuilds while typing.
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _messageCtrl,
              builder: (context, value, _) {
                final hasText = value.text.trim().isNotEmpty;
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
      ),
    );
  }

  Widget _buildSongSearchPanel(
      AuthProvider auth, SongsProvider songs, bool isDark) {
    final results = songs.allSongs.where((s) {
      final q = _songSearchCtrl.text.toLowerCase();
      if (q.isEmpty) return true;
      return s.name.toLowerCase().contains(q) ||
          s.artist.toLowerCase().contains(q);
    }).toList();

    return Material(
      color: isDark ? _Wa.inBubbleDark : Colors.white,
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
            Icon(Icons.lock_outline_rounded,
                size: 13, color: isDark ? _Wa.metaDark : const Color(0xFF8A7B3D)),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                'As mensagens ficam dentro do seu ministério.',
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

  const _WaMessageBubble({
    required this.message,
    required this.isMe,
    required this.isDark,
    required this.showName,
    required this.showTail,
    required this.showAvatar,
    this.onSongTap,
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
                      if (message.hasSong && message.linkedSongName != null)
                        _LinkedSongCard(
                          name: message.linkedSongName!,
                          isMe: isMe,
                          isDark: isDark,
                          onTap: onSongTap,
                        ),
                      // Text + inline-ish meta (time + check), WhatsApp style.
                      Wrap(
                        alignment: WrapAlignment.end,
                        crossAxisAlignment: WrapCrossAlignment.end,
                        children: [
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
                                if (isMe) ...[
                                  const SizedBox(width: 3),
                                  Icon(Icons.done_all_rounded,
                                      size: 15, color: metaColor),
                                ],
                              ],
                            ),
                          ),
                        ],
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

    // Subtle drop shadow like WhatsApp.
    canvas.drawShadow(path, Colors.black.withOpacity(isDark ? 0.5 : 0.28),
        1.0, false);
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _BubblePainter old) =>
      old.color != color ||
      old.isMe != isMe ||
      old.showTail != showTail ||
      old.isDark != isDark;
}

// ─── Wallpaper ─────────────────────────────────────────────────────────────

class _ChatWallpaper extends StatelessWidget {
  final bool isDark;
  const _ChatWallpaper({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        size: Size.infinite,
        painter: _WallpaperPainter(isDark: isDark),
      ),
    );
  }
}

class _WallpaperPainter extends CustomPainter {
  final bool isDark;
  _WallpaperPainter({required this.isDark});

  static const _icons = [
    Icons.music_note_rounded,
    Icons.favorite_rounded,
    Icons.church_rounded,
    Icons.star_rounded,
    Icons.headphones_rounded,
    Icons.queue_music_rounded,
    Icons.mic_none_rounded,
    Icons.auto_awesome_rounded,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    // Base fill.
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = isDark ? _Wa.bgDark : _Wa.bgLight,
    );

    final doodle = (isDark ? Colors.white : Colors.black)
        .withOpacity(isDark ? 0.03 : 0.035);

    const step = 76.0;
    const iconSize = 30.0;
    int n = 0;
    for (double y = 8; y < size.height + step; y += step) {
      // Offset alternating rows for a more organic look.
      final rowOffset = ((y ~/ step) % 2 == 0) ? 0.0 : step / 2;
      for (double x = 8; x < size.width + step; x += step) {
        final icon = _icons[n % _icons.length];
        // Deterministic small rotation per cell.
        final angle = ((n % 5) - 2) * 0.18;
        _paintIcon(
          canvas,
          icon,
          Offset(x + rowOffset, y),
          iconSize,
          doodle,
          angle,
        );
        n++;
      }
    }
  }

  void _paintIcon(Canvas canvas, IconData icon, Offset pos, double size,
      Color color, double angle) {
    final tp = TextPainter(textDirection: TextDirection.ltr);
    tp.text = TextSpan(
      text: String.fromCharCode(icon.codePoint),
      style: TextStyle(
        fontSize: size,
        fontFamily: icon.fontFamily,
        package: icon.fontPackage,
        color: color,
      ),
    );
    tp.layout();
    canvas.save();
    canvas.translate(pos.dx, pos.dy);
    canvas.rotate(angle);
    tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _WallpaperPainter old) =>
      old.isDark != isDark;
}
