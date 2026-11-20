import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../../core/constants/hinarios.dart';
import '../../providers/songs_provider.dart';
import 'projetar_letra_screen.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/chord_transposer.dart';
import '../../../core/utils/cifra_colada.dart';
import '../../../core/utils/mapa_da_musica.dart';
import '../../widgets/common/abrir_link.dart';
import '../../widgets/common/glass.dart';
import '../../widgets/songs/colar_cifra.dart';
import 'editar_musica_screen.dart';
import 'editor_de_cifra_screen.dart';
import '../../../data/services/local_storage_service.dart';
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

  /// Esconder as linhas de tablatura.
  ///
  /// Fica no APARELHO, e vale para todas as músicas: quem toca violão quer
  /// tablatura sempre, e quem canta nunca. Perguntar música por música seria
  /// o mesmo toque repetido para a mesma pessoa, para sempre.
  bool _ocultarTab = LocalStorageService.ocultarTablaturas;

  /// O tom se salva sozinho, um instante depois do último toque em − ou +.
  ///
  /// Antes havia os botões "Salvar" e "Reset" ao lado do tom, e é o tipo de
  /// botão que não deveria existir: a pessoa acabou de dizer em que tom quer
  /// ler: pedir que ela confirme é pedir duas vezes. Esperar um instante
  /// evita gravar quatro vezes quando ela toca em + quatro vezes.
  static const _esperaDoTom = Duration(milliseconds: 700);
  Timer? _relogioDoTom;

  /// How this church plays the song. Fetched when the screen opens — it is a
  /// subcollection of the song, so the chart is not downloaded with the song
  /// list.
  ArrangementModel? _arrangement;

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

  @override
  void dispose() {
    _relogioDoTom?.cancel();
    super.dispose();
  }

  /// Muda o tom na tela e guarda depois, sem avisar nada.
  ///
  /// Sem mensagem de "tom salvo": é o que a pessoa pediu, e um aviso a cada
  /// toque em + viraria quatro avisos seguidos.
  void _mudarTom(int novo) {
    setState(() => _semitones = novo);
    _relogioDoTom?.cancel();
    _relogioDoTom = Timer(_esperaDoTom, () {
      if (!mounted) return;
      context.read<AuthProvider>().saveSongTone(widget.song.id, _semitones);
    });
  }

  Future<void> _loadArrangement() async {
    final found = await FirestoreService.getArrangement(widget.song.id);
    if (!mounted) return;
    final canta = _cantaAgora(context);
    setState(() {
      _arrangement = found;
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

    // A letra e a cifra vêm por fora do `SongModel`, porque a cifra mora no
    // ARRANJO (modelo de três camadas) e a letra pura é extraída dela. Nulo
    // significa "não mexeu" — e é diferente de vazio, que apagaria tudo.
    final cifra = r.cifra;
    if (erro == null && cifra != null && mounted) {
      await _gravarCifra(CifraColada.analisar(
        cifra,
        nomeConhecido: r.musica.name,
        artistaConhecido: r.musica.artist,
      ));
    }
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
  /// O texto que o editor abre: a cifra da igreja, ou a letra quando não há
  /// cifra. Nunca vazio quando existe algo escrito na música.
  String get _textoParaEditar => _arrangement?.hasChords == true
      ? _arrangement!.chords
      : widget.song.lyrics;

  /// Abre o editor de letra e cifra.
  Future<void> _abrirEditorDeCifra() async {
    final r = await Navigator.push<CifraColada>(
      context,
      GlassPageRoute(
        builder: (_) => EditorDeCifraScreen(
          songId: widget.song.id,
          musica: widget.song.name,
          artista: widget.song.artist,
          inicial: _textoParaEditar,
          tomDoTexto: _arrangement?.churchKey.isNotEmpty == true
              ? _arrangement!.churchKey
              : widget.song.originalKey,
        ),
      ),
    );
    if (r == null || !mounted) return;
    await _gravarCifra(r);
  }

  /// Grava a cifra e a letra que saíram do editor.
  ///
  /// UM caminho só, chamado pelo editor e por "Editar música". Antes havia
  /// dois lugares gravando as mesmas três coisas (a cifra no arranjo, a letra
  /// na música e o tom original), e o segundo esquecia de perguntar sobre o
  /// tom — o defeito que já fez o levita ler o tom errado no domingo.
  Future<void> _gravarCifra(CifraColada r) async {
    final auth = context.read<AuthProvider>();
    final songs = context.read<SongsProvider>();

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
    // O rascunho do editor só morre quando a gravação deu certo. Apagá-lo
    // antes, ou junto de uma falha, jogaria fora exatamente o texto que a
    // pessoa precisa para tentar de novo.
    if (erro == null) {
      await LocalStorageService.esquecerRascunho(widget.song.id);
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(erro ?? 'Cifra salva.'),
        backgroundColor: erro == null ? AppColors.success : AppColors.red,
      ),
    );
  }

  /// A letra em tela cheia, para o telão. Nunca com cifra: se só há cifra, sai
  /// a letra tirada dela.
  void _projetar() {
    final letra = _letra(context.read<SongsProvider>());
    final base = letra.trim().isNotEmpty
        ? letra
        : (_arrangement?.hasChords == true ? _arrangement!.chords : '');
    ProjetarLetraScreen.abrir(
      context,
      titulo: nomeSemHinario(widget.song.name),
      subtitulo: widget.song.artist.isEmpty ? null : widget.song.artist,
      letra: base,
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

  /// Tirar a música do repertório. NÃO apaga: o documento fica.
  ///
  /// A confirmação diz o NOME da música e o que não se perde. O repertório
  /// inteiro já sumiu do banco uma vez por um toque num menu, com uma
  /// confirmação que não dizia sequer qual música era.
  Future<void> _tirarDoRepertorio() async {
    final songs = context.read<SongsProvider>();
    final auth = context.read<AuthProvider>();

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
            'Ela sai da lista e da busca para todo mundo, com a cifra e as '
                'anotações da música.',
            '',
            'DÁ PARA DESFAZER: nada é apagado. Os cultos em que ela já foi '
                'tocada continuam mostrando o nome, e você devolve a música '
                'em Músicas → Fora do repertório.',
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
                backgroundColor: AppColors.red, foregroundColor: Colors.white),
            child: const Text('Tirar do repertório'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    final erro = await songs.arquivar(widget.song.id, auth.user?.id ?? '');
    if (!mounted) return;
    if (erro == null) {
      Navigator.pop(context);
    } else {
      // Antes a tela fechava mesmo quando falhava, e a música reaparecia na
      // lista sem explicação nenhuma.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(erro), backgroundColor: AppColors.red),
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

  /// Uma linha do menu ⋯, no mesmo formato sempre.
  ///
  /// Existe para o menu não ser dez blocos de `Row` copiados: a próxima
  /// opção que alguém acrescentar vai nascer parecida com as outras.
  PopupMenuItem<String> _opcao(String valor, IconData icone, String texto,
      {Color? cor}) {
    return PopupMenuItem<String>(
      value: valor,
      child: Row(
        children: [
          Icon(icone, size: 18, color: cor),
          const SizedBox(width: 10),
          Expanded(child: Text(texto, style: TextStyle(color: cor))),
        ],
      ),
    );
  }

  /// Tem tablatura na cifra desta música?
  bool get _temTablatura =>
      _hasChords && _arrangement!.chords.split('\n').any(ehTablatura);

  bool get _mostrandoCifra => _showChords && _hasChords;

  /// A cifra (no tom escolhido), quando há e a pessoa pediu; senão a letra.
  /// Quem canta nunca vê acorde: se a letra antiga tiver acordes no meio,
  /// sai a letra pura.
  String _textoExibido(String letra, bool canta) {
    if (_mostrandoCifra) {
      final cifra = _ocultarTab
          ? semTablaturas(_arrangement!.chords)
          : _arrangement!.chords;
      return ChordTransposer.transposeText(cifra, _semitones);
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
          // Coração e ⋯, e nada mais.
          //
          // Eram OITO botões no topo: cifra, anotação, modo culto, offline,
          // Cifra Club, YouTube, salvar tom e reset. Oito escolhas para quem
          // abriu a tela querendo uma coisa — ler a música. Tudo continua
          // existindo, dentro do ⋯; o que saiu da tela foi a obrigação de
          // escolher antes de ler.
          IconButton(
            icon: Icon(
              isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              color: isFav ? AppColors.red : null,
            ),
            tooltip: isFav ? 'Tirar das favoritas' : 'Favoritar',
            onPressed: () => auth.toggleFavorite(widget.song.id),
          ),
          PopupMenuButton<String>(
            tooltip: 'Mais opções',
            onSelected: (v) async {
              switch (v) {
                case 'cifra-ver':
                  setState(() => _showChords = !_showChords);
                  return;
                case 'tab':
                  final novo = !_ocultarTab;
                  await LocalStorageService.salvarOcultarTablaturas(novo);
                  if (mounted) setState(() => _ocultarTab = novo);
                  return;
                case 'anotacao':
                  await _editNotes();
                  return;
                case 'culto':
                  setState(() => _isWorshipMode = true);
                  return;
                case 'projetar':
                  _projetar();
                  return;
                case 'offline':
                  await _toggleOffline();
                  return;
                case 'tom-original':
                  _mudarTom(0);
                  return;
                case 'cifraclub':
                  await abrirBuscaCifraClub(
                      context, widget.song.name, widget.song.artist);
                  return;
                case 'youtube':
                  await _openYoutube();
                  return;
                case 'letra':
                  await _abrirEditorDeCifra();
                  return;
                case 'editar':
                  await _editar();
                  return;
                case 'arquivar':
                  await _tirarDoRepertorio();
                  return;
              }
            },
            itemBuilder: (_) => [
              // A ordem é a do uso: o que se faz lendo vem primeiro, o que
              // se faz uma vez na vida da música vem no fim.
              if (_hasChords)
                _opcao(
                  'cifra-ver',
                  _showChords ? Icons.queue_music_rounded
                      : Icons.music_note_rounded,
                  // As MESMAS palavras do Perfil ("Eu canto" / "Eu toco"):
                  // "ocultar" e "mostrar" nomeiam a operação, estas duas
                  // dizem o que a pessoa vai ver. Dois vocabulários para a
                  // mesma escolha é o jeito de ela parecer duas escolhas.
                  _showChords ? 'Ver só a letra' : 'Ver a cifra',
                ),
              if (_temTablatura)
                _opcao(
                  'tab',
                  Icons.straighten_rounded,
                  _ocultarTab ? 'Mostrar tablaturas' : 'Ocultar tablaturas',
                ),
              if (_semitones != 0)
                _opcao('tom-original', Icons.restart_alt_rounded,
                    'Voltar ao tom original'),
              _opcao(
                'anotacao',
                Icons.sticky_note_2_outlined,
                auth.getSongNotes(widget.song.id).isEmpty
                    ? 'Minha anotação'
                    : 'Minha anotação ✓',
              ),
              _opcao('culto', Icons.fullscreen_rounded, 'Modo culto'),
              _opcao('projetar', Icons.cast_rounded,
                  'Projetar a letra (tela cheia)'),
              _opcao(
                'offline',
                isOffline ? Icons.download_done_rounded
                    : Icons.download_rounded,
                isOffline ? 'Tirar do celular' : 'Salvar no celular',
              ),
              if (widget.song.videoUrl != null)
                _opcao('youtube', Icons.play_circle_outline_rounded,
                    'Abrir no YouTube'),
              _opcao('cifraclub', Icons.open_in_new_rounded,
                  'Abrir no Cifra Club'),
              if (auth.isAdmin)
                _opcao('letra', Icons.notes_rounded, 'Letra e cifra'),
              if (auth.isAdmin || _souQuemCadastrou(auth.user?.id))
                _opcao('editar', Icons.edit_outlined, 'Editar música'),
              if (auth.isAdmin)
                _opcao('arquivar', Icons.archive_outlined,
                    'Tirar do repertório (dá para devolver)',
                    cor: AppColors.red),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // O TOM, e nada mais.
          //
          // É a única coisa que se mexe lendo a música, e a primeira que
          // quem vai tocar procura. Os botões "Salvar" e "Reset" que ficavam
          // ao lado saíram: o tom se salva sozinho (ver `_mudarTom`), e
          // voltar ao original virou uma linha no ⋯ — onde ela aparece só
          // quando há o que voltar.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'Tom $_currentKey',
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
                const Spacer(),
                _BotaoDeTom(
                  rotulo: '−',
                  isDark: isDark,
                  onTap: () => _mudarTom(_semitones - 1),
                ),
                // MEDIDO A 375 px: "Original" em 54 px quebrava em duas
                // linhas ("Origina / l") e subia por cima do −. Em letra
                // minúscula, numa linha só e com mais espaço, cabe — e
                // minúscula é o certo aqui, que é legenda e não título.
                SizedBox(
                  width: 72,
                  child: Text(
                    _semitones == 0
                        ? 'original'
                        : ChordTransposer.getTransposeDisplay(_semitones),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.visible,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? AppColors.textSecondaryDark
                          : AppColors.textSecondaryLight,
                    ),
                  ),
                ),
                _BotaoDeTom(
                  rotulo: '+',
                  isDark: isDark,
                  onTap: () => _mudarTom(_semitones + 1),
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
                color: AppColors.blue.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border:
                    Border.all(color: AppColors.blue.withValues(alpha: 0.25)),
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

/// O − e o + do tom: alvo de 44 px, que o polegar acerta sem olhar.
class _BotaoDeTom extends StatelessWidget {
  final String rotulo;
  final bool isDark;
  final VoidCallback onTap;

  const _BotaoDeTom({
    required this.rotulo,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.05),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: Text(
              rotulo,
              style: TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w600,
                color: isDark
                    ? AppColors.textPrimaryDark
                    : AppColors.textPrimaryLight,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
