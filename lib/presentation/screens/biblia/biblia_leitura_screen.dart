import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/livros_biblia.dart';
import '../../../core/platform/compartilhar.dart';
import '../../../data/services/biblia_service.dart';
import '../../providers/biblia_provider.dart';

/// A leitura: versículos numerados, fonte ajustável, capítulo anterior e
/// próximo, e o crédito da tradução no rodapé — que não é enfeite, é o que a
/// licença da Bíblia Livre exige de quem distribui o texto.
class BibliaLeituraScreen extends StatefulWidget {
  final LivroBiblia livro;
  final int capitulo;

  const BibliaLeituraScreen({
    super.key,
    required this.livro,
    required this.capitulo,
  });

  @override
  State<BibliaLeituraScreen> createState() => _BibliaLeituraScreenState();
}

class _BibliaLeituraScreenState extends State<BibliaLeituraScreen> {
  late LivroBiblia _livro = widget.livro;
  late int _capitulo = widget.capitulo;
  final _rolagem = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _marcar());
  }

  @override
  void dispose() {
    _rolagem.dispose();
    super.dispose();
  }

  void _marcar() {
    if (!mounted) return;
    context.read<BibliaProvider>().marcarLeitura(_livro.sigla, _capitulo);
  }

  /// O capítulo seguinte pode estar no próximo livro — é assim que se lê a
  /// Bíblia, e parar no fim de Gênesis seria um beco sem saída.
  ({LivroBiblia livro, int capitulo})? _vizinho(int passo) {
    final t = context.read<BibliaProvider>().traducao;
    if (t == null) return null;

    final alvo = _capitulo + passo;
    if (alvo >= 1 && alvo <= t.quantosCapitulos(_livro.sigla)) {
      return (livro: _livro, capitulo: alvo);
    }

    final livros = t.livros;
    final i = livros.indexWhere((l) => l.sigla == _livro.sigla);
    if (i < 0) return null;
    final j = i + passo;
    if (j < 0 || j >= livros.length) return null;

    final outro = livros[j];
    final quantos = t.quantosCapitulos(outro.sigla);
    if (quantos == 0) return null;
    return (livro: outro, capitulo: passo > 0 ? 1 : quantos);
  }

  void _ir(int passo) {
    final destino = _vizinho(passo);
    if (destino == null) return;
    setState(() {
      _livro = destino.livro;
      _capitulo = destino.capitulo;
    });
    if (_rolagem.hasClients) _rolagem.jumpTo(0);
    _marcar();
  }

  String _referencia(int versiculo) =>
      '${_livro.nome} $_capitulo:$versiculo';

  Future<void> _versiculoTocado(int numero, String texto) async {
    final t = context.read<BibliaProvider>().traducao;
    final completo = '"$texto"\n${_referencia(numero)} (${t?.sigla ?? ''})';

    final acao = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _AcoesDoVersiculo(referencia: _referencia(numero)),
    );
    if (acao == null || !mounted) return;

    if (acao == 'compartilhar' && podeCompartilhar) {
      final foi = await compartilharTexto(completo);
      if (foi) return;
    }
    await Clipboard.setData(ClipboardData(text: completo));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${_referencia(numero)} copiado.'),
        backgroundColor: AppColors.success,
      ),
    );
  }

  Future<void> _abrirYouVersion() async {
    final uri = BibliaService.noYouVersion(_livro.sigla, _capitulo);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível abrir o navegador.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = context.watch<BibliaProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final corTexto =
        isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final versiculos = b.traducao?.versiculos(_livro.sigla, _capitulo) ??
        const <String>[];

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text('${_livro.nome} $_capitulo'),
        actions: [
          IconButton(
            tooltip: 'Diminuir a letra',
            onPressed: () => b.mudarFonte(b.fonte - 1),
            icon: const Icon(Icons.text_decrease_rounded),
          ),
          IconButton(
            tooltip: 'Aumentar a letra',
            onPressed: () => b.mudarFonte(b.fonte + 1),
            icon: const Icon(Icons.text_increase_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              controller: _rolagem,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              children: [
                for (var i = 0; i < versiculos.length; i++)
                  _Versiculo(
                    numero: i + 1,
                    texto: versiculos[i],
                    fonte: b.fonte,
                    cor: corTexto,
                    aoTocar: () => _versiculoTocado(i + 1, versiculos[i]),
                  ),
                const SizedBox(height: 24),
                _Creditos(traducao: b.traducao, isDark: isDark),
                const SizedBox(height: 12),
                Center(
                  child: TextButton.icon(
                    onPressed: _abrirYouVersion,
                    icon: const Icon(Icons.open_in_new_rounded, size: 17),
                    label: const Text('Abrir no YouVersion'),
                    style:
                        TextButton.styleFrom(foregroundColor: AppColors.blue),
                  ),
                ),
              ],
            ),
          ),
          _Navegacao(
            isDark: isDark,
            anterior: _vizinho(-1),
            proximo: _vizinho(1),
            aoIr: _ir,
          ),
        ],
      ),
    );
  }
}

class _Versiculo extends StatelessWidget {
  final int numero;
  final String texto;
  final double fonte;
  final Color cor;
  final VoidCallback aoTocar;

  const _Versiculo({
    required this.numero,
    required this.texto,
    required this.fonte,
    required this.cor,
    required this.aoTocar,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: aoTocar,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: '$numero ',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: fonte * 0.68,
                  fontWeight: FontWeight.w700,
                  color: AppColors.blue,
                ),
              ),
              TextSpan(
                text: texto,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: fonte,
                  height: 1.62,
                  color: cor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// O crédito da tradução. Para a Bíblia Livre não é cortesia: a licença
/// Creative Commons Atribuição exige que ele acompanhe o texto.
class _Creditos extends StatelessWidget {
  final Traducao? traducao;
  final bool isDark;

  const _Creditos({required this.traducao, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final t = traducao;
    if (t == null || t.credito.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.white.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        t.credito,
        style: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 10.5,
          height: 1.5,
          color: isDark
              ? AppColors.textSecondaryDark
              : AppColors.textSecondaryLight,
        ),
      ),
    );
  }
}

class _Navegacao extends StatelessWidget {
  final bool isDark;
  final ({LivroBiblia livro, int capitulo})? anterior;
  final ({LivroBiblia livro, int capitulo})? proximo;
  final void Function(int) aoIr;

  const _Navegacao({
    required this.isDark,
    required this.anterior,
    required this.proximo,
    required this.aoIr,
  });

  @override
  Widget build(BuildContext context) {
    String rotulo(({LivroBiblia livro, int capitulo})? d) =>
        d == null ? '' : '${d.livro.nome} ${d.capitulo}';

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: anterior == null ? null : () => aoIr(-1),
                icon: const Icon(Icons.chevron_left_rounded, size: 20),
                label: Text(
                  rotulo(anterior),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: proximo == null ? null : () => aoIr(1),
                iconAlignment: IconAlignment.end,
                icon: const Icon(Icons.chevron_right_rounded, size: 20),
                label: Text(
                  rotulo(proximo),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AcoesDoVersiculo extends StatelessWidget {
  final String referencia;
  const _AcoesDoVersiculo({required this.referencia});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final corTexto =
        isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF171C23) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Text(
            referencia,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: corTexto,
            ),
          ),
          const SizedBox(height: 8),
          if (podeCompartilhar)
            ListTile(
              leading: const Icon(Icons.ios_share_rounded,
                  color: AppColors.blue),
              title: Text('Compartilhar',
                  style: TextStyle(fontFamily: 'Poppins', color: corTexto)),
              onTap: () => Navigator.pop(context, 'compartilhar'),
            ),
          ListTile(
            leading: const Icon(Icons.copy_rounded, color: AppColors.blue),
            title: Text('Copiar com a referência',
                style: TextStyle(fontFamily: 'Poppins', color: corTexto)),
            onTap: () => Navigator.pop(context, 'copiar'),
          ),
        ],
      ),
    );
  }
}
