import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../providers/auth_provider.dart';
import '../../providers/scale_provider.dart';
import '../../providers/songs_provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../data/models/scale_model.dart';
import '../scale/scale_detail_screen.dart';
import '../songs/song_detail_screen.dart';

class HomeScreen extends StatefulWidget {
  /// Switches the bottom-nav tab (0=Início, 1=Músicas, 2=Escala, 3=Chat).
  final void Function(int index)? onNavigateTab;

  const HomeScreen({super.key, this.onNavigateTab});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late int _verseIndex;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _verseIndex = (now.day + now.month) % AppStrings.verses.length;
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final scale = context.watch<ScaleProvider>();
    final songs = context.watch<SongsProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final nextScale = scale.nextScale;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // App Bar
          SliverAppBar(
            expandedHeight: 120,
            floating: false,
            pinned: true,
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            flexibleSpace: Stack(
              fit: StackFit.expand,
              children: [
                // Real frosted blur of the content scrolling behind the header.
                ClipRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
                    child: Container(
                      color: isDark
                          ? const Color(0x8C141019)
                          : Colors.white.withOpacity(0.55),
                    ),
                  ),
                ),
                FlexibleSpaceBar(
                  titlePadding: const EdgeInsets.only(left: 20, bottom: 16),
                  title: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Olá, ${auth.user?.name.split(' ').first ?? 'Levita'}! 👋',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? AppColors.textPrimaryDark
                              : AppColors.textPrimaryLight,
                        ),
                      ),
                      Text(
                        DateFormat('EEEE, d \'de\' MMMM', 'pt_BR')
                            .format(DateTime.now()),
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 11,
                          color: AppColors.textSecondaryLight,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: CircleAvatar(
                  radius: 20,
                  backgroundColor: AppColors.blue.withOpacity(0.15),
                  child: Text(
                    (auth.user?.name.isNotEmpty == true)
                        ? auth.user!.name[0].toUpperCase()
                        : 'L',
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w700,
                      color: AppColors.blue,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ],
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Primeira coisa da tela: a pergunta que o ministério mais
                  // faz. O modelo já sabia responder (isUserInScale,
                  // hasUserConfirmed) e nada chamava esses métodos.
                  _MyNextCallCard(scale: nextScale),

                  // Verse of the Day Card
                  _VerseCard(verse: AppStrings.verses[_verseIndex]),
                  const SizedBox(height: 20),

                  // Next Service Card
                  GestureDetector(
                    onTap: nextScale == null
                        ? null
                        : () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    ScaleDetailScreen(scale: nextScale),
                              ),
                            ),
                    child: _NextServiceCard(scale: nextScale, songs: songs),
                  ),
                  const SizedBox(height: 20),

                  // Quick Actions
                  _QuickActionsSection(onNavigateTab: widget.onNavigateTab),
                  const SizedBox(height: 20),

                  // Suggested repertoire
                  _SuggestionSection(songs: songs),
                  const SizedBox(height: 100),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VerseCard extends StatelessWidget {
  final String verse;
  const _VerseCard({required this.verse});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.blue.withOpacity(0.3),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  '✨ Versículo do Dia',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: verse));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Versículo copiado!'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.share_outlined,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            verse,
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 14,
              color: Colors.white,
              height: 1.6,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}

class _NextServiceCard extends StatelessWidget {
  final ScaleModel? scale;
  final SongsProvider songs;

  const _NextServiceCard({this.scale, required this.songs});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? AppColors.cardDark : AppColors.cardLight,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? Colors.grey.shade800 : Colors.grey.shade100,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.yellow.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.church_rounded, color: AppColors.yellow, size: 22),
              ),
              const SizedBox(width: 12),
              Text(
                AppStrings.nextService,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (scale == null)
            Text(
              AppStrings.noNextService,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 13,
                color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
              ),
            )
          else ...[
            // Date
            _InfoRow(
              icon: Icons.calendar_today_rounded,
              text: DateFormat("EEEE, d 'de' MMMM', às' HH:mm", 'pt_BR')
                  .format(scale!.date),
              color: AppColors.blue,
            ),
            const SizedBox(height: 8),
            // Service type
            _InfoRow(
              icon: Icons.church_rounded,
              text: scale!.serviceType,
              color: AppColors.red,
            ),
            if (scale!.songs.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Músicas (${scale!.songs.length})',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                ),
              ),
              const SizedBox(height: 6),
              ...scale!.songs.take(3).map((s) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        const Icon(Icons.music_note_rounded,
                            size: 14, color: AppColors.blue),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _songLabel(context, s),
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 12,
                              color: isDark
                                  ? AppColors.textPrimaryDark
                                  : AppColors.textPrimaryLight,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  )),
              if (scale!.songs.length > 3)
                Text(
                  '+ ${scale!.songs.length - 3} músicas',
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11,
                    color: AppColors.blue,
                  ),
                ),
            ],
            if (scale!.levitas.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Levitas (${scale!.levitas.length})',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: scale!.levitas.map((l) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: l.confirmed
                          ? AppColors.success.withOpacity(0.1)
                          : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: l.confirmed
                            ? AppColors.success.withOpacity(0.3)
                            : Colors.grey.shade300,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (l.confirmed)
                          const Icon(Icons.check_circle_rounded,
                              size: 12, color: AppColors.success),
                        if (l.confirmed) const SizedBox(width: 4),
                        Text(
                          l.userName,
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: l.confirmed
                                ? AppColors.success
                                : AppColors.textSecondaryLight,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const _InfoRow({required this.icon, required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 13,
              color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
            ),
          ),
        ),
      ],
    );
  }
}

class _QuickActionsSection extends StatelessWidget {
  final void Function(int index)? onNavigateTab;
  const _QuickActionsSection({this.onNavigateTab});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppStrings.quickActions,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _QuickActionButton(
                icon: Icons.search_rounded,
                label: 'Buscar\nMúsica',
                color: AppColors.blue,
                onTap: () => onNavigateTab?.call(1),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _QuickActionButton(
                icon: Icons.calendar_month_rounded,
                label: 'Ver\nEscala',
                color: AppColors.red,
                onTap: () => onNavigateTab?.call(2),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _QuickActionButton(
                icon: Icons.chat_bubble_rounded,
                label: 'Chat do\nMinistério',
                color: AppColors.yellow,
                onTap: () => onNavigateTab?.call(3),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _QuickActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SuggestionSection extends StatelessWidget {
  final SongsProvider songs;
  const _SuggestionSection({required this.songs});

  @override
  Widget build(BuildContext context) {
    final suggested = songs.suggestRepertoire(count: 4);
    if (suggested.isEmpty) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.auto_awesome_rounded,
                color: AppColors.yellow, size: 20),
            const SizedBox(width: 8),
            Text(
              'Sugestão de Repertório',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...suggested.map(
          (song) => GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SongDetailScreen(song: song),
                ),
              );
            },
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isDark ? AppColors.cardDark : AppColors.cardLight,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark ? Colors.grey.shade800 : Colors.grey.shade100,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.music_note_rounded,
                        color: AppColors.blue, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          song.name,
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? AppColors.textPrimaryDark
                                : AppColors.textPrimaryLight,
                          ),
                        ),
                        Text(
                          song.artist,
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 12,
                            color: AppColors.textSecondaryLight,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      song.originalKey,
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.blue,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.chevron_right_rounded,
                      color: AppColors.textSecondaryLight, size: 20),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Label for a song referenced by a service: "Nome • Artista", with the artist
/// dropped when unknown. Read from the repertoire, never from a stored copy.
String _songLabel(BuildContext context, ScaleSong ref) {
  final songs = context.read<SongsProvider>();
  final artist = songs.artistOf(ref);
  final name = songs.nameOf(ref);
  return artist.isEmpty ? name : '$name • $artist';
}

/// "Você toca domingo às 9h" — the first thing on the screen when this person
/// is scheduled, with the confirm button right there.
///
/// The information existed: [ScaleModel.isUserInScale] and
/// [ScaleModel.hasUserConfirmed] were written and never called from this
/// screen, so somebody only found out they were scheduled by opening the
/// Escala tab and guessing the day. Nothing is shown when they are not
/// scheduled: an empty promise would be worse than silence.
class _MyNextCallCard extends StatefulWidget {
  final ScaleModel? scale;
  const _MyNextCallCard({this.scale});

  @override
  State<_MyNextCallCard> createState() => _MyNextCallCardState();
}

class _MyNextCallCardState extends State<_MyNextCallCard> {
  bool _saving = false;

  Future<void> _confirm(String userId, bool confirmed) async {
    setState(() => _saving = true);
    final error = await context
        .read<ScaleProvider>()
        .confirmPresence(widget.scale!.id, userId, confirmed);

    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error ??
            (confirmed ? 'Presença confirmada!' : 'Presença cancelada')),
        backgroundColor: error == null ? AppColors.success : AppColors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scale = widget.scale;
    final user = context.watch<AuthProvider>().user;
    if (scale == null || user == null || !scale.isUserInScale(user.id)) {
      return const SizedBox.shrink();
    }

    // Reads from the live list so the card follows a confirmation given on the
    // service screen.
    final live = context.select<ScaleProvider, ScaleModel?>((p) {
      for (final s in p.scales) {
        if (s.id == scale.id) return s;
      }
      return null;
    }) ?? scale;

    final confirmed = live.hasUserConfirmed(user.id);
    final quando =
        DateFormat("EEEE', às' HH:mm", 'pt_BR').format(live.date);
    final faltam = _faltam(live.date);

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: confirmed
                ? [const Color(0xFF13694F), const Color(0xFF1B8A68)]
                : [const Color(0xFF8E0000), const Color(0xFFB3261E)],
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  confirmed
                      ? Icons.check_circle_rounded
                      : Icons.campaign_rounded,
                  color: Colors.white,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Você toca $quando',
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      height: 1.25,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${live.serviceType}$faltam',
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12.5,
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: 14),
            if (_saving)
              const SizedBox(
                height: 36,
                child: Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  ),
                ),
              )
            else if (confirmed)
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Presença confirmada. Obrigado!',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => _confirm(user.id, false),
                    child: const Text(
                      'Não vou poder',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12,
                        color: Colors.white70,
                        decoration: TextDecoration.underline,
                        decorationColor: Colors.white70,
                      ),
                    ),
                  ),
                ],
              )
            else
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _confirm(user.id, true),
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: const Text(
                    'Confirmar presença',
                    style: TextStyle(
                        fontFamily: 'Poppins', fontWeight: FontWeight.w600),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF8E0000),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// " · é hoje", " · amanhã", " · em 3 dias".
  String _faltam(DateTime quando) {
    final hoje = DateTime.now();
    final dias = DateTime(quando.year, quando.month, quando.day)
        .difference(DateTime(hoje.year, hoje.month, hoje.day))
        .inDays;
    if (dias < 0) return '';
    if (dias == 0) return ' · é hoje';
    if (dias == 1) return ' · amanhã';
    return ' · em $dias dias';
  }
}
