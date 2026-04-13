import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../providers/auth_provider.dart';
import '../../providers/scale_provider.dart';
import '../../providers/songs_provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/models/scale_model.dart';
import '../../../data/models/song_model.dart';
import '../../../data/models/user_model.dart';
import '../../../data/services/auth_service.dart';
import '../songs/song_detail_screen.dart';

class ScaleDetailScreen extends StatefulWidget {
  final ScaleModel scale;
  const ScaleDetailScreen({super.key, required this.scale});

  @override
  State<ScaleDetailScreen> createState() => _ScaleDetailScreenState();
}

class _ScaleDetailScreenState extends State<ScaleDetailScreen> {
  late ScaleModel _scale;
  final _observationsCtrl = TextEditingController();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _scale = widget.scale;
    _observationsCtrl.text = _scale.observations;
  }

  @override
  void dispose() {
    _observationsCtrl.dispose();
    super.dispose();
  }

  Future<void> _confirmPresence(AuthProvider auth) async {
    if (auth.user == null) return;
    final isConfirmed = _scale.hasUserConfirmed(auth.user!.id);
    final scale = context.read<ScaleProvider>();

    final success = await scale.confirmPresence(
      _scale.id,
      auth.user!.id,
      !isConfirmed,
    );

    if (success && mounted) {
      final updated = scale.scales.firstWhere((s) => s.id == _scale.id,
          orElse: () => _scale);
      setState(() => _scale = updated);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(!isConfirmed
              ? 'Presença confirmada!'
              : 'Presença cancelada'),
          backgroundColor:
              !isConfirmed ? AppColors.success : AppColors.textSecondaryLight,
        ),
      );
    }
  }

  Future<void> _saveObservations() async {
    setState(() => _isSaving = true);
    final scale = context.read<ScaleProvider>();
    final updated = _scale.copyWith(observations: _observationsCtrl.text);
    final success = await scale.updateScale(updated);
    if (mounted) {
      setState(() {
        _isSaving = false;
        if (success) _scale = updated;
      });
    }
  }

  Future<void> _showAddSongDialog() async {
    final songs = context.read<SongsProvider>();
    final allSongs = songs.allSongs;

    if (allSongs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nenhuma música cadastrada')),
      );
      return;
    }

    final List<SongModel>? selected = await showDialog<List<SongModel>>(
      context: context,
      builder: (ctx) {
        final selectedSongs = <String>{};
        for (final s in _scale.songs) {
          selectedSongs.add(s.songId);
        }
        return StatefulBuilder(builder: (ctx2, setDialog) {
          return AlertDialog(
            title: const Text('Adicionar Músicas',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 16)),
            content: SizedBox(
              width: double.maxFinite,
              height: 400,
              child: ListView.builder(
                itemCount: allSongs.length,
                itemBuilder: (_, i) {
                  final s = allSongs[i];
                  final checked = selectedSongs.contains(s.id);
                  return CheckboxListTile(
                    title: Text(s.name,
                        style: const TextStyle(
                            fontFamily: 'Poppins', fontSize: 13)),
                    subtitle: Text('${s.artist} • ${s.originalKey}',
                        style: const TextStyle(
                            fontFamily: 'Poppins', fontSize: 11)),
                    value: checked,
                    activeColor: AppColors.blue,
                    onChanged: (v) {
                      setDialog(() {
                        if (v == true) {
                          selectedSongs.add(s.id);
                        } else {
                          selectedSongs.remove(s.id);
                        }
                      });
                    },
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: () {
                  final result = allSongs
                      .where((s) => selectedSongs.contains(s.id))
                      .toList();
                  Navigator.pop(ctx, result);
                },
                style:
                    ElevatedButton.styleFrom(backgroundColor: AppColors.blue),
                child: const Text('Confirmar'),
              ),
            ],
          );
        });
      },
    );

    if (selected != null && mounted) {
      final scaleSongs = selected
          .map((s) => ScaleSong(
                songId: s.id,
                songName: s.name,
                artist: s.artist,
                key: s.originalKey,
              ))
          .toList();
      final updated = _scale.copyWith(songs: scaleSongs);
      final scaleProvider = context.read<ScaleProvider>();
      final success = await scaleProvider.updateScale(updated);
      if (success) {
        setState(() => _scale = updated);
      }
    }
  }

  Future<void> _showAddLevitaDialog() async {
    final List<UserModel> allUsers =
        await AuthService.getAllUsers().first;

    if (!mounted) return;

    final List<String>? selectedIds = await showDialog<List<String>>(
      context: context,
      builder: (ctx) {
        final currentIds = _scale.levitas.map((l) => l.userId).toSet();
        return StatefulBuilder(builder: (ctx2, setDialog) {
          return AlertDialog(
            title: const Text('Definir Levitas',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 16)),
            content: SizedBox(
              width: double.maxFinite,
              height: 400,
              child: ListView.builder(
                itemCount: allUsers.length,
                itemBuilder: (_, i) {
                  final u = allUsers[i];
                  final checked = currentIds.contains(u.id);
                  return CheckboxListTile(
                    leading: CircleAvatar(
                      radius: 16,
                      backgroundColor: AppColors.blue.withOpacity(0.15),
                      child: Text(
                        u.name[0].toUpperCase(),
                        style: const TextStyle(
                          color: AppColors.blue,
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    title: Text(u.name,
                        style: const TextStyle(
                            fontFamily: 'Poppins', fontSize: 13)),
                    subtitle: Text(
                        '${u.instrument.emoji} ${u.instrument.label}',
                        style: const TextStyle(
                            fontFamily: 'Poppins', fontSize: 11)),
                    value: checked,
                    activeColor: AppColors.blue,
                    onChanged: (v) {
                      setDialog(() {
                        if (v == true) {
                          currentIds.add(u.id);
                        } else {
                          currentIds.remove(u.id);
                        }
                      });
                    },
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, currentIds.toList()),
                style:
                    ElevatedButton.styleFrom(backgroundColor: AppColors.blue),
                child: const Text('Confirmar'),
              ),
            ],
          );
        });
      },
    );

    if (selectedIds != null && mounted) {
      final existingLevitas = Map<String, ScaleLevita>.fromEntries(
        _scale.levitas.map((l) => MapEntry(l.userId, l)),
      );

      final levitas = selectedIds.map((uid) {
        if (existingLevitas.containsKey(uid)) {
          return existingLevitas[uid]!;
        }
        final user = allUsers.firstWhere(
          (u) => u.id == uid,
          orElse: () => UserModel(
            id: uid,
            name: uid,
            passwordHash: '',
            createdAt: DateTime.now(),
          ),
        );
        return ScaleLevita(
          userId: user.id,
          userName: user.name,
          instrument: user.instrument.name,
        );
      }).toList();

      final updated = _scale.copyWith(levitas: levitas);
      final scaleProvider = context.read<ScaleProvider>();
      final success = await scaleProvider.updateScale(updated);
      if (success) {
        setState(() => _scale = updated);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isUserInScale =
        auth.user != null && _scale.isUserInScale(auth.user!.id);
    final isConfirmed =
        auth.user != null && _scale.hasUserConfirmed(auth.user!.id);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${_scale.serviceType} - ${DateFormat('dd/MM', 'pt_BR').format(_scale.date)}',
        ),
        actions: [
          if (auth.isAdmin)
            PopupMenuButton<String>(
              onSelected: (v) async {
                if (v == 'delete') {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('Excluir Culto'),
                      content: const Text('Deseja excluir este culto?'),
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
                    final scaleProvider = context.read<ScaleProvider>();
                    await scaleProvider.deleteScale(_scale.id);
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
                      Text('Excluir culto',
                          style: TextStyle(color: AppColors.red)),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Service info header
            _SectionHeader(
              title: DateFormat('EEEE, d \'de\' MMMM \'de\' yyyy', 'pt_BR')
                  .format(_scale.date),
              subtitle: _scale.serviceType,
              icon: Icons.church_rounded,
              color: AppColors.red,
            ),
            const SizedBox(height: 20),

            // Confirm presence button (if user is in scale)
            if (isUserInScale)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isConfirmed
                      ? AppColors.success.withOpacity(0.1)
                      : AppColors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isConfirmed
                        ? AppColors.success.withOpacity(0.3)
                        : AppColors.blue.withOpacity(0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      isConfirmed
                          ? Icons.check_circle_rounded
                          : Icons.help_outline_rounded,
                      color: isConfirmed ? AppColors.success : AppColors.blue,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        isConfirmed
                            ? 'Você confirmou presença!'
                            : 'Você está escalado. Confirmar presença?',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 13,
                          color: isConfirmed ? AppColors.success : AppColors.blue,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => _confirmPresence(auth),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: isConfirmed ? AppColors.success : AppColors.blue,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          isConfirmed ? 'Cancelar' : 'Confirmar',
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 20),

            // Songs section
            Row(
              children: [
                Text(
                  'Músicas (${_scale.songs.length})',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? AppColors.textPrimaryDark
                        : AppColors.textPrimaryLight,
                  ),
                ),
                const Spacer(),
                if (auth.isAdmin)
                  GestureDetector(
                    onTap: _showAddSongDialog,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppColors.blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.add_rounded,
                              size: 16, color: AppColors.blue),
                          SizedBox(width: 4),
                          Text(
                            'Adicionar',
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
            if (_scale.songs.isEmpty)
              _EmptyState(
                icon: Icons.music_off_rounded,
                text: 'Nenhuma música adicionada',
              )
            else
              ...List.generate(_scale.songs.length, (i) {
                final s = _scale.songs[i];
                return _SongRow(song: s, index: i + 1);
              }),

            const SizedBox(height: 20),

            // Levitas section
            Row(
              children: [
                Text(
                  'Levitas (${_scale.levitas.length})',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? AppColors.textPrimaryDark
                        : AppColors.textPrimaryLight,
                  ),
                ),
                const Spacer(),
                if (auth.isAdmin)
                  GestureDetector(
                    onTap: _showAddLevitaDialog,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppColors.red.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.person_add_alt_rounded,
                              size: 16, color: AppColors.red),
                          SizedBox(width: 4),
                          Text(
                            'Definir',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 12,
                              color: AppColors.red,
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
            if (_scale.levitas.isEmpty)
              _EmptyState(
                icon: Icons.people_outline_rounded,
                text: 'Nenhum levita definido',
              )
            else
              ...List.generate(_scale.levitas.length, (i) {
                final l = _scale.levitas[i];
                return _LevitaRow(levita: l);
              }),

            const SizedBox(height: 20),

            // Observations
            Text(
              'Observações',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: isDark
                    ? AppColors.textPrimaryDark
                    : AppColors.textPrimaryLight,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _observationsCtrl,
              maxLines: 4,
              readOnly: !auth.isAdmin,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 14,
                color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
              ),
              decoration: InputDecoration(
                hintText: 'Adicione observações sobre o culto...',
                hintStyle: const TextStyle(
                  fontFamily: 'Poppins',
                  color: AppColors.textSecondaryLight,
                ),
                filled: true,
                fillColor: isDark ? Colors.grey.shade900 : Colors.grey.shade50,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: isDark ? Colors.grey.shade700 : Colors.grey.shade200,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: isDark ? Colors.grey.shade700 : Colors.grey.shade200,
                  ),
                ),
              ),
            ),
            if (auth.isAdmin) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isSaving ? null : _saveObservations,
                  icon: _isSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.save_rounded, size: 18),
                  label: const Text('Salvar Observações'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.blue,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;

  const _SectionHeader({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: color, size: 24),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12,
                  color: color,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SongRow extends StatelessWidget {
  final ScaleSong song;
  final int index;

  const _SongRow({required this.song, required this.index});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
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
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: AppColors.blue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(
                '$index',
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.blue,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  song.songName,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                  ),
                ),
                Text(
                  song.artist,
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11,
                    color: AppColors.textSecondaryLight,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.blue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              song.key,
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.blue,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LevitaRow extends StatelessWidget {
  final ScaleLevita levita;
  const _LevitaRow({required this.levita});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.cardDark : AppColors.cardLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: levita.confirmed
              ? AppColors.success.withOpacity(0.3)
              : isDark
                  ? Colors.grey.shade800
                  : Colors.grey.shade100,
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: levita.confirmed
                ? AppColors.success.withOpacity(0.15)
                : AppColors.blue.withOpacity(0.15),
            child: Text(
              levita.userName[0].toUpperCase(),
              style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w700,
                color: levita.confirmed ? AppColors.success : AppColors.blue,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  levita.userName,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? AppColors.textPrimaryDark
                        : AppColors.textPrimaryLight,
                  ),
                ),
                Text(
                  levita.instrument,
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11,
                    color: AppColors.textSecondaryLight,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: levita.confirmed
                  ? AppColors.success.withOpacity(0.1)
                  : Colors.orange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  levita.confirmed
                      ? Icons.check_circle_rounded
                      : Icons.schedule_rounded,
                  size: 12,
                  color: levita.confirmed ? AppColors.success : Colors.orange,
                ),
                const SizedBox(width: 4),
                Text(
                  levita.confirmed ? 'Confirmado' : 'Pendente',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color:
                        levita.confirmed ? AppColors.success : Colors.orange,
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

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String text;

  const _EmptyState({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24),
      width: double.infinity,
      child: Column(
        children: [
          Icon(icon,
              size: 36,
              color: isDark ? Colors.grey.shade700 : Colors.grey.shade300),
          const SizedBox(height: 8),
          Text(
            text,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 13,
              color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
            ),
          ),
        ],
      ),
    );
  }
}
