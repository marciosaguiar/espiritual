import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../data/models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/scale_provider.dart';
import '../../providers/songs_provider.dart';
import '../../screens/songs/song_detail_screen.dart';
import 'abrir_link.dart';
import 'glass.dart';

/// "Minhas próximas músicas": o que EU vou tocar nos próximos sete dias.
///
/// Para chegar à cifra do domingo, a pessoa saía do Início, ia na Escala,
/// abria o culto, achava a música na lista e tocava nela. Quatro telas para a
/// única coisa que ela abre o app para fazer.
///
/// **Não aparece para quem não está escalado.** Cartão vazio dizendo "nenhuma
/// música" ocupa o lugar de algo útil e ensina a passar o olho por cima.
class MinhasProximasMusicas extends StatelessWidget {
  const MinhasProximasMusicas({super.key});

  @override
  Widget build(BuildContext context) {
    final eu = context.watch<AuthProvider>().user;
    final cultos = context.watch<ScaleProvider>().scales;
    final songs = context.watch<SongsProvider>();
    if (eu == null) return const SizedBox.shrink();

    final minhas = ScaleProvider.minhasProximasMusicas(
      cultos: cultos,
      userId: eu.id,
      agora: DateTime.now(),
    );
    if (minhas.isEmpty) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.queue_music_rounded,
                  size: 18, color: AppColors.blue),
              const SizedBox(width: 8),
              Text(
                minhas.length == 1
                    ? 'Minha próxima música'
                    : 'Minhas próximas músicas',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: isDark
                      ? AppColors.textPrimaryDark
                      : AppColors.textPrimaryLight,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...minhas.map((m) => _Linha(minha: m, songs: songs, isDark: isDark)),
        ],
      ),
    );
  }
}

class _Linha extends StatelessWidget {
  final MinhaMusica minha;
  final SongsProvider songs;
  final bool isDark;

  const _Linha({
    required this.minha,
    required this.songs,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final musica = songs.getSongById(minha.ref.songId);
    final funcao = UserInstrumentExtension.fromString(minha.instrumento);
    // "domingo, 19h" — sem o ano e sem os minutos quando são zero, que é o
    // caso de quase todo culto.
    final data = minha.culto.date;
    final hora = data.minute == 0
        ? '${DateFormat('HH', 'pt_BR').format(data)}h'
        : DateFormat('HH:mm', 'pt_BR').format(data);
    final quando = '${DateFormat('EEEE', 'pt_BR').format(data)}, $hora';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: musica == null
            ? null
            : () => Navigator.push(
                  context,
                  GlassPageRoute(
                    builder: (_) => SongDetailScreen(
                      song: musica,
                      // A função DAQUELE culto, não a do perfil: é ela que
                      // decide se a música abre em cifra ou só com a letra.
                      funcaoNoCulto: funcao,
                    ),
                  ),
                ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: isDark ? AppColors.cardDark : AppColors.cardLight,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
            ),
          ),
          child: Row(
            children: [
              // O TOM DAQUELE CULTO, em destaque: é o primeiro dado que quem
              // vai tocar procura, e muda de culto para culto.
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.blue.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  songs.keyOf(minha.ref),
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.blue,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      songs.nameOf(minha.ref),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? AppColors.textPrimaryDark
                            : AppColors.textPrimaryLight,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      // Culto e função na mesma linha: "domingo, 19h · Baixo".
                      '$quando · ${funcao.label}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12,
                        color: AppColors.textSecondaryLight,
                      ),
                    ),
                  ],
                ),
              ),
              // O YouTube só aparece quando há link: botão que não faz nada é
              // pior que botão nenhum.
              if (musica != null && (musica.videoUrl ?? '').isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.play_circle_outline_rounded,
                      size: 24, color: AppColors.red),
                  tooltip: 'Ouvir no YouTube',
                  onPressed: () => abrirLink(context, musica.videoUrl),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
