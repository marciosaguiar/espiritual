import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/platform/tela_acesa.dart';
import '../../../core/platform/tela_cheia.dart';
import '../../../core/utils/projetar_letra.dart';
import '../../widgets/common/glass.dart';

/// A letra em tela cheia, para projetar no telão.
///
/// Quem usa: a pessoa do computador ligado ao projetor, no meio do culto. Por
/// isso é o oposto do resto do app — fundo escuro, letra enorme, uma estrofe
/// por vez, **sem cifra, sem botão na frente da letra**, e avançando do jeito
/// que se avança slide: espaço, setas, Page Down ou Enter (o botão "próximo"
/// de um controle de apresentador manda Enter ou Page Down). Esc sai.
///
/// Os botões existem para o mouse e o dedo, mas somem depois de 3 segundos
/// parados — junto com o cursor. Botão e mãozinha sobre a letra, na frente da
/// igreja, seriam exatamente o que não pode aparecer.
class ProjetarLetraScreen extends StatefulWidget {
  final String titulo;
  final String? subtitulo;
  final String letra;

  const ProjetarLetraScreen({
    super.key,
    required this.titulo,
    this.subtitulo,
    required this.letra,
  });

  /// Abre POR CIMA de tudo (inclusive da navegação lateral): o telão não pode
  /// mostrar o menu do app.
  static Future<void> abrir(
    BuildContext context, {
    required String titulo,
    String? subtitulo,
    required String letra,
  }) {
    return Navigator.of(context, rootNavigator: true).push(
      GlassPageRoute<void>(
        larguraMaxima: double.infinity,
        fullscreenDialog: true,
        builder: (_) => ProjetarLetraScreen(
          titulo: titulo,
          subtitulo: subtitulo,
          letra: letra,
        ),
      ),
    );
  }

  @override
  State<ProjetarLetraScreen> createState() => _ProjetarLetraScreenState();
}

class _ProjetarLetraScreenState extends State<ProjetarLetraScreen> {
  late final List<SlideDeLetra> _slides = dividirEmSlides(widget.letra);
  int _i = 0;
  bool _controles = true;
  bool _entreiEmTelaCheia = false;
  String _aviso = '';
  Timer? _some;
  final _foco = FocusNode(debugLabel: 'projetar');

  @override
  void initState() {
    super.initState();
    // O computador do telão não pode apagar a tela no meio do louvor.
    manterTelaAcesa();
    _mostrarControles();
  }

  @override
  void dispose() {
    _some?.cancel();
    _foco.dispose();
    soltarTela();
    // Sai da tela cheia que ESTA tela pediu: deixar o navegador em tela cheia
    // depois de voltar ao app seria a pessoa sem a barra de endereço sem saber
    // por quê.
    if (_entreiEmTelaCheia) sairDaTelaCheia();
    super.dispose();
  }

  void _mostrarControles() {
    if (!_controles) setState(() => _controles = true);
    _some?.cancel();
    _some = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _controles = false);
    });
  }

  void _ir(int novo) {
    if (_slides.isEmpty) return;
    setState(() => _i = novo.clamp(0, _slides.length - 1));
  }

  Future<void> _telaCheia() async {
    final r = await alternarTelaCheia();
    if (!mounted) return;
    setState(() {
      _entreiEmTelaCheia = r == 'entrou';
      _aviso = switch (r) {
        'negado' => 'O navegador não deixou. Aperte F11 para a tela cheia.',
        'sem-suporte' => 'Este aparelho não tem tela cheia por aqui. No '
            'computador, aperte F11.',
        _ => '',
      };
    });
  }

  KeyEventResult _tecla(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final acao = acaoDaTecla(
      e.logicalKey,
      shift: HardwareKeyboard.instance.isShiftPressed,
    );
    if (acao == null) return KeyEventResult.ignored;
    _mostrarControles();
    switch (acao) {
      case AcaoDoPalco.proxima:
        _ir(_i + 1);
      case AcaoDoPalco.anterior:
        _ir(_i - 1);
      case AcaoDoPalco.primeira:
        _ir(0);
      case AcaoDoPalco.ultima:
        _ir(_slides.length - 1);
      case AcaoDoPalco.sair:
        Navigator.of(context).maybePop();
      case AcaoDoPalco.telaCheia:
        _telaCheia();
      case AcaoDoPalco.proximaMusica || AcaoDoPalco.musicaAnterior:
        // Aqui há uma música só.
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData.dark(useMaterial3: true),
      child: Scaffold(
        // Preto de verdade: o telão é lido de longe, muitas vezes com a luz da
        // igreja acesa. O tema do app não vale aqui.
        backgroundColor: const Color(0xFF000000),
        body: Focus(
          focusNode: _foco,
          autofocus: true,
          onKeyEvent: _tecla,
          child: MouseRegion(
            cursor: _controles ? MouseCursor.defer : SystemMouseCursors.none,
            onHover: (_) => _mostrarControles(),
            child: LayoutBuilder(
              builder: (context, c) => GestureDetector(
                behavior: HitTestBehavior.opaque,
                // Toque ou clique: o terço da esquerda volta, o resto avança.
                onTapUp: (d) {
                  _mostrarControles();
                  _ir(d.localPosition.dx < c.maxWidth / 3 ? _i - 1 : _i + 1);
                },
                child: Stack(
                  children: [
                    Positioned.fill(child: _corpo(c)),
                    _barra(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _corpo(BoxConstraints c) {
    if (_slides.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Esta música ainda não tem letra para projetar.',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontFamily: 'Poppins', fontSize: 28, color: Colors.white70),
          ),
        ),
      );
    }
    final slide = _slides[_i];
    final fonte = tamanhoDaFonte(
      linhas: slide.linhas,
      largura: c.maxWidth - 96,
      altura: c.maxHeight - 160,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(48, 72, 48, 88),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (slide.rotulo != null) ...[
              Text(
                slide.rotulo!.toUpperCase(),
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: (fonte * 0.32).clamp(16.0, 44.0),
                  fontWeight: FontWeight.w600,
                  letterSpacing: 4,
                  color: const Color(0xFFFFC857),
                ),
              ),
              SizedBox(height: fonte * 0.28),
            ],
            for (final linha in slide.linhas)
              Text(
                linha,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: fonte,
                  height: 1.32,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// O título, o progresso e os botões. Somem com o cursor.
  Widget _barra() {
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: !_controles,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 250),
          opacity: _controles ? 1 : 0,
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(20, 14, 12, 14),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xCC000000), Color(0x00000000)],
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.titulo,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              color: Colors.white70,
                            ),
                          ),
                          if (widget.subtitulo != null)
                            Text(
                              widget.subtitulo!,
                              style: const TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 12.5,
                                color: Colors.white38,
                              ),
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Tela cheia (F)',
                      icon: const Icon(Icons.fullscreen_rounded,
                          color: Colors.white70),
                      onPressed: _telaCheia,
                    ),
                    IconButton(
                      tooltip: 'Sair (Esc)',
                      icon: const Icon(Icons.close_rounded,
                          color: Colors.white70),
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              if (_aviso.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    _aviso,
                    style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 14,
                        color: Color(0xFFFFC857)),
                  ),
                ),
              Container(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Color(0xCC000000), Color(0x00000000)],
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      tooltip: 'Anterior (←)',
                      icon: const Icon(Icons.chevron_left_rounded,
                          size: 34, color: Colors.white70),
                      onPressed: _i > 0 ? () => _ir(_i - 1) : null,
                    ),
                    // A dica das teclas só cabe (e só serve) onde há teclado: no
                    // celular ela estourava a largura, e quem toca na tela não
                    // precisa saber do espaço.
                    Flexible(
                      child: Text(
                        _slides.isEmpty
                            ? ''
                            : MediaQuery.sizeOf(context).width >= 700
                                ? '${_i + 1} de ${_slides.length}  ·  espaço '
                                    'ou setas para avançar'
                                : '${_i + 1} de ${_slides.length}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 13.5,
                          color: Colors.white54,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Próxima (espaço)',
                      icon: const Icon(Icons.chevron_right_rounded,
                          size: 34, color: Colors.white70),
                      onPressed: _i < _slides.length - 1
                          ? () => _ir(_i + 1)
                          : null,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
