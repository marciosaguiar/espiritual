import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/chord_transposer.dart';
import '../../../core/utils/cifra_colada.dart';
import '../../../data/services/local_storage_service.dart';
import '../common/app_text_field.dart';

/// Abre a busca do Cifra Club no navegador com o nome já digitado. O app não
/// lê nada do site: só abre a página para a pessoa copiar a cifra.
Future<void> abrirBuscaCifraClub(
  BuildContext context,
  String musica, [
  String artista = '',
]) async {
  if (musica.trim().isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Digite o nome da música primeiro.')),
    );
    return;
  }
  // A marca é o que faz a faixa "usar a cifra copiada" aparecer quando a
  // pessoa voltar. Fica ANTES de abrir: se o navegador não abrir, a marca
  // some sozinha em 30 minutos e não custa nada.
  await LocalStorageService.marcarIdaAoCifraClub(musica.trim());
  final ok = await launchUrl(
    CifraColada.buscaNoCifraClub(musica, artista),
    mode: LaunchMode.externalApplication,
  );
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Não consegui abrir o navegador.')),
    );
  }
}

/// Tom da cifra no formato da lista de tons (que só tem tons maiores):
/// "Bm" vira "B". Nulo se não reconhecer.
String? tomDaLista(String? tom) {
  if (tom == null) return null;
  final raiz = tom.endsWith('m') ? tom.substring(0, tom.length - 1) : tom;
  return ChordTransposer.allKeys.contains(raiz) ? raiz : null;
}

/// Campo único "Colar cifra": recebe o texto do Cifra Club como veio,
/// mantém as quebras de linha e mostra, ao vivo, o que o app entendeu — o tom,
/// quantas linhas de acordes e a letra pura que quem canta vai ver.
class PainelColarCifra extends StatefulWidget {
  final TextEditingController controller;
  final ValueChanged<CifraColada>? onAnalisar;

  /// O nome e o artista que a música JÁ tem, quando ela já existe.
  ///
  /// Com eles, tirar o título do corpo da cifra é comparação em vez de
  /// adivinhação — ver `CifraColada._lerCabecalho`.
  final String? nomeConhecido;
  final String? artistaConhecido;

  const PainelColarCifra({
    super.key,
    required this.controller,
    this.onAnalisar,
    this.nomeConhecido,
    this.artistaConhecido,
  });

  @override
  State<PainelColarCifra> createState() => _PainelColarCifraState();
}

class _PainelColarCifraState extends State<PainelColarCifra> {
  CifraColada? _r;
  bool _verLetra = false;

  @override
  void initState() {
    super.initState();
    _analisar(widget.controller.text, avisar: false);
  }

  void _analisar(String texto, {bool avisar = true}) {
    final r = texto.trim().isEmpty
        ? null
        : CifraColada.analisar(
            texto,
            nomeConhecido: widget.nomeConhecido,
            artistaConhecido: widget.artistaConhecido,
          );
    setState(() => _r = r);
    if (avisar && r != null) widget.onAnalisar?.call(r);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final r = _r;
    final secundaria =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppTextField(
          label: 'Colar cifra (ou só a letra)',
          hint: 'Copie a cifra inteira no Cifra Club e cole aqui.\n'
              'Os acordes ficam para quem toca e a letra sai sozinha.',
          controller: widget.controller,
          maxLines: 12,
          monospace: true,
          textInputAction: TextInputAction.newline,
          onChanged: _analisar,
        ),
        if (r != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.blue.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r.temAcordes
                      ? '✓ Cifra reconhecida: ${r.linhasDeAcordes} '
                          '${r.linhasDeAcordes == 1 ? 'linha' : 'linhas'} de acordes'
                          '${r.tom != null ? ' · tom ${r.tom}' : ''}'
                      : 'Nenhum acorde encontrado: vai entrar só como letra.',
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.blue,
                  ),
                ),
                if (r.artista != null || r.titulo != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    'Cabeçalho do site retirado'
                    '${r.artista != null ? ' · artista: ${r.artista}' : ''}',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 11.5,
                      color: secundaria,
                    ),
                  ),
                ],
                if (r.temAcordes) ...[
                  const SizedBox(height: 4),
                  GestureDetector(
                    onTap: () => setState(() => _verLetra = !_verLetra),
                    child: Text(
                      _verLetra
                          ? 'Esconder a letra de quem canta ▲'
                          : 'Ver a letra que quem canta vai ver ▼',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12,
                        color: secundaria,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                  if (_verLetra) ...[
                    const SizedBox(height: 8),
                    Text(
                      r.letra,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 13,
                        height: 1.6,
                        color: isDark
                            ? AppColors.textPrimaryDark
                            : AppColors.textPrimaryLight,
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Tela para o líder colar (de novo) a cifra de uma música que já existe.
/// Devolve o resultado da análise, ou nulo se a pessoa desistir.
class ColarCifraScreen extends StatefulWidget {
  final String musica;
  final String artista;
  final String inicial;

  const ColarCifraScreen({
    super.key,
    required this.musica,
    required this.artista,
    this.inicial = '',
  });

  @override
  State<ColarCifraScreen> createState() => _ColarCifraScreenState();
}

class _ColarCifraScreenState extends State<ColarCifraScreen> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.inicial);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Colar cifra'),
        actions: [
          TextButton(
            onPressed: () {
              if (_ctrl.text.trim().isEmpty) return;
              Navigator.pop(
                context,
                CifraColada.analisar(
                  _ctrl.text,
                  nomeConhecido: widget.musica,
                  artistaConhecido: widget.artista,
                ),
              );
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OutlinedButton.icon(
              onPressed: () =>
                  abrirBuscaCifraClub(context, widget.musica, widget.artista),
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              label: const Text('Buscar no Cifra Club'),
            ),
            const SizedBox(height: 16),
            PainelColarCifra(
              controller: _ctrl,
              nomeConhecido: widget.musica,
              artistaConhecido: widget.artista,
            ),
            const SizedBox(height: 12),
            const Text(
              'Ao salvar, a cifra vira a da igreja e a letra da música é '
              'trocada pela letra pura tirada dela.',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
