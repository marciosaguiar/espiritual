import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/songs_provider.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/app_text_field.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/models/song_model.dart';
import '../../../data/services/firestore_service.dart';
import '../../../core/utils/chord_transposer.dart';
import '../../../core/utils/cifra_colada.dart';
import '../../widgets/songs/colar_cifra.dart';

class AddSongScreen extends StatefulWidget {
  const AddSongScreen({super.key});

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
    final song = FirestoreService.createSongModel(
      name: _nameCtrl.text.trim(),
      artist: _artistCtrl.text.trim(),
      lyrics: colado.letra,
      originalKey: _selectedKey,
      links: link.isEmpty ? const [] : [SongLink(url: link)],
      addedBy: auth.user?.id,
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
        title: const Text('Nova Música'),
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppTextField(
                label: 'Nome da Música',
                hint: 'Ex: Digno és',
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
                  if (tom != null && tom != _selectedKey) {
                    setState(() => _selectedKey = tom);
                  }
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
