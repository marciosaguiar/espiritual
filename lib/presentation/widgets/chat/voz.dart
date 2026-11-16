import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/platform/voz.dart';
import '../../../data/models/message_model.dart';
import '../../../data/services/firestore_service.dart';

/// Quem está tocando, para a barra andar e para a outra bolha se apagar.
///
/// Um só para o app inteiro, porque o navegador também só tem um elemento de
/// áudio: tocar outro áudio para o anterior sem nenhuma coordenação, e este
/// objeto só repassa esse fato para as bolhas.
class TocadorDeVoz extends ChangeNotifier {
  TocadorDeVoz._();
  static final TocadorDeVoz instancia = TocadorDeVoz._();

  Timer? _relogio;
  String _id = '';
  bool _tocando = false;
  int _posicaoMs = 0;
  String _falhou = '';

  String get idAtual => _id;
  bool get tocando => _tocando;
  int get posicaoMs => _posicaoMs;

  bool estaTocando(String id) => _tocando && _id == id;
  int posicaoDe(String id) => _id == id ? _posicaoMs : 0;

  /// Este áudio deu erro ao decodificar, depois de o play ter sido aceito.
  ///
  /// O `canPlayType` dizer "maybe" e o som não sair é o caso que sobra: sem
  /// isto a bolha ficaria com o play parado, sem som e sem explicação.
  bool falhouEm(String id) => id.isNotEmpty && _falhou == id;

  void _acompanhar() {
    _relogio?.cancel();
    // 200 ms: a barra anda liso o bastante e não acorda a tela à toa.
    _relogio = Timer.periodic(const Duration(milliseconds: 200), (_) {
      final e = estadoDoAudio();
      if (e.id == _id &&
          e.tocando == _tocando &&
          e.posicaoMs == _posicaoMs &&
          e.falhou == _falhou) {
        return;
      }
      _id = e.id;
      _tocando = e.tocando;
      _posicaoMs = e.posicaoMs;
      _falhou = e.falhou;
      if (!_tocando) _relogio?.cancel();
      notifyListeners();
    });
  }

  Future<bool> tocar(String id, Uint8List bytes, String tipo) async {
    final deu = await tocarAudio(id, bytes, tipo);
    if (deu) {
      _id = id;
      _tocando = true;
      _posicaoMs = 0;
      _falhou = '';
      notifyListeners();
      // O relógio continua rodando um pouco depois do fim: é ele que vê o
      // erro de decodificação, que chega DEPOIS de o play ser aceito.
      _acompanhar();
    }
    return deu;
  }

  void pausar() {
    pausarAudio();
    _tocando = false;
    _relogio?.cancel();
    notifyListeners();
  }

  void retomar() {
    retomarAudio();
    _tocando = true;
    notifyListeners();
    _acompanhar();
  }

  @override
  void dispose() {
    _relogio?.cancel();
    super.dispose();
  }
}

/// A bolha de uma mensagem de voz: play, barra e duração.
///
/// Os bytes NÃO vêm com a mensagem: só descem quando alguém toca no play. É
/// por isso que a primeira vez tem um instante de espera, e a segunda não.
class BolhaDeVoz extends StatefulWidget {
  final MessageModel mensagem;
  final bool isMe;
  final bool isDark;

  const BolhaDeVoz({
    super.key,
    required this.mensagem,
    required this.isMe,
    required this.isDark,
  });

  @override
  State<BolhaDeVoz> createState() => _BolhaDeVozState();
}

class _BolhaDeVozState extends State<BolhaDeVoz> {
  Uint8List? _bytes;
  bool _baixando = false;
  String? _erro;

  String get _id => widget.mensagem.audioId ?? '';

  /// Este aparelho toca o formato em que ISTO foi gravado?
  bool get _formatoServe => podeTocar(widget.mensagem.audioTipo ?? '');

  Future<void> _tocarOuPausar() async {
    final tocador = TocadorDeVoz.instancia;

    if (tocador.estaTocando(_id)) {
      tocador.pausar();
      return;
    }
    if (_bytes != null && tocador.idAtual == _id) {
      tocador.retomar();
      return;
    }

    if (_bytes == null) {
      setState(() {
        _baixando = true;
        _erro = null;
      });
      final r = await FirestoreService.baixarAudio(_id);
      if (!mounted) return;
      if (r.bytes == null) {
        setState(() {
          _baixando = false;
          _erro = r.error ?? 'Não foi possível baixar o áudio.';
        });
        return;
      }
      _bytes = r.bytes;
      setState(() => _baixando = false);
    }

    final deu = await tocador.tocar(
        _id, _bytes!, widget.mensagem.audioTipo ?? 'audio/mp4');
    if (!deu && mounted) {
      setState(() => _erro = 'Este áudio não toca neste aparelho.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cor = widget.isMe
        ? (widget.isDark ? Colors.white : AppColors.textPrimaryLight)
        : (widget.isDark
            ? AppColors.textPrimaryDark
            : AppColors.textPrimaryLight);
    final fraca = cor.withValues(alpha: 0.6);

    // Formato que este aparelho não toca: diz isso, em vez de um play mudo.
    if (!_formatoServe) {
      return _Aviso(
        icone: Icons.volume_off_rounded,
        texto: 'Este áudio não toca neste aparelho.',
        cor: fraca,
      );
    }
    if (_erro != null) {
      return _Aviso(
          icone: Icons.error_outline_rounded, texto: _erro!, cor: fraca);
    }

    return AnimatedBuilder(
      animation: TocadorDeVoz.instancia,
      builder: (_, __) {
        final tocador = TocadorDeVoz.instancia;
        if (tocador.falhouEm(_id)) {
          return _Aviso(
            icone: Icons.volume_off_rounded,
            texto: 'Este áudio não toca neste aparelho.',
            cor: fraca,
          );
        }
        final tocando = tocador.estaTocando(_id);
        final total = (widget.mensagem.audioDuracaoMs ?? 1).clamp(1, 1 << 30);
        final andado = tocador.posicaoDe(_id).clamp(0, total);
        final fracao = andado / total;

        return SizedBox(
          width: 210,
          child: Row(
            children: [
              SizedBox(
                width: 36,
                height: 36,
                child: _baixando
                    ? Padding(
                        padding: const EdgeInsets.all(8),
                        child: CircularProgressIndicator(
                            strokeWidth: 2.2, color: fraca),
                      )
                    : IconButton(
                        padding: EdgeInsets.zero,
                        onPressed: _tocarOuPausar,
                        icon: Icon(
                          tocando
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          size: 28,
                          color: cor,
                        ),
                      ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: fracao,
                        minHeight: 3.5,
                        backgroundColor: cor.withValues(alpha: 0.22),
                        valueColor: AlwaysStoppedAnimation<Color>(cor),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      tocando || andado > 0
                          ? '${_mmss(andado)} / ${widget.mensagem.audioDuracao}'
                          : widget.mensagem.audioDuracao,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 11,
                        color: fraca,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static String _mmss(int ms) {
    final t = (ms / 1000).round();
    return '${t ~/ 60}:${(t % 60).toString().padLeft(2, '0')}';
  }
}

class _Aviso extends StatelessWidget {
  final IconData icone;
  final String texto;
  final Color cor;

  const _Aviso({required this.icone, required this.texto, required this.cor});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 210,
      child: Row(
        children: [
          Icon(icone, size: 17, color: cor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              texto,
              style: TextStyle(
                  fontFamily: 'Poppins', fontSize: 12, height: 1.35, color: cor),
            ),
          ),
        ],
      ),
    );
  }
}

/// O botão de microfone: segurar para gravar, soltar para enviar, arrastar
/// para o lado para cancelar.
///
/// É o gesto do WhatsApp porque é o gesto que esta equipe já conhece — e
/// porque, segurando, ninguém manda áudio sem querer.
class BotaoDeVoz extends StatefulWidget {
  /// Chamado com o áudio pronto. A tela é quem envia.
  final Future<void> Function(AudioGravado) aoGravar;

  /// Avisa a tela para ela desenhar a tarja de "gravando", que ocupa o lugar
  /// do campo de texto. Fica na tela, e não aqui, porque é lá que há largura.
  final void Function(bool gravando, bool vaiCancelar, int ms) aoMudar;

  final bool isDark;

  const BotaoDeVoz({
    super.key,
    required this.aoGravar,
    required this.aoMudar,
    required this.isDark,
  });

  @override
  State<BotaoDeVoz> createState() => _BotaoDeVozState();
}

class _BotaoDeVozState extends State<BotaoDeVoz> {
  static const double _arrastoParaCancelar = 90;

  bool _gravando = false;
  bool _vaiCancelar = false;
  bool _enviando = false;
  int _ms = 0;
  Timer? _relogio;

  @override
  void dispose() {
    _relogio?.cancel();
    if (_gravando) gravarCancelar();
    super.dispose();
  }

  /// A explicação curta antes de o navegador pedir o microfone.
  ///
  /// O aviso do navegador aparece sem contexto nenhum, e quem não entende o
  /// que está sendo pedido toca em "não permitir" — e aí a permissão fica
  /// negada para sempre, sem caminho de volta dentro do app.
  Future<bool> _explicarSePreciso() async {
    if (LocalDaPermissao.jaExplicou) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Gravar um áudio'),
        content: const Text(
          'O aparelho vai perguntar se este app pode usar o microfone. '
          'Ele só grava enquanto você estiver segurando o botão.',
          style: TextStyle(fontFamily: 'Poppins', fontSize: 13.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Agora não'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.blue),
            child: const Text('Continuar'),
          ),
        ],
      ),
    );
    if (ok == true) LocalDaPermissao.jaExplicou = true;
    return ok == true;
  }

  Future<void> _comecar() async {
    if (_enviando) return;
    if (!await _explicarSePreciso()) return;
    if (!mounted) return;

    final r = await gravarIniciar();
    if (!mounted) return;
    if (r != 'ok') {
      final recado = switch (r) {
        'sem-permissao' => 'O microfone não foi liberado. Nas configurações '
            'do navegador, permita o microfone para este site.',
        'sem-suporte' => 'Este aparelho não grava áudio pelo navegador.',
        _ => 'Não foi possível começar a gravar.',
      };
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(recado), backgroundColor: AppColors.red),
      );
      return;
    }

    setState(() {
      _gravando = true;
      _vaiCancelar = false;
      _ms = 0;
    });
    widget.aoMudar(true, false, 0);
    _relogio = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!mounted) return;
      final agora = gravandoMs();
      // O próprio gravador para sozinho nos 2 minutos; aqui só se acompanha.
      if (agora == 0 && _gravando) {
        _terminar(cancelar: false);
        return;
      }
      setState(() => _ms = agora);
      widget.aoMudar(true, _vaiCancelar, agora);
    });
  }

  Future<void> _terminar({required bool cancelar}) async {
    _relogio?.cancel();
    if (!_gravando) return;
    setState(() => _gravando = false);
    widget.aoMudar(false, false, 0);

    if (cancelar) {
      gravarCancelar();
      return;
    }

    setState(() => _enviando = true);
    final audio = await gravarParar();
    if (!mounted) return;
    if (audio == null || audio.duracaoMs < 700) {
      // Toque curto demais: quase sempre é engano, e um áudio de meio
      // segundo só enche a conversa.
      setState(() => _enviando = false);
      return;
    }
    await widget.aoGravar(audio);
    if (mounted) setState(() => _enviando = false);
  }

  @override
  Widget build(BuildContext context) {
    final cor = _vaiCancelar ? AppColors.red : AppColors.blue;

    return GestureDetector(
      onLongPressStart: (_) => _comecar(),
      onLongPressMoveUpdate: (d) {
        if (!_gravando) return;
        final cancelar = d.localOffsetFromOrigin.dx < -_arrastoParaCancelar;
        if (cancelar != _vaiCancelar) {
          setState(() => _vaiCancelar = cancelar);
          widget.aoMudar(true, cancelar, _ms);
        }
      },
      onLongPressEnd: (_) => _terminar(cancelar: _vaiCancelar),
      onLongPressCancel: () => _terminar(cancelar: true),
      onTap: () {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Segure o microfone para gravar.'),
            duration: Duration(seconds: 2),
          ),
        );
      },
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: _gravando ? cor : AppColors.blue,
          shape: BoxShape.circle,
        ),
        child: _enviando
            ? const Padding(
                padding: EdgeInsets.all(13),
                child: CircularProgressIndicator(
                    strokeWidth: 2.4, color: Colors.white),
              )
            : Icon(
                _vaiCancelar ? Icons.delete_outline_rounded : Icons.mic_rounded,
                color: Colors.white,
                size: 23,
              ),
      ),
    );
  }

}

/// Se a explicação do microfone já foi mostrada neste aparelho.
///
/// Só na memória do app: mostrar de novo depois de um reinício não custa
/// nada, e guardar isso no aparelho seria mais um estado para manter.
class LocalDaPermissao {
  static bool jaExplicou = false;
}
