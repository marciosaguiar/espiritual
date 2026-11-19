import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../providers/songs_provider.dart';
import '../../screens/songs/song_detail_screen.dart';
import '../common/glass.dart';

/// "Sugestão de repertório": quatro músicas do dia.
///
/// Morava no Início, e não respondia a pergunta daquela tela — "o que eu
/// preciso fazer agora?". Veio para o Repertório, que é onde se procura
/// música, e aparece só na lista inteira: com busca ou filtro na tela, a
/// pessoa já sabe o que quer, e sugestão ali é estorvo.
///
/// A escolha é sorteada com a semente do DIA, então a lista não dança a cada
/// abertura do app.
class SugestoesDoDia extends StatelessWidget {
  final SongsProvider songs;
  const SugestoesDoDia({required this.songs});

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
                GlassPageRoute(
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
                      color: AppColors.blue.withValues(alpha: 0.1),
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
                      color: AppColors.blue.withValues(alpha: 0.1),
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
