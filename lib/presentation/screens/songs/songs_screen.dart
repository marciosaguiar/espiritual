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
import 'hino_por_numero_screen.dart';
import '../biblia/biblia_screen.dart';
import '../../widgets/songs/sugestoes_do_dia.dart';
import '../../widgets/songs/colar_cifra.dart';
import '../../widgets/songs/faixa_cifra_copiada.dart';
import '../../widgets/common/responsivo.dart';

class SongsScreen extends StatefulWidget {
  const SongsScreen({super.key});

  @override
  State<SongsScreen> createState() => _SongsScreenState();
}

/// As três bibliotecas da aba Músicas.
enum SecaoDeMusicas {
  /// O que a igreja canta: o repertório cadastrado.
  repertorio('Repertório'),

  /// Harpa Cristã e Cantor Cristão, pelo número.
  hinarios('Hinários'),

  /// Leitura offline, no aparelho.
  biblia('Bíblia');

  const SecaoDeMusicas(this.rotulo);
  final String rotulo;
}

class _SongsScreenState extends State<SongsScreen>
    with SingleTickerProviderStateMixin {
  final _searchCtrl = TextEditingController();

  /// Qual biblioteca está na tela.
  ///
  /// A aba Músicas virou a BIBLIOTECA do ministério: o repertório da igreja,
  /// os hinários e a Bíblia. Antes, o hino pelo número era um atalho no
  /// Início e a Bíblia era uma linha no Perfil — dois lugares que ninguém
  /// procuraria para achar algo para ler.
  SecaoDeMusicas _secao = SecaoDeMusicas.repertorio;

  @override
  void initState() {
    super.initState();
    // O repertório inteiro é lido aqui, quando alguém abre a aba — e não a cada
    // abertura do app (ver `SongsProvider.prazoDasMusicas`). A cópia do
    // aparelho aparece na hora; o servidor só é consultado se ela passou do
    // prazo.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<SongsProvider>().atualizarSeVelho();
    });
  }

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
    // Só o Repertório tem busca e filtros; nas outras seções a barra é só o
    // seletor, e a altura acompanha — barra alta e vazia come a tela de quem
    // está lendo.
    // A ALTURA DA BARRA MORA NUM LUGAR SÓ.
    //
    // Ela morava em dois — o `preferredSize` fixo em 120 e este cálculo em
    // 168 — e os dois discordavam. Medido a 375 px: o título "Músicas"
    // aparecia CORTADO ao meio, porque o conteúdo é maior que o espaço
    // declarado e o Flutter desenha por cima do título.
    const alturaDoSeletor = 54.0;
    const alturaDaBusca = 56.0;
    const alturaDosFiltros = 44.0;
    final alturaDaBarra = _secao == SecaoDeMusicas.repertorio
        ? alturaDoSeletor + alturaDaBusca + alturaDosFiltros
        : alturaDoSeletor;
    final topInset =
        MediaQuery.of(context).padding.top + kToolbarHeight + alturaDaBarra;

    final lista = Scaffold(
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
          // O teclado de hinos saiu daqui: virou a seção "Hinários", ao lado
          // de "Repertório". Ícone de teclado numérico numa barra não diz a
          // ninguém que ali estão a Harpa e o Cantor Cristão.
          if (auth.isAdmin && _secao == SecaoDeMusicas.repertorio)
            IconButton(
              icon: const Icon(Icons.add_rounded),
              onPressed: () {
                abrirTela(context, (_) => const AddSongScreen());
              },
            ),
        ],
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(alturaDaBarra),
          child: Column(
            children: [
              _SeletorDeSecao(
                escolhida: _secao,
                isDark: isDark,
                onEscolher: (s) => setState(() => _secao = s),
              ),
              if (_secao == SecaoDeMusicas.repertorio) ...[
              // Search bar
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (v) => songsProvider.search(v),
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 14,
                    color: isDark
                        ? AppColors.textPrimaryDark
                        : AppColors.textPrimaryLight,
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
                    fillColor:
                        isDark ? Colors.grey.shade800 : Colors.grey.shade100,
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
                      onTap: () =>
                          songsProvider.setFilter(SongsFilter.favorites),
                      icon: Icons.favorite_rounded,
                    ),
                    const SizedBox(width: 8),
                    _FilterChip(
                      label: AppStrings.offline,
                      isSelected: songsProvider.filter == SongsFilter.offline,
                      onTap: () => songsProvider.setFilter(SongsFilter.offline),
                      icon: Icons.download_done_rounded,
                    ),
                    // Só o líder tira e devolve música, então só ele tem o
                    // que fazer aqui. Para o levita seria uma aba que nunca
                    // muda de estado.
                    if (context.watch<AuthProvider>().isAdmin) ...[
                      const SizedBox(width: 8),
                      _FilterChip(
                        // "Arquivadas" é palavra de escritório. A lista é
                        // das músicas que saíram do repertório, e é isso que
                        // o nome diz agora.
                        label: 'Fora do repertório',
                        isSelected:
                            songsProvider.filter == SongsFilter.arquivadas,
                        onTap: () =>
                            songsProvider.setFilter(SongsFilter.arquivadas),
                        icon: Icons.archive_outlined,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 8),
              ],
            ],
          ),
        ),
      ),
      body: switch (_secao) {
        SecaoDeMusicas.repertorio =>
          _buildBody(songsProvider, isDark, topInset),
        // O teclado e a Bíblia vêm sem barra própria (`embutida`): a aba já
        // tem a dela, e duas barras empilhadas com dois títulos parecem
        // defeito.
        SecaoDeMusicas.hinarios => Padding(
            padding: EdgeInsets.only(top: topInset),
            child: const HinoPorNumeroScreen(embutida: true),
          ),
        SecaoDeMusicas.biblia => Padding(
            padding: EdgeInsets.only(top: topInset),
            child: const BibliaScreen(embutida: true),
          ),
      },
    );

    // Tela larga: a lista fica à esquerda e a música (ou o hino, ou o
    // capítulo) abre à direita, sem o vai-e-volta de uma tela empilhando
    // sobre a outra. No celular `MestreDetalhe` devolve só a lista.
    return MestreDetalhe(
      mestre: lista,
      vazioIcone: switch (_secao) {
        SecaoDeMusicas.repertorio => Icons.queue_music_rounded,
        SecaoDeMusicas.hinarios => Icons.library_music_rounded,
        SecaoDeMusicas.biblia => Icons.menu_book_rounded,
      },
      vazioTitulo: switch (_secao) {
        SecaoDeMusicas.repertorio => 'Escolha uma música',
        SecaoDeMusicas.hinarios => 'Escolha um hino',
        SecaoDeMusicas.biblia => 'Escolha um capítulo',
      },
      vazioTexto: switch (_secao) {
        SecaoDeMusicas.repertorio =>
          'A letra, a cifra e o tom abrem aqui, ao lado da lista.',
        SecaoDeMusicas.hinarios =>
          'Digite o número ou toque num hino da lista: a letra abre aqui.',
        SecaoDeMusicas.biblia => 'O texto abre aqui, ao lado da lista de livros.',
      },
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
    return _comFaixa(songs, isDark, topInset);
  }

  /// A lista com a faixa da cifra copiada por cima, quando houver.
  ///
  /// A faixa fica aqui, e não no Início, porque é aqui que a pessoa estava
  /// quando tocou em "Buscar no Cifra Club" — e é aqui que ela volta.
  ///
  /// O `topInset` sai da lista e passa para a coluna: a lista desenha por
  /// baixo da barra de cima, e sem isso a faixa nasceria escondida atrás
  /// dela.
  Widget _comFaixa(SongsProvider songs, bool isDark, double topInset) {
    // As sugestões do dia aparecem só na lista INTEIRA: com busca ou filtro
    // na tela, a pessoa já sabe o que quer, e sugestão ali é estorvo.
    final naListaInteira = songs.searchQuery.trim().isEmpty &&
        songs.filter == SongsFilter.all;
    return Column(
      children: [
        SizedBox(height: topInset),
        const FaixaCifraCopiada(),
        Expanded(
          child: naListaInteira && songs.songs.isNotEmpty
              ? ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                  children: [
                    SugestoesDoDia(songs: songs),
                    // O título é o que separa a sugestão (que repete quatro
                    // músicas) da lista: sem ele, as duas se liam como uma só.
                    _TituloDaLista(total: songs.songs.length, isDark: isDark),
                    ...songs.songs.map((s) => _SongListTile(song: s)),
                  ],
                )
              : _buildList(songs, isDark, 0),
        ),
      ],
    );
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
    } else if (songs.filter == SongsFilter.arquivadas) {
      icone = Icons.archive_outlined;
      titulo = 'Nenhuma música fora do repertório';
      detalhe = 'As músicas que você tirar do repertório ficam guardadas '
          'aqui, e podem voltar quando quiser.';
    } else if (songs.filter == SongsFilter.offline) {
      icone = Icons.cloud_off_rounded;
      titulo = 'Nenhuma música salva no celular';
      detalhe = 'Abra uma música e toque em "Salvar no celular" para poder '
          'abri-la sem internet, no meio do culto.';
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
            // Música cadastrada por outra pessoa só chega na lista no próximo
            // prazo; quem acabou de ouvir "o líder cadastrou ontem" e não
            // acha precisa de um jeito de buscar agora — e a pessoa decide,
            // porque custa uma leitura por música.
            if (songs.searchQuery.trim().isNotEmpty) ...[
              const SizedBox(height: 18),
              OutlinedButton.icon(
                onPressed: () => songs.atualizarSeVelho(forcar: true),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Atualizar a lista de músicas'),
              ),
            ],
            // A busca que não achou nada é o melhor momento do app para
            // oferecer o Cifra Club: a pessoa acabou de digitar o nome da
            // música, e o que falta é justamente a cifra dela. O texto já
            // vai preenchido com o que ela digitou.
            if (songs.searchQuery.trim().isNotEmpty && ehLider) ...[
              const SizedBox(height: 18),
              OutlinedButton.icon(
                onPressed: () =>
                    abrirBuscaCifraClub(context, songs.searchQuery),
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: const Text('Buscar no Cifra Club'),
              ),
              const SizedBox(height: 6),
              Text(
                'Copie a cifra lá e volte: o app oferece colá-la.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12.5,
                  color: isDark
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondaryLight,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// "Devolver ao repertório", na linha de uma música arquivada.
///
/// Fica na própria lista de arquivadas em vez de dentro do detalhe: quem
/// chega aqui já sabe o que quer, e obrigar a abrir a música para desfazer
/// um engano é um passo a mais sem motivo.
class _BotaoDevolver extends StatefulWidget {
  final SongModel song;
  const _BotaoDevolver({required this.song});

  @override
  State<_BotaoDevolver> createState() => _BotaoDevolverState();
}

class _BotaoDevolverState extends State<_BotaoDevolver> {
  bool _salvando = false;

  Future<void> _devolver() async {
    setState(() => _salvando = true);
    final erro =
        await context.read<SongsProvider>().desarquivar(widget.song.id);
    if (!mounted) return;
    setState(() => _salvando = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(erro ?? '${widget.song.name} voltou ao repertório.'),
        backgroundColor: erro == null ? AppColors.success : AppColors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_salvando) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 12),
        child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2.2)),
      );
    }
    return OutlinedButton(
      onPressed: _devolver,
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.blue,
        side: BorderSide(color: AppColors.blue.withValues(alpha: 0.5)),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        visualDensity: VisualDensity.compact,
        textStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 12.5),
      ),
      child: const Text('Devolver ao repertório'),
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

/// "Todas as músicas (42)": diz onde a lista começa e quantas há.
class _TituloDaLista extends StatelessWidget {
  final int total;
  final bool isDark;
  const _TituloDaLista({required this.total, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 18, 2, 10),
      child: Text(
        'Todas as músicas ($total)',
        style: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: isDark
              ? AppColors.textSecondaryDark
              : AppColors.textSecondaryLight,
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

    return ComMao(
      onTap: () {
        abrirTela(context, (_) => SongDetailScreen(song: song));
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
            if (song.archived)
              _BotaoDevolver(song: song)
            else ...[
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
            ],
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right_rounded,
                color: AppColors.textSecondaryLight, size: 20),
          ],
        ),
      ),
    );
  }
}

/// Repertório · Hinários · Bíblia.
///
/// Três palavras, do mesmo tamanho, sempre visíveis. Um menu escondido aqui
/// faria a Bíblia e os hinários continuarem invisíveis — que era justamente
/// o problema de eles morarem num atalho no Início e numa linha no Perfil.
class _SeletorDeSecao extends StatelessWidget {
  final SecaoDeMusicas escolhida;
  final bool isDark;
  final ValueChanged<SecaoDeMusicas> onEscolher;

  const _SeletorDeSecao({
    required this.escolhida,
    required this.isDark,
    required this.onEscolher,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Row(
        children: SecaoDeMusicas.values.map((s) {
          final ativa = s == escolhida;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Material(
                color: ativa
                    ? AppColors.blue
                    : (isDark
                        ? Colors.white10
                        : Colors.black.withValues(alpha: 0.05)),
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => onEscolher(s),
                  child: Padding(
                    // 11 px de altura dá um alvo de ~40 px, que o polegar
                    // acerta sem olhar.
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    child: Text(
                      s.rotulo,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: ativa
                            ? Colors.white
                            : (isDark
                                ? AppColors.textPrimaryDark
                                : AppColors.textPrimaryLight),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
