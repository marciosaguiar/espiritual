import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../providers/auth_provider.dart';
import '../../providers/songs_provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/utils/chord_transposer.dart';
import '../../../core/utils/cifra_colada.dart';
import '../../widgets/common/abrir_link.dart';
import '../../widgets/common/glass.dart';
import '../../widgets/songs/colar_cifra.dart';
import 'editar_musica_screen.dart';
import '../../../data/models/arrangement_model.dart';
import '../../../data/services/firestore_service.dart';
import '../../../data/models/song_model.dart';
import '../../../data/models/user_model.dart';

class SongDetailScreen extends StatefulWidget {
  final SongModel song;

  /// A função em que a pessoa vai NESTE culto, quando a música foi aberta de
  /// dentro de um culto.
  ///
  /// Quem canta num domingo e faz baixo no outro precisa ver coisas
  /// diferentes, e o cadastro não sabe qual é hoje — a escala sabe. Nulo
  /// significa "aberta pelo repertório": aí vale o que a pessoa escolheu no
  /// perfil, como antes.
  final UserInstrument? funcaoNoCulto;

  const SongDetailScreen({
    super.key,
    required this.song,
    this.funcaoNoCulto,
  });

  @override
  State<SongDetailScreen> createState() => _SongDetailScreenState();
}

class _SongDetailScreenState extends State<SongDetailScreen> {
  bool _showChords = false;

  /// Quem canta, para esta abertura da tela.
  ///
  /// A função do culto manda; sem culto, vale a escolha do perfil. A pessoa
  /// pode trocar na hora pelo botão "Letra / Cifra" — a troca vale só
  /// enquanto a tela está aberta, e não mexe no perfil.
  bool _cantaAgora(BuildContext context) {
    final f = widget.funcaoNoCulto;
    if (f != null) return UserModel.leituraDaFuncao(f) == ModoLeitura.canto;
    return context.read<AuthProvider>().user?.canta ?? false;
  }
  bool _isWorshipMode = false;
  int _semitones = 0;
  double _fontSize = 16.0;

  /// How this church plays the song. Fetched when the screen opens — it is a
  /// subcollection of the song, so the chart is not downloaded with the song
  /// list.
  ArrangementModel? _arrangement;
  bool _loadingArrangement = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final auth = context.read<AuthProvider>();
      final saved = auth.getSavedTone(widget.song.id);
      if (saved != 0) setState(() => _semitones = saved);
      // Quem canta lê de longe: letra grande também no Modo Culto.
      if (_cantaAgora(context)) setState(() => _fontSize = 26);
      _loadArrangement();
    });
  }

  Future<void> _loadArrangement() async {
    final found = await FirestoreService.getArrangement(widget.song.id);
    if (!mounted) return;
    final canta = _cantaAgora(context);
    setState(() {
      _arrangement = found;
      _loadingArrangement = false;
      // Quem toca abre direto na cifra, no tom dele; quem canta, na letra.
      _showChords = !canta && (found?.hasChords ?? false);
    });
  }

  /// Quem cadastrou a música pode corrigir o cadastro dela.
  bool _souQuemCadastrou(String? meuId) =>
      meuId != null && meuId.isNotEmpty && widget.song.addedBy == meuId;

  /// Corrigir nome, artista, tom, BPM, link do YouTube e observações.
  ///
  /// O BPM vai para o ARRANJO, e não para a música: é de como esta igreja
  /// toca. Se ainda não houver arranjo, um é criado só com o BPM — sem cifra,
  /// que é o que já acontece quando o líder define o tom da igreja antes de
  /// ter a cifra em mãos.
  Future<void> _editar() async {
    final songs = context.read<SongsProvider>();
    final auth = context.read<AuthProvider>();

    final r = await Navigator.push<EdicaoDeMusica>(
      context,
      GlassPageRoute(
        builder: (_) => EditarMusicaScreen(
          musica: widget.song,
          arranjo: _arrangement,
        ),
      ),
    );
    if (r == null || !mounted) return;

    String? erro = await songs.updateSong(r.musica);

    final bpmMudou = r.bpm != (_arrangement?.bpm ?? 0);
    if (erro == null && bpmMudou) {
      final base = _arrangement ??
          FirestoreService.createArrangementModel(
            songId: widget.song.id,
            churchKey: r.musica.originalKey,
            approvedBy: auth.user?.id,
          );
      final salvo = await FirestoreService.saveArrangement(
          base.copyWith(bpm: r.bpm, updatedAt: DateTime.now()));
      if (salvo.success) {
        if (mounted) setState(() => _arrangement = salvo.arrangement);
      } else {
        erro = salvo.error;
      }
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(erro ?? 'Música atualizada.'),
        backgroundColor: erro == null ? AppColors.success : AppColors.red,
      ),
    );
  }

  /// "A cifra está em D, a música está em G. Trocar?"
  ///
  /// Diz os dois tons no texto, porque "Trocar o tom?" sem os valores não dá
  /// à pessoa como decidir.
  Future<bool> _confirmarTroca(String atual, String doSite) async {
    final trocar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tom diferente'),
        content: Text(
          'A cifra que você colou está em $doSite, e esta música está '
          'cadastrada em $atual.\n\nQuer passar o tom original para $doSite?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Manter $atual'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Usar $doSite'),
          ),
        ],
      ),
    );
    return trocar ?? false;
  }

  /// Líder cola a cifra de novo (conserta música cadastrada com a cifra
  /// embolada num parágrafo só): a cifra vira a da igreja e a letra é
  /// trocada pela letra pura tirada dela.
  Future<void> _colarCifra() async {
    final auth = context.read<AuthProvider>();
    final songs = context.read<SongsProvider>();
    final inicial = _arrangement?.hasChords == true
        ? _arrangement!.chords
        : (CifraColada.pareceCifra(widget.song.lyrics) ? widget.song.lyrics : '');

    final r = await Navigator.push<CifraColada>(
      context,
      GlassPageRoute(
        builder: (_) => ColarCifraScreen(
          musica: widget.song.name,
          artista: widget.song.artist,
          inicial: inicial,
        ),
      ),
    );
    if (r == null || !mounted) return;

    String? erro;
    ArrangementModel? novo = _arrangement;
    if (r.temAcordes) {
      final base = _arrangement ??
          FirestoreService.createArrangementModel(
            songId: widget.song.id,
            churchKey: r.tom ?? widget.song.originalKey,
            approvedBy: auth.user?.id,
          );
      final salvo = await FirestoreService.saveArrangement(base.copyWith(
        chords: r.cifra,
        churchKey: _arrangement == null ? null : (r.tom ?? base.churchKey),
        approvedBy: auth.user?.id,
        updatedAt: DateTime.now(),
      ));
      if (salvo.success) {
        novo = salvo.arrangement;
      } else {
        erro = salvo.error;
      }
    }
    // O TOM ORIGINAL. Era aqui que a música ficava "em G" com a cifra em D:
    // a cifra colada trazia o tom, e ninguém perguntava nada — o campo
    // continuava com o valor antigo e o levita lia o tom errado.
    //
    // Trocar sem perguntar também não serve: o tom original é da obra, e o
    // site pode estar mostrando a cifra em outro. Então: vazio, preenche;
    // diferente, pergunta.
    var novoTom = widget.song.originalKey;
    final tomDoSite = tomDaLista(r.tom);
    if (tomDoSite != null && tomDoSite != widget.song.originalKey) {
      if (widget.song.originalKey.trim().isEmpty) {
        novoTom = tomDoSite;
      } else if (await _confirmarTroca(widget.song.originalKey, tomDoSite)) {
        novoTom = tomDoSite;
      }
      if (!mounted) return;
    }

    final letraNova = r.letra.isNotEmpty && r.letra != widget.song.lyrics;
    if (erro == null && (letraNova || novoTom != widget.song.originalKey)) {
      erro = await songs.updateSong(widget.song.copyWith(
        lyrics: letraNova ? r.letra : null,
        originalKey: novoTom,
      ));
    }
    if (!mounted) return;
    setState(() {
      _arrangement = novo;
      if (r.temAcordes && !_cantaAgora(context)) _showChords = true;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(erro ?? 'Cifra salva.'),
        backgroundColor: erro == null ? AppColors.success : AppColors.red,
      ),
    );
  }

  /// Letra atual: a da lista de músicas (atualiza depois de colar a cifra).
  String _letra(SongsProvider songs) {
    for (final s in songs.allSongs) {
      if (s.id == widget.song.id) return s.lyrics;
    }
    return widget.song.lyrics;
  }

  /// Personal note for this song — only this musician sees it.
  Future<void> _editNotes() async {
    final auth = context.read<AuthProvider>();
    final controller =
        TextEditingController(text: auth.getSongNotes(widget.song.id));

    final saved = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Minha anotação'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Só você vê isto. Nem o líder.',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              maxLines: 4,
              maxLength: 2000,
              decoration: const InputDecoration(
                hintText: 'Ex: entro na segunda voz, capotraste na 2ª casa...',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );

    controller.dispose();
    if (saved == null || !mounted) return;

    final error = await auth.saveSongNotes(widget.song.id, saved);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error ?? 'Anotação salva.'),
        backgroundColor: error == null ? AppColors.success : AppColors.red,
      ),
    );
  }

  /// Abre o vídeo, e AVISA quando não dá.
  ///
  /// Antes: `canLaunchUrl` dizendo não fazia o toque não produzir nada —
  /// nem som, nem aviso, nem tela. No iPhone instalado isso acontece com
  /// alguma frequência, e a pessoa lê como app travado.
  Future<void> _openYoutube() => abrirLink(context, widget.song.videoUrl);

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
              ? 'Música salva no celular. Abre sem internet.'
              : 'Música tirada do celular'),
          backgroundColor:
              isNowOffline ? AppColors.success : AppColors.textSecondaryLight,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  bool get _mostrandoCifra => _showChords && _hasChords;

  /// A cifra (no tom escolhido), quando há e a pessoa pediu; senão a letra.
  /// Quem canta nunca vê acorde: se a letra antiga tiver acordes no meio,
  /// sai a letra pura.
  String _textoExibido(String letra, bool canta) {
    if (_mostrandoCifra) {
      return ChordTransposer.transposeText(_arrangement!.chords, _semitones);
    }
    if (canta) return CifraColada.letraDe(letra);
    return CifraColada.pareceCifra(letra)
        ? ChordTransposer.transposeText(letra, _semitones)
        : letra;
  }

  /// Fonte de largura fixa sempre que houver acordes na tela.
  bool _monoespacada(String letra, bool canta) =>
      _mostrandoCifra || (!canta && CifraColada.pareceCifra(letra));

  /// Key being shown: the church's arrangement is the starting point, the
  /// song's recorded key is the fallback.
  String get _currentKey {
    final base = _arrangement?.churchKey.isNotEmpty == true
        ? _arrangement!.churchKey
        : widget.song.originalKey;
    return ChordTransposer.getKeyName(base, _semitones);
  }

  bool get _hasChords => (_arrangement?.chords ?? '').isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final songs = context.watch<SongsProvider>();
    final isFav = auth.isFavorite(widget.song.id);
    final isOffline = songs.isOffline(widget.song.id);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final canta = _cantaAgora(context);
    final letra = _letra(songs);
    final texto = _textoExibido(letra, canta);
    final mono = _monoespacada(letra, canta);

    if (_isWorshipMode) {
      return _WorshipModeView(
        song: widget.song,
        displayText: texto,
        currentKey: _currentKey,
        showChords: mono,
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
          // O menu aparece para o líder e para quem cadastrou a música:
          // quem digitou o nome errado é quem mais precisa consertá-lo, e
          // antes só o líder podia.
          if (auth.isAdmin || _souQuemCadastrou(auth.user?.id))
            PopupMenuButton<String>(
              onSelected: (v) async {
                if (v == 'editar') {
                  await _editar();
                  return;
                }
                if (v == 'colar') {
                  await _colarCifra();
                  return;
                }
                if (v == 'arquivar') {
                  // Não apaga: tira do repertório. O documento fica, então
                  // os cultos em que a música foi tocada seguem mostrando o
                  // nome dela, e dá para voltar atrás.
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: Text('Tirar "${widget.song.name}" do repertório?'),
                      content: Text(
                        [
                          if (widget.song.artist.isNotEmpty)
                            '${widget.song.name} — ${widget.song.artist}'
                          else
                            widget.song.name,
                          '',
                          'Ela sai da lista e da busca para todo mundo, com '
                              'a cifra e as anotações da música.',
                          '',
                          'DÁ PARA DESFAZER: nada é apagado. Os cultos em '
                              'que ela já foi tocada continuam mostrando o '
                              'nome, e você devolve a música em Músicas → '
                              'Fora do repertório.',
                        ].join('\n'),
                        style: const TextStyle(
                            fontFamily: 'Poppins', fontSize: 13.5, height: 1.45),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Cancelar'),
                        ),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(context, true),
                          style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.red,
                              foregroundColor: Colors.white),
                          child: const Text('Tirar do repertório'),
                        ),
                      ],
                    ),
                  );
                  if (confirm == true && mounted) {
                    final error = await songs.arquivar(
                        widget.song.id, auth.user?.id ?? '');
                    if (!mounted) return;
                    if (error == null) {
                      Navigator.pop(context);
                    } else {
                      // Antes a tela fechava mesmo quando falhava, e a música
                      // reaparecia na lista sem explicação.
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                            content: Text(error),
                            backgroundColor: AppColors.red),
                      );
                    }
                  }
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'editar',
                  child: Row(
                    children: [
                      Icon(Icons.edit_outlined, size: 18),
                      SizedBox(width: 8),
                      Text('Editar música'),
                    ],
                  ),
                ),
                if (auth.isAdmin)
                  const PopupMenuItem(
                    value: 'colar',
                    child: Row(
                      children: [
                        Icon(Icons.content_paste_rounded, size: 18),
                        SizedBox(width: 8),
                        Text('Colar cifra'),
                      ],
                    ),
                  ),
                // Tirar do repertório continua só do líder: é decisão sobre o
                // repertório da igreja, não sobre o cadastro de uma música.
                if (auth.isAdmin)
                  const PopupMenuItem(
                    value: 'arquivar',
                    child: Row(
                      children: [
                        Icon(Icons.archive_outlined,
                            color: AppColors.red, size: 18),
                        SizedBox(width: 8),
                        Text('Tirar do repertório (dá para devolver)',
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
                    // Chart: only offered once we know there is one. The
                    // chart belongs to the church's arrangement and is
                    // fetched when this screen opens.
                    if (_loadingArrangement)
                      const _ToggleChip(
                        label: 'Carregando cifra...',
                        icon: Icons.hourglass_empty_rounded,
                        isActive: false,
                      )
                    else if (_hasChords)
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
                      )
                    else
                      const _ToggleChip(
                        label: 'Sem cifra ainda',
                        icon: Icons.music_off_rounded,
                        isActive: false,
                      ),
                    // Personal notes, private to this musician.
                    _ToggleChip(
                      label: auth.getSongNotes(widget.song.id).isEmpty
                          ? 'Minha anotação'
                          : 'Minha anotação ✓',
                      icon: Icons.sticky_note_2_outlined,
                      isActive: auth.getSongNotes(widget.song.id).isNotEmpty,
                      onTap: _editNotes,
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
                      label: isOffline
                          ? 'Tirar do celular'
                          : 'Salvar no celular',
                      icon: isOffline
                          ? Icons.download_done_rounded
                          : Icons.download_rounded,
                      isActive: isOffline,
                      onTap: _toggleOffline,
                    ),
                    // Só abre a busca do site no navegador; nada é lido de lá.
                    _ToggleChip(
                      label: 'Cifra Club',
                      icon: Icons.open_in_new_rounded,
                      isActive: false,
                      onTap: () => abrirBuscaCifraClub(
                          context, widget.song.name, widget.song.artist),
                    ),
                    if (widget.song.videoUrl != null)
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
          // O recado do líder sobre a música: "entra sem bateria", "repete o
          // refrão três vezes". Fica ACIMA da letra, e não num menu, porque
          // é combinação que vale no momento de tocar.
          if (widget.song.observacoes.trim().isNotEmpty)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.blue.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border:
                    Border.all(color: AppColors.blue.withOpacity(0.25)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.push_pin_outlined,
                      size: 16, color: AppColors.blue),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.song.observacoes.trim(),
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12.5,
                        height: 1.4,
                        color: isDark
                            ? AppColors.textPrimaryDark
                            : AppColors.textPrimaryLight,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          // Lyrics / Chords
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
              child: _TextoMusica(
                texto: texto,
                mono: mono,
                style: TextStyle(
                  fontFamily: mono ? 'JetBrainsMono' : 'Poppins',
                  fontSize: mono ? 14 : (canta ? 22 : 16),
                  height: mono ? 1.5 : 1.8,
                  fontWeight: canta && !mono ? FontWeight.w500 : null,
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

  /// Null for a chip that only states something (loading, no chart yet).
  final VoidCallback? onTap;

  final Color? activeColor;

  const _ToggleChip({
    required this.label,
    required this.icon,
    required this.isActive,
    this.onTap,
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
                  child: _TextoMusica(
                    texto: displayText,
                    mono: showChords,
                    style: TextStyle(
                      fontFamily: showChords ? 'JetBrainsMono' : 'Poppins',
                      fontSize: fontSize,
                      height: showChords ? 1.5 : 2.0,
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


/// Letra ou cifra. A cifra não quebra linha (quebrar desalinha o acorde da
/// sílaba): se a linha for mais larga que a tela, ela rola para o lado.
class _TextoMusica extends StatelessWidget {
  final String texto;
  final bool mono;
  final TextStyle style;

  const _TextoMusica({
    required this.texto,
    required this.mono,
    required this.style,
  });

  @override
  Widget build(BuildContext context) {
    final t = Text(
      texto.isNotEmpty ? texto : 'Nenhuma letra disponível',
      softWrap: !mono,
      style: style,
    );
    if (!mono) return t;
    return SingleChildScrollView(scrollDirection: Axis.horizontal, child: t);
  }
}
