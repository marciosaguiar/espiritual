import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/chord_transposer.dart';
import '../../../core/utils/cifra_colada.dart';
import '../../../core/utils/mapa_da_musica.dart';
import '../../../data/models/arrangement_model.dart';
import '../../../data/models/song_model.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/app_text_field.dart';
import '../../widgets/common/glass.dart';
import 'editor_de_cifra_screen.dart';

/// O que a tela devolve: a música corrigida e o BPM.
///
/// O BPM vem separado porque ele NÃO é da música: é do arranjo — de como esta
/// igreja toca. Ver o modelo de três camadas no CLAUDE.md. Juntar os dois num
/// objeto só seria o começo de ter dois BPMs diferentes para a mesma música.
typedef EdicaoDeMusica = ({SongModel musica, int bpm, String? cifra});

/// Corrigir o cadastro de uma música: nome, artista, tom original, BPM, link
/// do YouTube e observações.
///
/// Antes disto, o menu ⋮ só oferecia "Colar cifra" e "Tirar do repertório" —
/// um nome digitado errado ficava errado para sempre, e a única saída era
/// cadastrar a música de novo e perder o histórico dos cultos em que ela foi
/// tocada.
class EditarMusicaScreen extends StatefulWidget {
  final SongModel musica;
  final ArrangementModel? arranjo;

  const EditarMusicaScreen({
    super.key,
    required this.musica,
    this.arranjo,
  });

  @override
  State<EditarMusicaScreen> createState() => _EditarMusicaScreenState();
}

class _EditarMusicaScreenState extends State<EditarMusicaScreen> {
  late final _nome = TextEditingController(text: widget.musica.name);
  late final _artista = TextEditingController(text: widget.musica.artist);
  late final _youtube =
      TextEditingController(text: widget.musica.videoUrl ?? '');
  late final _observacoes =
      TextEditingController(text: widget.musica.observacoes);
  late final _bpm = TextEditingController(
      text: (widget.arranjo?.bpm ?? 0) > 0 ? '${widget.arranjo!.bpm}' : '');

  late String _tom = ChordTransposer.allKeys.contains(widget.musica.originalKey)
      ? widget.musica.originalKey
      : 'C';

  String? _erro;

  /// O texto novo de letra e cifra, quando a pessoa mexeu nele.
  ///
  /// **Nulo é "não mexeu", e é diferente de vazio.** Vazio apagaria a letra
  /// da música; nulo deixa como está. Era este campo que faltava: dava para
  /// corrigir nome, artista, tom e BPM, e a única maneira de arrumar um verso
  /// errado era colar a música inteira de novo.
  String? _cifraNova;

  /// O que está gravado hoje: a cifra da igreja, ou a letra quando não há
  /// cifra.
  String get _textoAtual => widget.arranjo?.hasChords == true
      ? widget.arranjo!.chords
      : widget.musica.lyrics;

  /// O texto que vale agora na tela — o novo, se houver.
  String get _texto => _cifraNova ?? _textoAtual;

  Future<void> _abrirEditor() async {
    final r = await Navigator.push<CifraColada>(
      context,
      GlassPageRoute(
        builder: (_) => EditorDeCifraScreen(
          songId: widget.musica.id,
          musica: _nome.text.trim(),
          artista: _artista.text.trim(),
          inicial: _texto,
          tomDoTexto: widget.arranjo?.churchKey.isNotEmpty == true
              ? widget.arranjo!.churchKey
              : _tom,
        ),
      ),
    );
    if (r == null || !mounted) return;
    setState(() => _cifraNova = r.cifra.isNotEmpty ? r.cifra : r.letra);
  }

  @override
  void dispose() {
    _nome.dispose();
    _artista.dispose();
    _youtube.dispose();
    _observacoes.dispose();
    _bpm.dispose();
    super.dispose();
  }

  void _salvar() {
    final nome = _nome.text.trim();
    if (nome.length < 2) {
      setState(() => _erro = 'Escreva o nome da música.');
      return;
    }
    final url = _youtube.text.trim();
    if (url.isNotEmpty) {
      final uri = Uri.tryParse(url);
      // Endereço sem "https://" é o erro mais comum ao colar, e um link que
      // não abre não dá nenhum aviso: o botão simplesmente não faz nada.
      if (uri == null || !uri.isScheme('https') || uri.host.isEmpty) {
        setState(() => _erro =
            'O link do YouTube precisa começar com https:// — cole o '
            'endereço inteiro.');
        return;
      }
    }
    final bpm = int.tryParse(_bpm.text.trim()) ?? 0;
    if (_bpm.text.trim().isNotEmpty && (bpm < 30 || bpm > 300)) {
      setState(() => _erro = 'O BPM fica entre 30 e 300. Deixe vazio se não '
          'souber.');
      return;
    }

    Navigator.pop<EdicaoDeMusica>(context, (
      musica: widget.musica
          .comVideo(_youtube.text)
          .copyWith(
            name: nome,
            artist: _artista.text.trim(),
            originalKey: _tom,
            observacoes: _observacoes.text.trim(),
          ),
      bpm: bpm,
      cifra: _cifraNova,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(title: const Text('Editar música')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppTextField(
              label: 'Nome da música',
              controller: _nome,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 16),
            AppTextField(
              label: 'Artista',
              hint: 'Quem gravou',
              controller: _artista,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(child: _seletorDeTom(isDark)),
                const SizedBox(width: 12),
                Expanded(
                  child: AppTextField(
                    label: 'BPM (opcional)',
                    hint: 'Ex: 72',
                    controller: _bpm,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.next,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            AppTextField(
              label: 'Link do YouTube (opcional)',
              hint: 'https://youtube.com/...',
              controller: _youtube,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.next,
              prefixIcon: const Icon(Icons.play_circle_outline, size: 20),
            ),
            const SizedBox(height: 6),
            Text(
              'Vira um botão na tela da música e aparece no culto, para '
              'ensaiar antes.',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 11.5,
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondaryLight,
              ),
            ),
            const SizedBox(height: 16),
            _LinhaDeCifra(
              texto: _texto,
              mexeu: _cifraNova != null,
              isDark: isDark,
              onTap: _abrirEditor,
            ),
            const SizedBox(height: 16),
            // "Anotações da música", e não "Observações": o CULTO tem as
            // "Observações do culto", e as duas apareciam com o mesmo nome em
            // telas diferentes — uma é da música em qualquer culto, a outra é
            // daquele domingo.
            AppTextField(
              label: 'Anotações da música (opcional)',
              hint: 'Ex: entra sem bateria; repete o refrão três vezes',
              controller: _observacoes,
              maxLines: 4,
              textInputAction: TextInputAction.newline,
            ),
            if (_erro != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.red.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                  border:
                      Border.all(color: AppColors.red.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline_rounded,
                        color: AppColors.red, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _erro!,
                        style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 12.5,
                            height: 1.35,
                            color: AppColors.red),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 28),
            AppButton(label: 'Salvar', onPressed: _salvar),
          ],
        ),
      ),
    );
  }

  Widget _seletorDeTom(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Tom original',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: isDark
                ? AppColors.textSecondaryDark
                : AppColors.textSecondaryLight,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: isDark ? Colors.grey.shade900 : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark ? Colors.grey.shade700 : Colors.grey.shade200,
            ),
          ),
          child: DropdownButton<String>(
            value: _tom,
            isExpanded: true,
            underline: const SizedBox.shrink(),
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 15,
              color: isDark
                  ? AppColors.textPrimaryDark
                  : AppColors.textPrimaryLight,
            ),
            items: ChordTransposer.allKeys
                .map((k) => DropdownMenuItem(value: k, child: Text(k)))
                .toList(),
            onChanged: (v) {
              if (v != null) setState(() => _tom = v);
            },
          ),
        ),
      ],
    );
  }
}

/// A linha "Letra e cifra": diz o que está lá hoje e abre o editor.
///
/// Não é um campo de texto aqui dentro de propósito. Cifra é texto alinhado e
/// comprido: editá-la numa caixinha de doze linhas, no meio de um formulário,
/// é o que fazia o líder preferir colar tudo de novo a corrigir uma palavra.
class _LinhaDeCifra extends StatelessWidget {
  final String texto;
  final bool mexeu;
  final bool isDark;
  final VoidCallback onTap;

  const _LinhaDeCifra({
    required this.texto,
    required this.mexeu,
    required this.isDark,
    required this.onTap,
  });

  /// O que dizer sobre o que está gravado. Cada caso tem uma frase, porque
  /// "letra e cifra" vazio e "só a letra" levam a ações diferentes.
  String get _resumo {
    if (texto.trim().isEmpty) return 'Vazio — toque para colar a cifra';
    final r = CifraColada.analisar(texto);
    final partes = MapaDaMusica.mapear(texto).partes.length;
    if (!r.temAcordes) {
      return 'Só a letra, sem acordes'
          '${partes > 0 ? ' · $partes parte(s)' : ''}';
    }
    return 'Cifra com ${r.linhasDeAcordes} '
        '${r.linhasDeAcordes == 1 ? 'linha' : 'linhas'} de acordes'
        '${partes > 0 ? ' · $partes parte(s)' : ''}';
  }

  @override
  Widget build(BuildContext context) {
    final secundaria =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Letra e cifra',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: secundaria,
          ),
        ),
        const SizedBox(height: 6),
        Material(
          color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 13, 10, 13),
              child: Row(
                children: [
                  Icon(Icons.notes_rounded, size: 20, color: secundaria),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _resumo,
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? AppColors.textPrimaryDark
                                : AppColors.textPrimaryLight,
                          ),
                        ),
                        if (mexeu)
                          const Text(
                            'Alterado — salve abaixo para valer',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.warning,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: secundaria),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
