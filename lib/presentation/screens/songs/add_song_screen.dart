import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/songs_provider.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/app_text_field.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/hinarios.dart';
import '../../../data/models/song_model.dart';
import '../../../data/services/firestore_service.dart';
import '../../../core/utils/chord_transposer.dart';
import '../../../core/utils/cifra_colada.dart';
import '../../widgets/songs/colar_cifra.dart';

class AddSongScreen extends StatefulWidget {
  /// Quando o cadastro começou pelo teclado numérico de hinos, o hinário e o
  /// número vêm preenchidos daqui.
  ///
  /// Nulos significam "música comum", que é o caminho de sempre. O hino não
  /// é um tipo diferente de música: é a mesma música com dois campos a mais,
  /// e foi isso que deixou o hinário caber sem uma tela de cadastro própria.
  final Hinario? hinario;
  final int? numero;

  const AddSongScreen({super.key, this.hinario, this.numero});

  @override
  State<AddSongScreen> createState() => _AddSongScreenState();
}

class _AddSongScreenState extends State<AddSongScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _artistCtrl = TextEditingController();
  /// Campo único: cifra do Cifra Club como veio, ou só a letra.
  final _cifraCtrl = TextEditingController();
  final _youtubeCtrl = TextEditingController();
  String _selectedKey = 'C';
  bool _isSaving = false;

  /// É cadastro de hino com número? Exige os DOIS, como o modelo exige.
  bool get _ehHino => widget.hinario != null && widget.numero != null;

  @override
  void initState() {
    super.initState();
    // O artista de um hino é o hinário. Preenchido, e não fixo, porque o
    // líder pode querer pôr o autor de verdade do hino no lugar.
    if (_ehHino) _artistCtrl.text = widget.hinario!.nome;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _artistCtrl.dispose();
    _cifraCtrl.dispose();
    _youtubeCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _isSaving = true);

    final auth = context.read<AuthProvider>();
    final songs = context.read<SongsProvider>();

    // A letra pura sai da cifra; a cifra (com as quebras de linha intactas)
    // vira o arranjo da igreja. Sem acordes, o texto entra só como letra.
    final colado = CifraColada.analisar(_cifraCtrl.text);
    final link = _youtubeCtrl.text.trim();
    // A sigla e o número entram NO TÍTULO ("HC 15 · Sou Grato"), gerados num
    // lugar só. É isso que faz o hino se reconhecer na escala, no chat e no
    // lembrete da véspera sem que nenhuma dessas telas saiba o que é um
    // hinário. Quem ACHA o hino pelo número usa os campos, nunca o título.
    final nome = _ehHino
        ? widget.hinario!.tituloDe(widget.numero!, _nameCtrl.text)
        : _nameCtrl.text.trim();
    final song = FirestoreService.createSongModel(
      name: nome,
      artist: _artistCtrl.text.trim(),
      lyrics: colado.letra,
      originalKey: _selectedKey,
      links: link.isEmpty ? const [] : [SongLink(url: link)],
      addedBy: auth.user?.id,
      hinario: _ehHino ? widget.hinario!.id : '',
      numero: _ehHino ? widget.numero : null,
    );

    var error = await songs.addSong(song);

    // The chart is the church's arrangement, not part of the song itself, so
    // it is saved as the song's first arrangement.
    final chords = colado.temAcordes ? colado.cifra : '';
    if (error == null && chords.isNotEmpty) {
      final arranjo = await FirestoreService.saveArrangement(
        FirestoreService.createArrangementModel(
          songId: song.id,
          churchKey: _selectedKey,
          chords: chords,
          approvedBy: auth.user?.id,
        ),
      );
      // A música entrou; avisa que a cifra não, em vez de dar tudo por certo.
      if (!arranjo.success) {
        error = 'A música foi salva, mas a cifra não: ${arranjo.error}';
      }
    }

    if (!mounted) return;
    setState(() => _isSaving = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error ?? 'Música adicionada com sucesso!'),
        backgroundColor: error == null ? AppColors.success : AppColors.red,
        duration: Duration(seconds: error == null ? 2 : 6),
      ),
    );
    if (error == null) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(_ehHino
            ? 'Hino ${widget.numero} · ${widget.hinario!.sigla}'
            : 'Nova Música'),
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_ehHino) ...[
                _FichaDoHino(
                  hinario: widget.hinario!,
                  numero: widget.numero!,
                  isDark: isDark,
                ),
                const SizedBox(height: 16),
              ],
              AppTextField(
                label: _ehHino ? 'Nome do hino' : 'Nome da Música',
                hint: _ehHino ? 'Ex: Sou grato por seu amor' : 'Ex: Digno és',
                controller: _nameCtrl,
                textInputAction: TextInputAction.next,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Nome é obrigatório';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              AppTextField(
                label: 'Artista / Ministério',
                hint: 'Ex: Hillsong, Vineyard...',
                controller: _artistCtrl,
                textInputAction: TextInputAction.next,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Artista é obrigatório';
                  return null;
                },
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => abrirBuscaCifraClub(
                      context, _nameCtrl.text, _artistCtrl.text),
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: const Text('Buscar no Cifra Club'),
                ),
              ),
              const SizedBox(height: 16),
              // Key selector
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Tom Original',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textSecondaryLight,
                    ),
                  ),
                  const SizedBox(height: 8),
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
                      value: _selectedKey,
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
                          .map((k) => DropdownMenuItem(
                                value: k,
                                child: Text(k),
                              ))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setState(() => _selectedKey = v);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              PainelColarCifra(
                controller: _cifraCtrl,
                onAnalisar: (r) {
                  final tom = tomDaLista(r.tom);
                  setState(() {
                    if (tom != null && tom != _selectedKey) _selectedKey = tom;
                    // Título e artista só entram em campo VAZIO: aqui a
                    // pessoa está cadastrando, e sobrescrever o que ela
                    // acabou de digitar é pior que não ajudar.
                    if (_nameCtrl.text.trim().isEmpty && r.titulo != null) {
                      _nameCtrl.text = r.titulo!;
                    }
                    if (_artistCtrl.text.trim().isEmpty && r.artista != null) {
                      _artistCtrl.text = r.artista!;
                    }
                  });
                },
              ),
              const SizedBox(height: 16),
              AppTextField(
                label: 'Link do YouTube (opcional)',
                hint: 'https://youtube.com/...',
                controller: _youtubeCtrl,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.done,
                prefixIcon: const Icon(Icons.play_circle_outline, size: 20),
              ),
              const SizedBox(height: 32),
              AppButton(
                label: 'Salvar Música',
                isLoading: _isSaving,
                onPressed: _save,
                icon: const Icon(Icons.save_rounded, size: 18, color: Colors.white),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}

/// A ficha do hino no alto do cadastro: diz de qual hinário e qual número é.
///
/// Não é editável de propósito. Quem chegou aqui pelo teclado numérico já
/// disse o número; oferecer o campo de novo só criaria a chance de cadastrar
/// o 15 como 150 e nunca mais achá-lo.
class _FichaDoHino extends StatelessWidget {
  final Hinario hinario;
  final int numero;
  final bool isDark;

  const _FichaDoHino({
    required this.hinario,
    required this.numero,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.blue.withOpacity(isDark ? 0.18 : 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Text(
            '${hinario.sigla} $numero',
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.blue,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Hino $numero da ${hinario.nome}. Cole a cifra do hinário da '
              'igreja abaixo.',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12.5,
                height: 1.4,
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondaryLight,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
