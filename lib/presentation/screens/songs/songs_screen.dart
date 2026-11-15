import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/songs_provider.dart';
import '../../widgets/common/error_banner.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../data/models/song_model.dart';
import 'song_detail_screen.dart';
import 'add_song_screen.dart';
import '../../widgets/common/glass.dart';

class SongsScreen extends StatefulWidget {
  const SongsScreen({super.key});

  @override
  State<SongsScreen> createState() => _SongsScreenState();
}

class _SongsScreenState extends State<SongsScreen>
    with SingleTickerProviderStateMixin {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final songsProvider = context.watch<SongsProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Favorites are kept in sync by MainScreen (reactively, outside build),
    // so there is no per-frame work here anymore.

    // Body extends behind the frosted app bar so the list blurs underneath it.
    final topInset =
        MediaQuery.of(context).padding.top + kToolbarHeight + 120;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
            child: Container(
              color: isDark
                  ? const Color(0x8C141019)
                  : Colors.white.withOpacity(0.55),
            ),
          ),
        ),
        title: const Text(AppStrings.songs),
        actions: [
          if (auth.isAdmin)
            IconButton(
              icon: const Icon(Icons.add_rounded),
              onPressed: () {
                Navigator.push(
                  context,
                  GlassPageRoute(builder: (_) => const AddSongScreen()),
                );
              },
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(120),
          child: Column(
            children: [
              // Search bar
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (v) => songsProvider.search(v),
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 14,
                    color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                  ),
                  decoration: InputDecoration(
                    hintText: AppStrings.searchSongs,
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    suffixIcon: _searchCtrl.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 18),
                            onPressed: () {
                              _searchCtrl.clear();
                              songsProvider.search('');
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: isDark ? Colors.grey.shade800 : Colors.grey.shade100,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              // Filter tabs
              SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    _FilterChip(
                      label: AppStrings.allSongs,
                      isSelected: songsProvider.filter == SongsFilter.all,
                      onTap: () => songsProvider.setFilter(SongsFilter.all),
                      icon: Icons.library_music_rounded,
                    ),
                    const SizedBox(width: 8),
                    _FilterChip(
                      label: AppStrings.favorites,
                      isSelected: songsProvider.filter == SongsFilter.favorites,
                      onTap: () => songsProvider.setFilter(SongsFilter.favorites),
                      icon: Icons.favorite_rounded,
                    ),
                    const SizedBox(width: 8),
                    _FilterChip(
                      label: AppStrings.offline,
                      isSelected: songsProvider.filter == SongsFilter.offline,
                      onTap: () => songsProvider.setFilter(SongsFilter.offline),
                      icon: Icons.download_done_rounded,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
      body: _buildBody(songsProvider, isDark, topInset),
    );
  }

  Widget _buildBody(SongsProvider songs, bool isDark, double topInset) {
    // A lista que não carregou dizia apenas "nenhuma música", o que a pessoa
    // lê como repertório vazio e não como falha.
    if (songs.error != null) {
      return Column(
        children: [
          ErrorBanner(message: songs.error!, onRetry: songs.retry),
          Expanded(child: _buildList(songs, isDark, topInset)),
        ],
      );
    }
    return _buildList(songs, isDark, topInset);
  }

  Widget _buildList(SongsProvider songs, bool isDark, double topInset) {
    if (songs.isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.blue),
      );
    }

    if (songs.songs.isEmpty) {
      return _ListaVazia(songs: songs, isDark: isDark);
    }

    return ListView.builder(
      padding: EdgeInsets.fromLTRB(16, topInset + 8, 16, 100),
      itemCount: songs.songs.length,
      itemBuilder: (ctx, i) {
        final song = songs.songs[i];
        return _SongListTile(song: song);
      },
    );
  }
}

/// A lista sem nada, dizendo POR QUE não há nada.
///
/// Antes era sempre a mesma frase, "Nenhuma música". Buscar por uma palavra
/// que não existe, abrir a aba de favoritas vazia e ter o repertório
/// realmente vazio produziam a mesma tela — e, depois de reinstalar o app,
/// essa frase foi lida como defeito. Cada caso agora diz o que é e o que
/// fazer a respeito.
class _ListaVazia extends StatelessWidget {
  final SongsProvider songs;
  final bool isDark;

  const _ListaVazia({required this.songs, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final ehLider = context.watch<AuthProvider>().isAdmin;

    late final IconData icone;
    late final String titulo;
    late final String detalhe;

    if (songs.searchQuery.isNotEmpty) {
      icone = Icons.search_off_rounded;
      titulo = 'Nada encontrado';
      detalhe = 'Nenhuma música com "${songs.searchQuery}" no nome ou no '
          'artista.';
    } else if (songs.filter == SongsFilter.favorites) {
      icone = Icons.favorite_border_rounded;
      titulo = 'Nenhuma favorita ainda';
      detalhe = 'Toque no coração de uma música para ela aparecer aqui.';
    } else if (songs.filter == SongsFilter.offline) {
      icone = Icons.cloud_off_rounded;
      titulo = 'Nenhuma música salva no aparelho';
      detalhe = 'Abra uma música e toque em "Salvar offline" para poder '
          'tocá-la sem internet.';
    } else {
      icone = Icons.music_off_rounded;
      titulo = 'O repertório está vazio';
      detalhe = ehLider
          ? 'Toque no + para cadastrar a primeira música.'
          : 'Ainda não há músicas cadastradas. Fale com o líder do '
              'ministério.';
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icone,
                size: 60,
                color: isDark ? Colors.grey.shade700 : Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(
              titulo,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: isDark
                    ? AppColors.textPrimaryDark
                    : AppColors.textPrimaryLight,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              detalhe,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 14,
                height: 1.5,
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondaryLight,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final IconData icon;

  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.blue : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppColors.blue : Colors.grey.shade300,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isSelected ? Colors.white : AppColors.textSecondaryLight,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: isSelected ? Colors.white : AppColors.textSecondaryLight,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SongListTile extends StatelessWidget {
  final SongModel song;
  const _SongListTile({required this.song});

  @override
  Widget build(BuildContext context) {
    // Each tile only rebuilds when ITS own favorite/offline status changes,
    // instead of rebuilding the whole list on any provider update.
    final isFav =
        context.select<AuthProvider, bool>((a) => a.isFavorite(song.id));
    final isOffline =
        context.select<SongsProvider, bool>((s) => s.isOffline(song.id));
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
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
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isDark ? Colors.grey.shade800 : Colors.grey.shade100,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  song.name.isNotEmpty ? song.name[0].toUpperCase() : '♪',
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
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
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
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
            const SizedBox(width: 8),
            // Key badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                song.originalKey,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.blue,
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Icons
            Column(
              children: [
                if (isFav)
                  const Icon(Icons.favorite_rounded,
                      size: 16, color: AppColors.red),
                if (isOffline)
                  const Icon(Icons.download_done_rounded,
                      size: 16, color: AppColors.success),
              ],
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right_rounded,
                color: AppColors.textSecondaryLight, size: 20),
          ],
        ),
      ),
    );
  }
}
