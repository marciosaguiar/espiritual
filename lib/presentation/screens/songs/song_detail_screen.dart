import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../providers/auth_provider.dart';
import '../../providers/songs_provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/utils/chord_transposer.dart';
import '../../../data/models/song_model.dart';

class SongDetailScreen extends StatefulWidget {
  final SongModel song;
  const SongDetailScreen({super.key, required this.song});

  @override
  State<SongDetailScreen> createState() => _SongDetailScreenState();
}

class _SongDetailScreenState extends State<SongDetailScreen> {
  bool _showChords = false;
  bool _isWorshipMode = false;
  int _semitones = 0;
  double _fontSize = 16.0;

  @override
  void initState() {
    super.initState();
    // Load user's saved tone for this song
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = context.read<AuthProvider>();
      final saved = auth.getSavedTone(widget.song.id);
      if (saved != 0) {
        setState(() => _semitones = saved);
      }
    });
  }

  Future<void> _openYoutube() async {
    if (widget.song.youtubeUrl == null) return;
    final uri = Uri.parse(widget.song.youtubeUrl!);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _saveTone() async {
    final auth = context.read<AuthProvider>();
    await auth.saveSongTone(widget.song.id, _semitones);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Tom ${ChordTransposer.getTransposeDisplay(_semitones)} salvo!',
          ),
          backgroundColor: AppColors.success,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _toggleOffline() async {
    final songs = context.read<SongsProvider>();
    await songs.toggleOffline(widget.song);
    if (mounted) {
      final isNowOffline = songs.isOffline(widget.song.id);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isNowOffline
              ? 'Música salva offline!'
              : 'Música removida do offline'),
          backgroundColor:
              isNowOffline ? AppColors.success : AppColors.textSecondaryLight,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  String get _displayText {
    if (_showChords && widget.song.chords.isNotEmpty) {
      return ChordTransposer.transposeText(widget.song.chords, _semitones);
    }
    return widget.song.lyrics;
  }

  String get _currentKey {
    return ChordTransposer.getKeyName(widget.song.originalKey, _semitones);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final songs = context.watch<SongsProvider>();
    final isFav = auth.isFavorite(widget.song.id);
    final isOffline = songs.isOffline(widget.song.id);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_isWorshipMode) {
      return _WorshipModeView(
        song: widget.song,
        displayText: _displayText,
        currentKey: _currentKey,
        showChords: _showChords,
        fontSize: _fontSize,
        onExit: () => setState(() => _isWorshipMode = false),
        onFontSizeChange: (v) => setState(() => _fontSize = v),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.song.name,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          // Favorite
          IconButton(
            icon: Icon(
              isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              color: isFav ? AppColors.red : null,
            ),
            onPressed: () => auth.toggleFavorite(widget.song.id),
          ),
          // Admin delete
          if (auth.isAdmin)
            PopupMenuButton<String>(
              onSelected: (v) async {
                if (v == 'delete') {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('Excluir Música'),
                      content: const Text('Deseja excluir esta música?'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Cancelar'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Excluir',
                              style: TextStyle(color: AppColors.red)),
                        ),
                      ],
                    ),
                  );
                  if (confirm == true && mounted) {
                    await songs.deleteSong(widget.song.id);
                    if (mounted) Navigator.pop(context);
                  }
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline, color: AppColors.red, size: 18),
                      SizedBox(width: 8),
                      Text('Excluir música',
                          style: TextStyle(color: AppColors.red)),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
      body: Column(
        children: [
          // Controls bar
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            color:
                isDark ? const Color(0x8C141019) : Colors.white.withOpacity(0.55),
            child: Column(
              children: [
                // Key and transpose — Wrap prevents overflow on small screens
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    // Key display
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        gradient: AppColors.primaryGradient,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Tom: $_currentKey',
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    // Transpose cluster kept together
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _TransposeButton(
                          label: '−',
                          onTap: () => setState(() => _semitones--),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Text(
                            ChordTransposer.getTransposeDisplay(_semitones),
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: isDark
                                  ? AppColors.textPrimaryDark
                                  : AppColors.textPrimaryLight,
                            ),
                          ),
                        ),
                        _TransposeButton(
                          label: '+',
                          onTap: () => setState(() => _semitones++),
                        ),
                      ],
                    ),
                    // Reset
                    if (_semitones != 0)
                      GestureDetector(
                        onTap: () => setState(() => _semitones = 0),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'Reset',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 11,
                              color: AppColors.textSecondaryLight,
                            ),
                          ),
                        ),
                      ),
                    // Save tone
                    if (_semitones != 0)
                      GestureDetector(
                        onTap: _saveTone,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppColors.blue.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.save_rounded,
                                  size: 14, color: AppColors.blue),
                              SizedBox(width: 4),
                              Text(
                                'Salvar',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 12,
                                  color: AppColors.blue,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                // Mode toggles — Wrap prevents overflow on small screens
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    // Chords toggle
                    _ToggleChip(
                      label: _showChords
                          ? AppStrings.hideChords
                          : AppStrings.showChords,
                      icon: _showChords
                          ? Icons.queue_music_rounded
                          : Icons.music_note_rounded,
                      isActive: _showChords,
                      onTap: () =>
                          setState(() => _showChords = !_showChords),
                    ),
                    // Worship mode
                    _ToggleChip(
                      label: 'Modo Culto',
                      icon: Icons.fullscreen_rounded,
                      isActive: false,
                      onTap: () => setState(() => _isWorshipMode = true),
                    ),
                    // Offline
                    _ToggleChip(
                      label: isOffline ? 'Remover offline' : 'Salvar offline',
                      icon: isOffline
                          ? Icons.download_done_rounded
                          : Icons.download_rounded,
                      isActive: isOffline,
                      onTap: _toggleOffline,
                    ),
                    if (widget.song.youtubeUrl != null)
                      _ToggleChip(
                        label: 'YouTube',
                        icon: Icons.play_circle_outline_rounded,
                        isActive: false,
                        activeColor: AppColors.red,
                        onTap: _openYoutube,
                      ),
                  ],
                ),
              ],
            ),
          ),
          Divider(
              height: 1,
              color: isDark ? Colors.grey.shade800 : Colors.grey.shade200),
          // Lyrics / Chords
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
              child: Text(
                _displayText.isNotEmpty
                    ? _displayText
                    : 'Nenhuma letra disponível',
                style: TextStyle(
                  fontFamily: _showChords ? 'Courier' : 'Poppins',
                  fontSize: 15,
                  height: 1.9,
                  color: isDark
                      ? AppColors.textPrimaryDark
                      : AppColors.textPrimaryLight,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TransposeButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _TransposeButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: AppColors.blue,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Text(
            label,
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

class _ToggleChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;
  final Color? activeColor;

  const _ToggleChip({
    required this.label,
    required this.icon,
    required this.isActive,
    required this.onTap,
    this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    final color = activeColor ?? AppColors.blue;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? color.withOpacity(0.1) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isActive ? color.withOpacity(0.3) : Colors.grey.shade200,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 14, color: isActive ? color : AppColors.textSecondaryLight),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: isActive ? color : AppColors.textSecondaryLight,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Worship Mode ─────────────────────────────────────────────────────────────

class _WorshipModeView extends StatelessWidget {
  final SongModel song;
  final String displayText;
  final String currentKey;
  final bool showChords;
  final double fontSize;
  final VoidCallback onExit;
  final ValueChanged<double> onFontSizeChange;

  const _WorshipModeView({
    required this.song,
    required this.displayText,
    required this.currentKey,
    required this.showChords,
    required this.fontSize,
    required this.onExit,
    required this.onFontSizeChange,
  });

  @override
  Widget build(BuildContext context) {
    // Force dark mode for worship
    return Theme(
      data: ThemeData.dark(),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: onExit,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white10,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.fullscreen_exit_rounded,
                            color: Colors.white70, size: 20),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            song.name,
                            style: const TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '${song.artist} • Tom: $currentKey',
                            style: const TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 11,
                              color: Colors.white54,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Font size controls
                    Row(
                      children: [
                        GestureDetector(
                          onTap: () => onFontSizeChange(
                              (fontSize - 2).clamp(12.0, 40.0)),
                          child: const Icon(Icons.text_decrease_rounded,
                              color: Colors.white70, size: 22),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Text(
                            '${fontSize.toInt()}',
                            style: const TextStyle(
                                color: Colors.white70,
                                fontFamily: 'Poppins',
                                fontSize: 13),
                          ),
                        ),
                        GestureDetector(
                          onTap: () => onFontSizeChange(
                              (fontSize + 2).clamp(12.0, 40.0)),
                          child: const Icon(Icons.text_increase_rounded,
                              color: Colors.white70, size: 22),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Divider(height: 1, color: Colors.white12),
              // Lyrics
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
                  child: Text(
                    displayText.isNotEmpty
                        ? displayText
                        : 'Nenhuma letra disponível',
                    style: TextStyle(
                      fontFamily: showChords ? 'Courier' : 'Poppins',
                      fontSize: fontSize,
                      height: 2.0,
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
