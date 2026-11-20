import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../data/models/song_model.dart';
import '../../../data/services/local_storage_service.dart';
import '../../providers/songs_provider.dart';
import '../../screens/songs/song_detail_screen.dart';
import '../common/responsivo.dart';

/// "Sugestão de repertório": quatro músicas do dia.
///
/// Morava no Início, e não respondia a pergunta daquela tela — "o que eu
/// preciso fazer agora?". Veio para o Repertório, que é onde se procura
/// música, e aparece só na lista inteira: com busca ou filtro na tela, a
/// pessoa já sabe o que quer, e sugestão ali é estorvo.
///
/// A escolha é sorteada com a semente do DIA, então a lista não dança a cada
/// abertura do app.
///
/// POR QUE VIROU UMA FAIXA RECOLHIDA (rodada de 20/11/2026)
///
/// A sugestão eram quatro cartões grandes, iguais aos da lista de baixo — e
/// as mesmas quatro músicas estavam nos dois lugares, sem nada que dissesse
/// onde uma acabava e a outra começava. Quem procurava uma música lia
/// quatro linhas repetidas antes de chegar à lista, e quem tocava numa delas
/// não sabia se estava na lista ou na sugestão.
///
/// Agora a sugestão é uma faixa de uma linha, de outra cor, FECHADA de
/// partida: o Repertório serve primeiro a quem procura uma música, e a
/// sugestão é para quem quer ideias. Aberta, ela diz que as músicas também
/// estão na lista. **Não se tira a música da lista** por estar sugerida —
/// quem a procura pelo nome tem de achá-la onde sempre esteve.
class SugestoesDoDia extends StatefulWidget {
  final SongsProvider songs;
  const SugestoesDoDia({super.key, required this.songs});

  @override
  State<SugestoesDoDia> createState() => _SugestoesDoDiaState();
}

class _SugestoesDoDiaState extends State<SugestoesDoDia> {
  late bool _aberta = _lerEscolha();

  /// A escolha de abrir fica no aparelho, e ausente vale FECHADA. Se o
  /// armazenamento falhar, a faixa abre fechada: é o caso em que ela atrapalha
  /// menos.
  static bool _lerEscolha() {
    try {
      return LocalStorageService.sugestoesAbertas;
    } catch (_) {
      return false;
    }
  }

  void _alternar() {
    setState(() => _aberta = !_aberta);
    // Melhor esforço: lembrar da escolha não vale uma tela de erro.
    LocalStorageService.salvarSugestoesAbertas(_aberta).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final sugeridas = widget.songs.suggestRepertoire(count: 4);
    if (sugeridas.isEmpty) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final texto =
        isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.yellow.withValues(alpha: isDark ? 0.10 : 0.14),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.yellow.withValues(alpha: isDark ? 0.35 : 0.55),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ComMao(
            onTap: _alternar,
            child: Semantics(
              button: true,
              expanded: _aberta,
              label: 'Sugestão de repertório',
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    const Icon(Icons.auto_awesome_rounded,
                        color: AppColors.yellow, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Sugestão de repertório',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: texto,
                        ),
                      ),
                    ),
                    Text(
                      _aberta ? 'Esconder' : 'Ver ${sugeridas.length}',
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.blue,
                      ),
                    ),
                    Icon(
                      _aberta
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      color: AppColors.blue,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_aberta) ...[
            for (final song in sugeridas) _LinhaSugerida(song: song),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
              child: Text(
                'Escolhidas pelo dia. Todas elas também estão na lista '
                'abaixo.',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 11.5,
                  height: 1.4,
                  color: isDark
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondaryLight,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _LinhaSugerida extends StatelessWidget {
  final SongModel song;
  const _LinhaSugerida({required this.song});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ComMao(
      // `abrirTela`, e NUNCA `Navigator.push`: em tela larga a música tem de
      // abrir ao lado, no painel. Com o `push` ela cobria a janela inteira e
      // o painel ficava dizendo "Escolha uma música".
      onTap: () => abrirTela(context, (_) => SongDetailScreen(song: song)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        child: Row(
          children: [
            const Icon(Icons.music_note_rounded,
                color: AppColors.blue, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song.name,
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
                  if (song.artist.trim().isNotEmpty)
                    Text(
                      song.artist,
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
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.blue.withValues(alpha: 0.12),
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
          ],
        ),
      ),
    );
  }
}
