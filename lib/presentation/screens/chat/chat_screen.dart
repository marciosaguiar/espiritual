import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../providers/auth_provider.dart';
import '../../providers/chat_provider.dart';
import '../../providers/songs_provider.dart';
import '../../providers/scale_provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../data/models/message_model.dart';
import '../../../data/models/song_model.dart';
import '../../../data/models/scale_model.dart';

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

  ChatProvider? _chat;
  int _lastMessageCount = 0;

  @override
  void initState() {
    super.initState();
    _chat = context.read<ChatProvider>();
    _lastMessageCount = _chat!.messages.length;
    // Scroll to the bottom only when a new message actually arrives,
    // instead of on every rebuild.
    _chat!.addListener(_onMessagesChanged);
  }

  void _onMessagesChanged() {
    final count = _chat?.messages.length ?? 0;
    if (count != _lastMessageCount) {
      _lastMessageCount = count;
      _scrollToBottom();
    }
  }

  @override
  void dispose() {
    _chat?.removeListener(_onMessagesChanged);
    _messageCtrl.dispose();
    _scrollCtrl.dispose();
    _songSearchCtrl.dispose();
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

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.groupChat),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 12),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.success.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: AppColors.success,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                const Text(
                  'Tempo real',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11,
                    color: AppColors.success,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Song search panel
          if (_showSongSearch)
            Container(
              color: isDark ? AppColors.cardDark : Colors.grey.shade50,
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        'Buscar música',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: () {
                          setState(() => _showSongSearch = false);
                          _songSearchCtrl.clear();
                        },
                        child: const Icon(Icons.close_rounded, size: 18),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    auth.isAdmin
                        ? 'Enviar no chat ou adicionar à escala'
                        : 'Encontre e compartilhe uma música no chat',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 11,
                      color: isDark
                          ? AppColors.textSecondaryDark
                          : AppColors.textSecondaryLight,
                    ),
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
                      fillColor: isDark ? Colors.grey.shade800 : Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 120,
                    child: ListView(
                      children: songs.allSongs
                          .where((s) {
                            final q = _songSearchCtrl.text.toLowerCase();
                            if (q.isEmpty) return true;
                            return s.name.toLowerCase().contains(q) ||
                                s.artist.toLowerCase().contains(q);
                          })
                          .map((song) => ListTile(
                                dense: true,
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
                                    // Share in chat
                                    Tooltip(
                                      message: 'Enviar no chat',
                                      child: GestureDetector(
                                        onTap: () {
                                          _sendMessage(
                                            linkedSongId: song.id,
                                            linkedSongName: song.name,
                                          );
                                        },
                                        child: const Icon(Icons.send_rounded,
                                            size: 18, color: AppColors.blue),
                                      ),
                                    ),
                                    // Add to scale (admins only)
                                    if (auth.isAdmin) ...[
                                      const SizedBox(width: 12),
                                      Tooltip(
                                        message: 'Adicionar à escala',
                                        child: GestureDetector(
                                          onTap: () {
                                            _showInsertSongInScaleDialog(song);
                                          },
                                          child: const Icon(
                                              Icons.calendar_month_rounded,
                                              size: 18,
                                              color: AppColors.red),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ))
                          .toList(),
                    ),
                  ),
                ],
              ),
            ),

          // Messages list
          Expanded(
            child: chat.isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.blue))
                : chat.messages.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.chat_bubble_outline_rounded,
                                size: 56,
                                color: isDark
                                    ? Colors.grey.shade700
                                    : Colors.grey.shade300),
                            const SizedBox(height: 12),
                            Text(
                              AppStrings.noMessages,
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                color: isDark
                                    ? AppColors.textSecondaryDark
                                    : AppColors.textSecondaryLight,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollCtrl,
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                        itemCount: chat.messages.length,
                        itemBuilder: (ctx, i) {
                          final msg = chat.messages[i];
                          final isMe = msg.userId == auth.user?.id;
                          final showDate = i == 0 ||
                              !_isSameDay(
                                  chat.messages[i - 1].timestamp,
                                  msg.timestamp);
                          return Column(
                            children: [
                              if (showDate) _DateDivider(date: msg.timestamp),
                              _MessageBubble(
                                message: msg,
                                isMe: isMe,
                                onSongTap: msg.linkedSongId != null
                                    ? () {
                                        final song = songs.getSongById(
                                            msg.linkedSongId!);
                                        if (song != null &&
                                            auth.isAdmin) {
                                          _showInsertSongInScaleDialog(song);
                                        }
                                      }
                                    : null,
                              ),
                            ],
                          );
                        },
                      ),
          ),

          // Input bar
          Container(
            padding: EdgeInsets.fromLTRB(
                12, 8, 12, MediaQuery.of(context).padding.bottom + 8),
            decoration: BoxDecoration(
              color: isDark ? AppColors.surfaceDark : AppColors.white,
              border: Border(
                top: BorderSide(
                  color:
                      isDark ? Colors.grey.shade800 : Colors.grey.shade200,
                ),
              ),
            ),
            child: Row(
              children: [
                // Song search toggle
                Tooltip(
                  message: 'Buscar e compartilhar música',
                  child: GestureDetector(
                    onTap: () {
                      setState(() => _showSongSearch = !_showSongSearch);
                    },
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: _showSongSearch
                            ? AppColors.blue.withOpacity(0.15)
                            : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.music_note_rounded,
                        size: 20,
                        color: _showSongSearch
                            ? AppColors.blue
                            : AppColors.textSecondaryLight,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Text input
                Expanded(
                  child: TextField(
                    controller: _messageCtrl,
                    maxLines: 4,
                    minLines: 1,
                    textCapitalization: TextCapitalization.sentences,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 14,
                      color: isDark
                          ? AppColors.textPrimaryDark
                          : AppColors.textPrimaryLight,
                    ),
                    decoration: InputDecoration(
                      hintText: AppStrings.typeMessage,
                      hintStyle: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 13,
                        color: isDark
                            ? Colors.grey.shade600
                            : Colors.grey.shade400,
                      ),
                      filled: true,
                      fillColor: isDark
                          ? Colors.grey.shade900
                          : Colors.grey.shade100,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                // Send button
                GestureDetector(
                  onTap: _sendMessage,
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: const BoxDecoration(
                      gradient: AppColors.primaryGradient,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.send_rounded,
                        size: 18, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}

class _DateDivider extends StatelessWidget {
  final DateTime date;
  const _DateDivider({required this.date});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    String label;
    if (date.year == now.year &&
        date.month == now.month &&
        date.day == now.day) {
      label = 'Hoje';
    } else if (date.year == now.year &&
        date.month == now.month &&
        date.day == now.day - 1) {
      label = 'Ontem';
    } else {
      label = DateFormat('dd/MM/yyyy').format(date);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(child: Divider(color: Colors.grey.shade300, height: 1)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              label,
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 11,
                color: AppColors.textSecondaryLight,
              ),
            ),
          ),
          Expanded(child: Divider(color: Colors.grey.shade300, height: 1)),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final MessageModel message;
  final bool isMe;
  final VoidCallback? onSongTap;

  const _MessageBubble({
    required this.message,
    required this.isMe,
    this.onSongTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            CircleAvatar(
              radius: 16,
              backgroundColor: AppColors.blue.withOpacity(0.15),
              child: Text(
                message.userName[0].toUpperCase(),
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.blue,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment:
                  isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (!isMe)
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 3),
                    child: Text(
                      message.userName,
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondaryLight,
                      ),
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.70,
                  ),
                  decoration: BoxDecoration(
                    gradient: isMe ? AppColors.primaryGradient : null,
                    color: isMe
                        ? null
                        : isDark
                            ? AppColors.cardDark
                            : Colors.grey.shade100,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: Radius.circular(isMe ? 16 : 4),
                      bottomRight: Radius.circular(isMe ? 4 : 16),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Linked song card
                      if (message.hasSong && message.linkedSongName != null)
                        GestureDetector(
                          onTap: onSongTap,
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(
                                  isMe ? 0.2 : 0.8),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isMe
                                    ? Colors.white.withOpacity(0.3)
                                    : Colors.grey.shade300,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.music_note_rounded,
                                  size: 16,
                                  color: isMe ? Colors.white : AppColors.blue,
                                ),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    message.linkedSongName!,
                                    style: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: isMe
                                          ? Colors.white
                                          : AppColors.blue,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (onSongTap != null)
                                  Icon(
                                    Icons.add_rounded,
                                    size: 14,
                                    color: isMe ? Colors.white70 : AppColors.blue,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      Text(
                        message.text,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 13,
                          color: isMe
                              ? Colors.white
                              : isDark
                                  ? AppColors.textPrimaryDark
                                  : AppColors.textPrimaryLight,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        DateFormat('HH:mm').format(message.timestamp),
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 10,
                          color: isMe ? Colors.white60 : AppColors.textSecondaryLight,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
