import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/songs_provider.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/app_text_field.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../data/services/firestore_service.dart';
import '../../../core/utils/chord_transposer.dart';

class AddSongScreen extends StatefulWidget {
  const AddSongScreen({super.key});

  @override
  State<AddSongScreen> createState() => _AddSongScreenState();
}

class _AddSongScreenState extends State<AddSongScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _artistCtrl = TextEditingController();
  final _lyricsCtrl = TextEditingController();
  final _chordsCtrl = TextEditingController();
  final _youtubeCtrl = TextEditingController();
  String _selectedKey = 'C';
  bool _isSaving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _artistCtrl.dispose();
    _lyricsCtrl.dispose();
    _chordsCtrl.dispose();
    _youtubeCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _isSaving = true);

    final auth = context.read<AuthProvider>();
    final songs = context.read<SongsProvider>();

    final song = FirestoreService.createSongModel(
      name: _nameCtrl.text.trim(),
      artist: _artistCtrl.text.trim(),
      lyrics: _lyricsCtrl.text.trim(),
      chords: _chordsCtrl.text.trim(),
      originalKey: _selectedKey,
      youtubeUrl: _youtubeCtrl.text.trim().isEmpty
          ? null
          : _youtubeCtrl.text.trim(),
      addedBy: auth.user?.id,
    );

    final success = await songs.addSong(song);
    if (mounted) {
      setState(() => _isSaving = false);
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Música adicionada com sucesso!'),
            backgroundColor: AppColors.success,
          ),
        );
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(AppStrings.errorGeneric),
            backgroundColor: AppColors.red,
          ),
        );
      }
    }
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
              AppTextField(
                label: 'Letra',
                hint: 'Cole a letra aqui...',
                controller: _lyricsCtrl,
                maxLines: 8,
                textInputAction: TextInputAction.newline,
              ),
              const SizedBox(height: 16),
              AppTextField(
                label: 'Cifra (opcional)',
                hint: 'Cole a cifra com acordes...',
                controller: _chordsCtrl,
                maxLines: 8,
                textInputAction: TextInputAction.newline,
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
