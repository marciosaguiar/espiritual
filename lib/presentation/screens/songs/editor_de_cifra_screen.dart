import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/chord_transposer.dart';
import '../../../core/utils/cifra_colada.dart';
import '../../../core/utils/mapa_da_musica.dart';
import '../../../data/services/local_storage_service.dart';
import '../../widgets/songs/colar_cifra.dart';

/// O editor de letra e cifra: uma tela, tela cheia, fonte de largura fixa.
///
/// POR QUE ELE EXISTE
///
/// "Editar música" não tinha onde mexer na letra nem na cifra. Dava para
/// corrigir o nome, o artista, o tom e o BPM — e a única maneira de arrumar
/// um verso errado era "Colar cifra" e colar tudo de novo, do zero. Quem
/// digitou uma palavra errada tinha de reescrever a música.
///
/// AS TRÊS COISAS QUE ELE FAZ E UM CAMPO COMUM NÃO FARIA
///
/// 1. **Largura fixa e tela cheia.** Cifra é texto alinhado: o acorde fica em
///    cima da sílaba em que se troca. Em fonte proporcional o alinhamento se
///    perde, e num campo de doze linhas a pessoa edita olhando por uma fresta.
/// 2. **Pré-visualizar, já transposto.** O que se escreve não é o que se lê:
///    a tela da música transpõe. Sem ver o resultado, um erro de acorde só
///    aparece no domingo, com a igreja de pé.
/// 3. **Rascunho no aparelho.** Arrumar uma cifra leva minutos, e a internet
///    de casa cai. Sem rascunho, a tela volta vazia e o trabalho se perde sem
///    nada avisar.
class EditorDeCifraScreen extends StatefulWidget {
  /// Para onde o rascunho é guardado. Vazio = cadastro de música nova, que
  /// ainda não tem id (aí o rascunho fica desligado: não há a que voltar).
  final String songId;

  final String musica;
  final String artista;

  /// O texto que já existe: a cifra da igreja, ou a letra quando não há cifra.
  final String inicial;

  /// O tom em que o texto está escrito, para a pré-visualização saber de onde
  /// transpor.
  final String tomDoTexto;

  const EditorDeCifraScreen({
    super.key,
    required this.musica,
    required this.artista,
    this.songId = '',
    this.inicial = '',
    this.tomDoTexto = 'C',
  });

  @override
  State<EditorDeCifraScreen> createState() => _EditorDeCifraScreenState();
}

class _EditorDeCifraScreenState extends State<EditorDeCifraScreen> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.inicial);

  /// Guardar a cada tecla seria escrever no disco centenas de vezes por
  /// minuto; um segundo depois da última tecla é imperceptível e seguro.
  static const _esperaDoRascunho = Duration(seconds: 1);
  Timer? _relogio;

  bool _previa = false;
  int _semitons = 0;
  String? _rascunhoOferecido;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_programarRascunho);

    // Havia um rascunho diferente do que está salvo? A pessoa decide; a tela
    // não troca o texto dela sozinha — ninguém gosta de ver a própria tela
    // mudar sem pedir.
    final r = LocalStorageService.rascunho(widget.songId);
    if (r != null && r.trim() != widget.inicial.trim()) {
      _rascunhoOferecido = r;
    }
  }

  @override
  void dispose() {
    _relogio?.cancel();
    _ctrl.removeListener(_programarRascunho);
    _ctrl.dispose();
    super.dispose();
  }

  void _programarRascunho() {
    if (widget.songId.isEmpty) return;
    _relogio?.cancel();
    _relogio = Timer(_esperaDoRascunho, () {
      LocalStorageService.salvarRascunho(widget.songId, _ctrl.text);
    });
  }

  void _usarRascunho() {
    final r = _rascunhoOferecido;
    if (r == null) return;
    setState(() {
      _ctrl.text = r;
      _rascunhoOferecido = null;
    });
  }

  void _descartarRascunho() {
    LocalStorageService.esquecerRascunho(widget.songId);
    setState(() => _rascunhoOferecido = null);
  }

  void _salvar() {
    final texto = _ctrl.text;
    if (texto.trim().isEmpty) {
      // Salvar vazio apagaria a letra da música inteira, e sem aviso. Quem
      // quer tirar a música do repertório tem outro caminho.
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Está vazio. Cole ou escreva a letra antes de salvar.'),
      ));
      return;
    }
    // O rascunho só morre depois de a tela de cima confirmar a gravação; aqui
    // ele é mantido de propósito.
    Navigator.pop(
      context,
      CifraColada.analisar(
        texto,
        nomeConhecido: widget.musica,
        artistaConhecido: widget.artista,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final analise = _ctrl.text.trim().isEmpty
        ? null
        : CifraColada.analisar(
            _ctrl.text,
            nomeConhecido: widget.musica,
            artistaConhecido: widget.artista,
          );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Letra e cifra'),
        actions: [
          TextButton(
            onPressed: _salvar,
            child: const Text('Salvar'),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_rascunhoOferecido != null)
                _FaixaDeRascunho(
                  isDark: isDark,
                  onUsar: _usarRascunho,
                  onDescartar: _descartarRascunho,
                ),
              _BarraDoEditor(
                isDark: isDark,
                previa: _previa,
                semitons: _semitons,
                onPrevia: () => setState(() => _previa = !_previa),
                onTransporMenos: () => setState(() => _semitons--),
                onTransporMais: () => setState(() => _semitons++),
                onBuscar: () => abrirBuscaCifraClub(
                    context, widget.musica, widget.artista),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _previa
                    ? _Previa(
                        texto: _ctrl.text,
                        semitons: _semitons,
                        isDark: isDark,
                      )
                    : _Campo(ctrl: _ctrl, isDark: isDark),
              ),
              if (analise != null)
                _Resumo(analise: analise, texto: _ctrl.text, isDark: isDark),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Você estava escrevendo algo aqui."
class _FaixaDeRascunho extends StatelessWidget {
  final bool isDark;
  final VoidCallback onUsar;
  final VoidCallback onDescartar;

  const _FaixaDeRascunho({
    required this.isDark,
    required this.onUsar,
    required this.onDescartar,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: isDark ? 0.18 : 0.14),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Você estava escrevendo algo aqui e não salvou.',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12.5,
                height: 1.35,
                color: isDark
                    ? AppColors.textPrimaryDark
                    : AppColors.textPrimaryLight,
              ),
            ),
          ),
          TextButton(onPressed: onUsar, child: const Text('Recuperar')),
          TextButton(onPressed: onDescartar, child: const Text('Descartar')),
        ],
      ),
    );
  }
}

class _BarraDoEditor extends StatelessWidget {
  final bool isDark;
  final bool previa;
  final int semitons;
  final VoidCallback onPrevia;
  final VoidCallback onTransporMenos;
  final VoidCallback onTransporMais;
  final VoidCallback onBuscar;

  const _BarraDoEditor({
    required this.isDark,
    required this.previa,
    required this.semitons,
    required this.onPrevia,
    required this.onTransporMenos,
    required this.onTransporMais,
    required this.onBuscar,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // "Pré-visualizar" / "Editar": um botão só, que troca de nome. Dois
        // botões aqui seriam dois estados para a pessoa manter na cabeça.
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onPrevia,
            icon: Icon(
                previa ? Icons.edit_outlined : Icons.visibility_outlined,
                size: 18),
            label: Text(previa ? 'Editar' : 'Pré-visualizar'),
          ),
        ),
        if (previa) ...[
          const SizedBox(width: 8),
          // Transpor na PRÉVIA, não no texto: o que se grava continua no tom
          // em que foi escrito. Transpor o texto gravado faria a próxima
          // pessoa editar uma cifra que ninguém escreveu.
          _Redondo(rotulo: '−', onTap: onTransporMenos, isDark: isDark),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              ChordTransposer.getTransposeDisplay(semitons),
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
          _Redondo(rotulo: '+', onTap: onTransporMais, isDark: isDark),
        ] else ...[
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Buscar no Cifra Club',
            icon: const Icon(Icons.open_in_new_rounded, size: 20),
            onPressed: onBuscar,
          ),
        ],
      ],
    );
  }
}

class _Redondo extends StatelessWidget {
  final String rotulo;
  final VoidCallback onTap;
  final bool isDark;

  const _Redondo({
    required this.rotulo,
    required this.onTap,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.05),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        // 40 px é o alvo de toque que o polegar acerta sem olhar.
        child: SizedBox(
          width: 40,
          height: 40,
          child: Center(
            child: Text(
              rotulo,
              style: TextStyle(
                fontSize: 19,
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

/// O campo de escrever: largura fixa, tela cheia, sem limite de linhas.
class _Campo extends StatelessWidget {
  final TextEditingController ctrl;
  final bool isDark;

  const _Campo({required this.ctrl, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: TextField(
        controller: ctrl,
        maxLines: null,
        expands: true,
        keyboardType: TextInputType.multiline,
        textInputAction: TextInputAction.newline,
        // Sem corretor nem maiúscula automática: os dois estragam cifra.
        // "G" vira "g", "Em" vira "Em." e o alinhamento se perde.
        autocorrect: false,
        enableSuggestions: false,
        textCapitalization: TextCapitalization.none,
        style: TextStyle(
          fontFamily: 'JetBrainsMono',
          fontSize: 13.5,
          height: 1.5,
          color: isDark
              ? AppColors.textPrimaryDark
              : AppColors.textPrimaryLight,
        ),
        decoration: const InputDecoration(
          border: InputBorder.none,
          hintText: 'Cole a cifra do Cifra Club aqui.\n\n'
              'Os acordes ficam em cima da sílaba certa, e a letra para quem '
              'canta sai sozinha.',
          hintStyle: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 13,
            height: 1.5,
          ),
        ),
      ),
    );
  }
}

/// Como vai ficar na tela da música, já transposto.
class _Previa extends StatelessWidget {
  final String texto;
  final int semitons;
  final bool isDark;

  const _Previa({
    required this.texto,
    required this.semitons,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final mostrado = semitons == 0
        ? texto
        : ChordTransposer.transposeText(texto, semitons);
    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.black26 : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.white12 : Colors.black12,
        ),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Text(
          mostrado,
          style: TextStyle(
            fontFamily: 'JetBrainsMono',
            fontSize: 13.5,
            height: 1.5,
            color: isDark
                ? AppColors.textPrimaryDark
                : AppColors.textPrimaryLight,
          ),
        ),
      ),
    );
  }
}

/// O que o app entendeu: acordes, tom, partes e tablatura.
///
/// Fica no pé da tela porque é conferência, não instrução: a pessoa olha
/// quando quer saber se o app entendeu, e o resto do tempo escreve.
class _Resumo extends StatelessWidget {
  final CifraColada analise;
  final String texto;
  final bool isDark;

  const _Resumo({
    required this.analise,
    required this.texto,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final mapa = MapaDaMusica.mapear(texto);
    final partes = mapa.partes.map((p) => p.nome).toSet().toList();
    final temTab = texto.split('\n').any(ehTablatura);

    final secundaria =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            analise.temAcordes
                ? '✓ ${analise.linhasDeAcordes} '
                    '${analise.linhasDeAcordes == 1 ? 'linha' : 'linhas'} de '
                    'acordes${analise.tom != null ? ' · tom ${analise.tom}' : ''}'
                : 'Nenhum acorde: vai entrar só como letra.',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: analise.temAcordes ? AppColors.success : secundaria,
            ),
          ),
          if (partes.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Partes reconhecidas: ${partes.join(' · ')}',
              style: TextStyle(
                  fontFamily: 'Poppins', fontSize: 11.5, color: secundaria),
            ),
          ],
          if (temTab) ...[
            const SizedBox(height: 4),
            Text(
              'Tem tablatura. Quem não toca violão pode esconder, no menu ⋯ '
              'da música.',
              style: TextStyle(
                  fontFamily: 'Poppins', fontSize: 11.5, color: secundaria),
            ),
          ],
        ],
      ),
    );
  }
}
