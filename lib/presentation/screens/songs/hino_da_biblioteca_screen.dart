import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/hinarios.dart';
import '../../../core/utils/ajuste_de_fonte.dart';
import '../../../data/models/hino_da_biblioteca.dart';
import '../../../data/models/song_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/biblioteca_provider.dart';
import '../../providers/songs_provider.dart';
import '../../widgets/common/glass.dart';
import '../../widgets/common/responsivo.dart';
import 'projetar_letra_screen.dart';
import 'song_detail_screen.dart';

/// Ler um hino que está na biblioteca, mas ainda não no repertório.
///
/// POR QUE É UMA TELA À PARTE
///
/// Abrir o hino 15 no meio do culto tem de ser LER — e ler não escreve nada.
/// Quem pode criar música no banco é só o líder, e criar um documento em
/// `songs` a cada hino aberto encheria o repertório de hinos que ninguém usa
/// (e, com ele, a cota de leitura: ver [HinoDaBiblioteca]). Então esta tela
/// mostra o texto e mais nada, para qualquer pessoa aprovada.
///
/// O hino vira música do repertório quando o ministério decide USÁ-LO —
/// tom, cifra, favoritar, entrar num culto. É o que o botão do líder faz.
class HinoDaBibliotecaScreen extends StatefulWidget {
  final Hinario hinario;
  final HinoDaBiblioteca hino;

  const HinoDaBibliotecaScreen({
    super.key,
    required this.hinario,
    required this.hino,
  });

  @override
  State<HinoDaBibliotecaScreen> createState() => _HinoDaBibliotecaScreenState();
}

class _HinoDaBibliotecaScreenState extends State<HinoDaBibliotecaScreen> {
  /// Letra grande de saída: quem lê o hino de pé, de longe, com o celular na
  /// mão, é quem mais precisa — e metade do ministério tem mais de sessenta
  /// anos.
  static const double _minimo = 16;
  static const double _maximo = 36;
  static const double _passo = 2;

  double _fonte = 22;
  bool _gravando = false;

  /// Depois que a pessoa aperta A+ ou A−, o tamanho é o DELA, exato. Antes
  /// disso, em tela larga, a letra encolhe o que for preciso para nenhuma
  /// linha quebrar (ver `tamanhoQueCabe`). Sem esta chave, o A+ pareceria
  /// quebrado: a letra já encolhida não mudaria até a pessoa passar do
  /// tamanho que cabe.
  bool _ajustouAMao = false;

  void _aumentar() => setState(() {
        _ajustouAMao = true;
        if (_fonte < _maximo) _fonte += _passo;
      });

  void _diminuir() => setState(() {
        _ajustouAMao = true;
        if (_fonte > _minimo) _fonte -= _passo;
      });

  void _avisar(String texto, {bool erro = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(texto),
        backgroundColor: erro ? AppColors.red : AppColors.success,
        duration: Duration(seconds: erro ? 6 : 2),
      ),
    );
  }

  /// Põe o hino no repertório e abre a música.
  Future<void> _porNoRepertorio() async {
    if (_gravando) return;
    final songs = context.read<SongsProvider>();

    // Alguém pode ter posto este hino enquanto a tela estava aberta. Criar
    // outra música com o mesmo número seria a duplicata que perde a cifra
    // que já foi colada na primeira.
    final existente =
        songs.hinoCadastrado(widget.hinario.id, widget.hino.numero);
    if (existente != null) {
      if (existente.archived) {
        _avisar(
          'Este hino já foi cadastrado e está fora do repertório. Em '
          'Músicas, na lista "Fora do repertório", toque em Devolver.',
          erro: true,
        );
        return;
      }
      _abrirMusica(existente);
      return;
    }

    final auth = context.read<AuthProvider>();
    final biblioteca = context.read<BibliotecaProvider>();
    setState(() => _gravando = true);
    final r = await biblioteca.porNoRepertorio(
      widget.hinario,
      widget.hino,
      porQuemId: auth.user?.id,
    );
    if (!mounted) return;
    setState(() => _gravando = false);

    if (r.error != null || r.musica == null) {
      _avisar(r.error ?? 'Não foi possível pôr o hino no repertório.',
          erro: true);
      return;
    }
    _abrirMusica(r.musica!);
  }

  void _abrirMusica(SongModel song) {
    // `pushReplacement`: quem volta, volta ao teclado — e não a esta tela,
    // que já cumpriu o papel e agora mostraria um botão sem sentido.
    Navigator.pushReplacement(
      context,
      GlassPageRoute(builder: (_) => SongDetailScreen(song: song)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ehLider = context.watch<AuthProvider>().isAdmin;
    final corTexto =
        isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final corMuda =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.hinario.sigla} ${widget.hino.numero}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.cast_rounded),
            tooltip: 'Projetar a letra (tela cheia)',
            onPressed: () => ProjetarLetraScreen.abrir(
              context,
              titulo: widget.hino.titulo,
              subtitulo: '${widget.hinario.nome}, hino ${widget.hino.numero}',
              letra: widget.hino.letra,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.text_decrease_rounded),
            tooltip: 'Letra menor',
            onPressed: _fonte > _minimo ? _diminuir : null,
          ),
          IconButton(
            icon: const Icon(Icons.text_increase_rounded),
            tooltip: 'Letra maior',
            onPressed: _fonte < _maximo ? _aumentar : null,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                // Largura inteira, e não a da linha mais comprida: um
                // `SingleChildScrollView` dentro de um `Column` encolhe até o
                // conteúdo e é centralizado, e em tela larga o hino virava um
                // bloco estreito no meio da janela.
                child: SizedBox(
                  width: double.infinity,
                  child: LayoutBuilder(builder: (ctx, c) {
                    // Em tela larga, a linha do hino NÃO quebra no meio da
                    // frase: a letra encolhe até caber. No celular, nada muda.
                    final estiloBase = TextStyle(
                        fontFamily: 'Poppins', height: 1.55, color: corTexto);
                    final fonte = _ajustouAMao || !Porte.lateral(ctx)
                        ? _fonte
                        : tamanhoQueCabe(
                            texto: widget.hino.letra,
                            estilo: estiloBase,
                            // O recuo de 20 de cada lado já saiu de `c`.
                            largura: c.maxWidth,
                            maximo: _fonte,
                            minimo: _minimo,
                          );
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.hino.titulo,
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: fonte + 2,
                            fontWeight: FontWeight.w700,
                            height: 1.25,
                            color: corTexto,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${widget.hinario.nome}, hino ${widget.hino.numero}',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 13,
                            color: corMuda,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          widget.hino.letra,
                          style: estiloBase.copyWith(fontSize: fonte),
                        ),
                      ],
                    );
                  }),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: ehLider
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        FilledButton.icon(
                          onPressed: _gravando ? null : _porNoRepertorio,
                          icon: _gravando
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.library_add_rounded),
                          label: const Text('Pôr no repertório'),
                          style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(50)),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'No repertório o hino ganha tom, cifra, favorito e '
                          'pode entrar num culto.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 12,
                            color: corMuda,
                          ),
                        ),
                      ],
                    )
                  : Text(
                      'Este hino ainda não está no repertório. Para pô-lo '
                      'num culto, peça a um líder.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12,
                        color: corMuda,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
