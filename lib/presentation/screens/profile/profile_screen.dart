import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/songs_provider.dart';
import '../../providers/theme_provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/chord_transposer.dart';
import '../../../core/constants/app_strings.dart';
import '../../../data/models/user_model.dart';
import '../../../core/platform/install.dart';
import '../../../data/services/auth_service.dart';
import '../../../data/services/avisos_service.dart';
import '../../../data/services/firestore_service.dart';
import '../../providers/agenda_provider.dart';
import '../../providers/scale_provider.dart';
import '../songs/song_detail_screen.dart';
import '../biblia/biblia_screen.dart';
import 'fixed_schedule_screen.dart';
import 'members_screen.dart';
import 'teams_screen.dart';
import '../../widgets/common/glass.dart';
import '../../widgets/common/install_banner.dart';
import '../../widgets/common/selecao_de_funcoes.dart';
import '../../widgets/common/recuperacao_por_email.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _isEditing = false;
  List<UserInstrument>? _editFuncoes;

  void _showHelpSheet(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? AppColors.surfaceDark : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        const items = [
          (Icons.home_rounded, 'Início',
              'Versículo do dia, próximo culto e atalhos rápidos.'),
          (Icons.music_note_rounded, 'Músicas',
              'Busque cifras, transponha o tom e salve offline.'),
          (Icons.calendar_month_rounded, 'Escala',
              'Veja os cultos, confirme presença e monte o repertório.'),
          (Icons.chat_bubble_rounded, 'Chat',
              'Converse com o ministério e compartilhe músicas.'),
          (Icons.person_rounded, 'Perfil',
              'Seu instrumento, favoritas, tons salvos e o tema.'),
        ];
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade400,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Como usar o ${AppStrings.appName}',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? AppColors.textPrimaryDark
                        : AppColors.textPrimaryLight,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Um guia rápido das 5 áreas do app:',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13,
                    color: isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondaryLight,
                  ),
                ),
                const SizedBox(height: 16),
                ...items.map(
                  (it) => Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: AppColors.blue.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child:
                              Icon(it.$1, color: AppColors.blue, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                it.$2,
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: isDark
                                      ? AppColors.textPrimaryDark
                                      : AppColors.textPrimaryLight,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                it.$3,
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 12,
                                  height: 1.3,
                                  color: isDark
                                      ? AppColors.textSecondaryDark
                                      : AppColors.textSecondaryLight,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.blue,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('Entendi'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showChangePasswordSheet(
      BuildContext context, UserModel user) async {
    final formKey = GlobalKey<FormState>();
    final atualCtrl = TextEditingController();
    final novaCtrl = TextEditingController();
    final confirmaCtrl = TextEditingController();
    var salvando = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: const Text('Alterar minha senha'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: atualCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Senha atual'),
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'Informe a senha atual' : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: novaCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Nova senha',
                    hintText: 'Mínimo 6 caracteres',
                  ),
                  validator: (v) =>
                      (v == null || v.length < AuthService.minPasswordLength)
                          ? 'Mínimo ${AuthService.minPasswordLength} caracteres'
                          : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: confirmaCtrl,
                  obscureText: true,
                  decoration:
                      const InputDecoration(labelText: 'Repita a nova senha'),
                  validator: (v) =>
                      v != novaCtrl.text ? 'As senhas não coincidem' : null,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: salvando ? null : () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: salvando
                  ? null
                  : () async {
                      if (!(formKey.currentState?.validate() ?? false)) return;
                      setDialog(() => salvando = true);

                      final result = await AuthService.changePassword(
                        user: user,
                        currentPassword: atualCtrl.text,
                        newPassword: novaCtrl.text,
                      );

                      if (!ctx.mounted) return;
                      setDialog(() => salvando = false);

                      if (result.success) {
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Senha alterada!'),
                            backgroundColor: AppColors.success,
                          ),
                        );
                      } else {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(
                            content: Text(result.error ??
                                'Não foi possível alterar a senha.'),
                            backgroundColor: AppColors.red,
                          ),
                        );
                      }
                    },
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.blue),
              child: salvando
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Salvar'),
            ),
          ],
        ),
      ),
    );

    atualCtrl.dispose();
    novaCtrl.dispose();
    confirmaCtrl.dispose();
  }

  void _showAboutSheet(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: AppStrings.appName,
      applicationVersion: 'Versão 1.0.0',
      applicationIcon: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          gradient: AppColors.primaryGradient,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.music_note_rounded, color: Colors.white),
      ),
      children: const [
        SizedBox(height: 8),
        Text(
          'O super app do ministério de louvor: músicas com cifras, '
          'escalas, chat e organização — tudo em um só lugar.',
          style: TextStyle(fontFamily: 'Poppins', fontSize: 13, height: 1.4),
        ),
        SizedBox(height: 12),
        Text(
          'Feito com ❤️ para a glória de Deus.',
          style: TextStyle(fontFamily: 'Poppins', fontSize: 12),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final songs = context.watch<SongsProvider>();
    final theme = context.watch<ThemeProvider>();
    final user = auth.user;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (user == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final favoriteSongs = songs.repertorio
        .where((s) => user.favoriteSongs.contains(s.id))
        .toList();

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // Profile header
          SliverAppBar(
            expandedHeight: 240,
            pinned: true,
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            flexibleSpace: Stack(
              fit: StackFit.expand,
              children: [
                // Frosted glass that shows once the gradient header collapses.
                ClipRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
                    child: Container(
                      color: isDark
                          ? const Color(0x8C141019)
                          : Colors.white.withOpacity(0.55),
                    ),
                  ),
                ),
                FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: AppColors.primaryGradient,
                ),
                child: SafeArea(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 20),
                      // Avatar
                      Stack(
                        children: [
                          CircleAvatar(
                            radius: 48,
                            backgroundColor: Colors.white.withOpacity(0.3),
                            child: Text(
                              user.name[0].toUpperCase(),
                              style: const TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 36,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        user.name,
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              user.isAdmin ? '👑 ${user.role.label}' : '🎵 ${user.role.label}',
                              style: const TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 12,
                                color: Colors.white,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '${user.instrument.emoji} ${user.instrument.label}',
                              style: const TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 12,
                                color: Colors.white,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
              ],
            ),
            actions: [
              IconButton(
                tooltip: _isEditing ? 'Salvar alterações' : 'Editar perfil',
                icon: Icon(_isEditing ? Icons.check_rounded : Icons.edit_rounded),
                color: isDark ? Colors.white : AppColors.textPrimaryLight,
                onPressed: () async {
                  if (_isEditing && _editFuncoes != null) {
                    await auth.updateProfile(instruments: _editFuncoes);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Perfil atualizado!'),
                          backgroundColor: AppColors.success,
                        ),
                      );
                    }
                  }
                  setState(() {
                    _isEditing = !_isEditing;
                    _editFuncoes = List.of(user.instruments);
                  });
                },
              ),
            ],
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Edit instrument
                  if (_isEditing) ...[
                    const Text(
                      'Instrumento',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Escolha seu instrumento e toque em ✓ para salvar',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12,
                        color: isDark
                            ? AppColors.textSecondaryDark
                            : AppColors.textSecondaryLight,
                      ),
                    ),
                    const SizedBox(height: 10),
                    SelecaoDeFuncoes(
                      funcoes: _editFuncoes ?? const [],
                      isDark: isDark,
                      aoMudar: (f) => setState(() => _editFuncoes = f),
                    ),
                    const SizedBox(height: 20),
                  ],

                  // Cantor x músico: muda o que a tela da música mostra.
                  _EscolhaLeitura(
                    atual: user.modoLeitura,
                    onEscolher: (m) async {
                      final ok = await auth.updateProfile(leitura: m);
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(ok
                              ? (m == ModoLeitura.canto
                                  ? 'Pronto: nas músicas você verá só a letra, grande.'
                                  : 'Pronto: nas músicas você verá a cifra no seu tom.')
                              : 'Não deu para salvar. Confira a internet.'),
                          backgroundColor:
                              ok ? AppColors.success : AppColors.red,
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 20),

                  // Stats cards
                  Row(
                    children: [
                      _StatCard(
                        label: 'Favoritas',
                        value: '${user.favoriteSongs.length}',
                        icon: Icons.favorite_rounded,
                        color: AppColors.red,
                      ),
                      const SizedBox(width: 12),
                      _StatCard(
                        label: 'Tons Salvos',
                        value: '${auth.songPrefs.length}',
                        icon: Icons.music_note_rounded,
                        color: AppColors.blue,
                      ),
                      const SizedBox(width: 12),
                      _StatCard(
                        label: 'Offline',
                        value: '${songs.offlineCount}',
                        icon: Icons.download_done_rounded,
                        color: AppColors.success,
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Settings group
                  Text(
                    'Configurações',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? AppColors.textPrimaryDark
                          : AppColors.textPrimaryLight,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _SettingRow(
                    icon: isDark
                        ? Icons.light_mode_rounded
                        : Icons.dark_mode_rounded,
                    label: isDark ? 'Modo Claro' : 'Modo Escuro',
                    trailing: Switch(
                      value: isDark,
                      onChanged: (_) => theme.toggleTheme(),
                      activeColor: AppColors.blue,
                    ),
                    onTap: () => theme.toggleTheme(),
                  ),
                  // "Instalar o app" só aparece para quem ainda não
                  // instalou — e no iPhone é o que destrava os avisos.
                  if (caminhoDeInstalacao != InstallRoute.naoSeAplica) ...[
                    const SizedBox(height: 8),
                    _SettingRow(
                      icon: Icons.add_to_home_screen_rounded,
                      label: 'Instalar o app no celular',
                      trailing: const Icon(Icons.chevron_right_rounded,
                          color: AppColors.textSecondaryLight),
                      onTap: () => mostrarComoInstalar(context),
                    ),
                  ],
                  const SizedBox(height: 8),
                  const _AvisosDoApp(),
                  const SizedBox(height: 8),
                  _SettingRow(
                    icon: Icons.menu_book_rounded,
                    label: 'Bíblia',
                    trailing: const Icon(Icons.chevron_right_rounded,
                        color: AppColors.textSecondaryLight),
                    onTap: () => Navigator.push(
                      context,
                      GlassPageRoute(builder: (_) => const BibliaScreen()),
                    ),
                  ),
                  if (auth.isAdmin) ...[
                    const SizedBox(height: 8),
                    _SettingRow(
                      icon: Icons.groups_rounded,
                      label: 'Membros do ministério',
                      trailing: const _SeloPendentes(),
                      onTap: () => Navigator.push(
                        context,
                        GlassPageRoute(
                            builder: (_) => const MembersScreen()),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _SettingRow(
                      icon: Icons.event_repeat_rounded,
                      label: 'Agenda fixa',
                      trailing: const Icon(Icons.chevron_right_rounded,
                          color: AppColors.textSecondaryLight),
                      onTap: () => Navigator.push(
                        context,
                        GlassPageRoute(
                            builder: (_) => const FixedScheduleScreen()),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _SettingRow(
                      icon: Icons.diversity_3_rounded,
                      label: 'Equipes',
                      trailing: const Icon(Icons.chevron_right_rounded,
                          color: AppColors.textSecondaryLight),
                      onTap: () => Navigator.push(
                        context,
                        GlassPageRoute(builder: (_) => const TeamsScreen()),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  // Vem ANTES de "Alterar minha senha" de propósito: esta é a
                  // que a pessoa precisa ter feito antes de precisar dela.
                  // Sem e-mail cadastrado, senha esquecida é acesso perdido —
                  // não existe quem destrave depois, nem o líder.
                  _SettingRow(
                    icon: user.recuperacaoPorEmail
                        ? Icons.verified_user_outlined
                        : Icons.shield_outlined,
                    label: 'Recuperar a senha',
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          user.recuperacaoPorEmail
                              ? 'Pronto'
                              : 'Falta cadastrar',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: user.recuperacaoPorEmail
                                ? AppColors.success
                                : AppColors.red,
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded,
                            color: AppColors.textSecondaryLight),
                      ],
                    ),
                    onTap: () => mostrarRecuperacaoPorEmail(context),
                  ),
                  const SizedBox(height: 8),
                  _SettingRow(
                    icon: Icons.key_outlined,
                    label: 'Alterar minha senha',
                    trailing: const Icon(Icons.chevron_right_rounded,
                        color: AppColors.textSecondaryLight),
                    onTap: () => _showChangePasswordSheet(context, user),
                  ),
                  const SizedBox(height: 8),
                  _SettingRow(
                    icon: Icons.help_outline_rounded,
                    label: 'Como usar o app',
                    trailing: const Icon(Icons.chevron_right_rounded,
                        color: AppColors.textSecondaryLight),
                    onTap: () => _showHelpSheet(context),
                  ),
                  const SizedBox(height: 8),
                  _SettingRow(
                    icon: Icons.info_outline_rounded,
                    label: 'Sobre o ${AppStrings.appName}',
                    trailing: const Icon(Icons.chevron_right_rounded,
                        color: AppColors.textSecondaryLight),
                    onTap: () => _showAboutSheet(context),
                  ),

                  const SizedBox(height: 8),

                  // Saved tones
                  if (auth.songPrefs.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      AppStrings.savedTones,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? AppColors.textPrimaryDark
                            : AppColors.textPrimaryLight,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ...auth.songPrefs.entries.map((e) {
                      final song = songs.getSongById(e.key);
                      if (song == null) return const SizedBox.shrink();
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isDark ? AppColors.cardDark : AppColors.cardLight,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isDark
                                ? Colors.grey.shade800
                                : Colors.grey.shade100,
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                song.name,
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 13,
                                  color: isDark
                                      ? AppColors.textPrimaryDark
                                      : AppColors.textPrimaryLight,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppColors.blue.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                // O tom em que a pessoa toca, não o
                                // deslocamento: "+2" não diz nada para quem
                                // canta, "D → E" diz.
                                '${song.originalKey} → '
                                '${ChordTransposer.getKeyName(song.originalKey, e.value.semitones)}',
                                style: const TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.blue,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],

                  // Favorites
                  if (favoriteSongs.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Text(
                      AppStrings.myFavorites,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? AppColors.textPrimaryDark
                            : AppColors.textPrimaryLight,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ...favoriteSongs.map((song) {
                      return GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            GlassPageRoute(
                              builder: (_) => SongDetailScreen(song: song),
                            ),
                          );
                        },
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isDark ? AppColors.cardDark : AppColors.cardLight,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isDark
                                  ? Colors.grey.shade800
                                  : Colors.grey.shade100,
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.favorite_rounded,
                                  size: 18, color: AppColors.red),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      song.name,
                                      style: TextStyle(
                                        fontFamily: 'Poppins',
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: isDark
                                            ? AppColors.textPrimaryDark
                                            : AppColors.textPrimaryLight,
                                      ),
                                    ),
                                    Text(
                                      song.artist,
                                      style: const TextStyle(
                                        fontFamily: 'Poppins',
                                        fontSize: 11,
                                        color: AppColors.textSecondaryLight,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 3),
                                decoration: BoxDecoration(
                                  color: AppColors.blue.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  song.originalKey,
                                  style: const TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.blue,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],

                  // Favorites empty hint
                  if (favoriteSongs.isEmpty) ...[
                    const SizedBox(height: 20),
                    Text(
                      AppStrings.myFavorites,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? AppColors.textPrimaryDark
                            : AppColors.textPrimaryLight,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isDark ? AppColors.cardDark : AppColors.cardLight,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color:
                              isDark ? Colors.grey.shade800 : Colors.grey.shade100,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.favorite_border_rounded,
                              size: 20,
                              color: isDark
                                  ? AppColors.textSecondaryDark
                                  : AppColors.textSecondaryLight),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Toque no ♥ em uma música para salvá-la nas favoritas.',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 12.5,
                                color: isDark
                                    ? AppColors.textSecondaryDark
                                    : AppColors.textSecondaryLight,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 28),

                  // Sair do MINISTÉRIO — diferente de sair da conta, e por
                  // isso vem antes e com outra cara. Quem toca em "Sair da
                  // conta" quer voltar depois; quem toca aqui, não.
                  const _SairDoMinisterio(),
                  const SizedBox(height: 10),

                  // Logout
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (_) => AlertDialog(
                            title: const Text('Sair da conta'),
                            content: const Text(
                                'Deseja realmente sair da sua conta?'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('Cancelar'),
                              ),
                              ElevatedButton(
                                onPressed: () => Navigator.pop(context, true),
                                style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.red),
                                child: const Text('Sair'),
                              ),
                            ],
                          ),
                        );
                        if (confirm == true && mounted) {
                          await auth.logout();
                        }
                      },
                      icon: const Icon(Icons.logout_rounded,
                          color: AppColors.red, size: 18),
                      label: const Text(
                        AppStrings.logout,
                        style: TextStyle(
                          color: AppColors.red,
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppColors.red),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 100),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.18)),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.10),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 10,
                color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Sair do ministério": a própria pessoa revoga o próprio acesso.
///
/// Existe porque sair não deveria depender de pedir a alguém. O efeito é o
/// mesmo de ser removido pelo líder, com uma diferença registrada no banco:
/// `removedBy` é a própria pessoa, e a lista de removidos mostra isso.
///
/// O último líder não sai: o ministério ficaria sem ninguém capaz de aprovar
/// membro, criar culto ou devolver acesso — nem de desfazer a saída.
class _SairDoMinisterio extends StatefulWidget {
  const _SairDoMinisterio();

  @override
  State<_SairDoMinisterio> createState() => _SairDoMinisterioState();
}

class _SairDoMinisterioState extends State<_SairDoMinisterio> {
  bool _saindo = false;

  Future<void> _sair() async {
    final auth = context.read<AuthProvider>();
    final eu = auth.user;
    if (eu == null) return;

    if (eu.isAdmin && await AuthService.adminCount() <= 1) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('O ministério precisa de pelo menos um líder. '
              'Promova outra pessoa antes de sair.'),
          backgroundColor: AppColors.red,
        ),
      );
      return;
    }
    if (!mounted) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sair do ministério?'),
        content: const Text(
          'Você perde o acesso ao chat, às escalas e às músicas, e sai das '
          'equipes e dos próximos cultos. Sua conta continua existindo: se '
          'mudar de ideia, um líder devolve o seu acesso.',
          style: TextStyle(fontFamily: 'Poppins', fontSize: 13.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.red),
            child: const Text('Sair do ministério'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final equipes = context.read<AgendaProvider>().teams;
    final escalas = context.read<ScaleProvider>().scales;

    setState(() => _saindo = true);
    final r = await FirestoreService.removerDoMinisterio(
      alvo: eu,
      porQuemId: eu.id,
      equipes: equipes,
      escalas: escalas,
    );
    if (!mounted) return;
    setState(() => _saindo = false);

    // Deu certo? A tela some sozinha: o provider escuta o próprio cadastro e
    // o app troca para a tela de quem está fora. Só o erro precisa de aviso.
    if (!r.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(r.error ?? 'Não foi possível sair do ministério.'),
          backgroundColor: AppColors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: TextButton.icon(
        onPressed: _saindo ? null : _sair,
        icon: _saindo
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.person_remove_outlined,
                size: 18, color: AppColors.textSecondaryLight),
        label: const Text(
          'Sair do ministério',
          style: TextStyle(
            color: AppColors.textSecondaryLight,
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w600,
          ),
        ),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 13),
        ),
      ),
    );
  }
}

/// Quantos esperam aprovação, ao lado de "Membros do ministério".
///
/// Fica numa consulta filtrada por `role == 'pendente'`: o resultado quase
/// sempre vem vazio e não custa a lista inteira de membros. Enquanto não há
/// ninguém esperando, é só a seta de sempre.
class _SeloPendentes extends StatelessWidget {
  const _SeloPendentes();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<UserModel>>(
      stream: AuthService.watchPendentes(),
      builder: (context, snap) {
        final n = snap.data?.length ?? 0;
        if (n == 0) {
          return const Icon(Icons.chevron_right_rounded,
              color: AppColors.textSecondaryLight);
        }
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.red,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Text(
                n == 1 ? '1 aguardando' : '$n aguardando',
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right_rounded,
                color: AppColors.textSecondaryLight),
          ],
        );
      },
    );
  }
}

class _SettingRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _SettingRow({
    required this.icon,
    required this.label,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isDark ? AppColors.cardDark : AppColors.cardLight,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? Colors.grey.shade800 : Colors.grey.shade100,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: AppColors.blue),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 14,
                  color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                ),
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}


/// "Eu canto" ou "Eu toco": quem canta abre a música e vê só a letra, em
/// fonte grande; quem toca vê a cifra no tom salvo.
class _EscolhaLeitura extends StatelessWidget {
  final ModoLeitura atual;
  final ValueChanged<ModoLeitura> onEscolher;

  const _EscolhaLeitura({required this.atual, required this.onEscolher});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    Widget opcao(ModoLeitura m, String emoji, String titulo, String sub) {
      final sel = atual == m;
      return Expanded(
        child: GestureDetector(
          onTap: sel ? null : () => onEscolher(m),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: sel
                  ? AppColors.blue
                  : isDark
                      ? Colors.grey.shade800
                      : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$emoji $titulo',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: sel
                        ? Colors.white
                        : isDark
                            ? AppColors.textPrimaryDark
                            : AppColors.textPrimaryLight,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  sub,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11,
                    color: sel
                        ? Colors.white70
                        : isDark
                            ? AppColors.textSecondaryDark
                            : AppColors.textSecondaryLight,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Nas músicas, eu…',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            opcao(ModoLeitura.canto, '🎤', 'Eu canto', 'Só a letra, grande'),
            const SizedBox(width: 10),
            opcao(ModoLeitura.toco, '🎸', 'Eu toco', 'Cifra no meu tom'),
          ],
        ),
      ],
    );
  }
}

/// "Avisos do chat", no Perfil.
///
/// São SETE estados, e cada um tem de dizer uma coisa diferente — é a razão
/// de isto ser um widget à parte em vez de um `Switch` na lista. O pior
/// desfecho possível aqui é a pessoa tocar em algo e não saber se funcionou:
/// aviso de mensagem é invisível por natureza, então cada caminho termina ou
/// num aviso de verdade chegando, ou numa frase dizendo o que falta.
///
/// O caso do iPhone é o que obriga a maior parte disto: lá o Push só existe
/// com o app instalado na tela de início, e a permissão só se pede dentro de
/// um toque. Fora da tela de início não há botão para mostrar — há um passo
/// a passo de instalação.
class _AvisosDoApp extends StatefulWidget {
  const _AvisosDoApp();

  @override
  State<_AvisosDoApp> createState() => _AvisosDoAppState();
}

class _AvisosDoAppState extends State<_AvisosDoApp> {
  EstadoDosAvisos? _estado;
  DateTime? _silenciadoAte;
  Set<TipoDeAviso> _ligados = const {};
  bool _trabalhando = false;

  @override
  void initState() {
    super.initState();
    _conferir();
  }

  Future<void> _conferir() async {
    final s = await AvisosService.situacao(instalado: estaInstalado);
    if (!mounted) return;
    setState(() {
      _estado = s.estado;
      _silenciadoAte = s.silenciadoAte;
      _ligados = s.ligados;
    });
  }

  void _dizer(String texto, {bool erro = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(texto),
      backgroundColor: erro ? AppColors.red : AppColors.success,
    ));
  }

  Future<void> _comEspera(Future<String?> Function() acao,
      {required String deuCerto}) async {
    if (_trabalhando) return;
    setState(() => _trabalhando = true);
    final erro = await acao();
    if (!mounted) return;
    setState(() => _trabalhando = false);
    await _conferir();
    _dizer(erro ?? deuCerto, erro: erro != null);
  }

  Future<void> _ativar() async {
    final eu = context.read<AuthProvider>().user;
    if (eu == null) return;
    // Sem `_comEspera` aqui: a permissão do iPhone precisa ser pedida DENTRO
    // do toque, e um `setState` antes já basta para o Safari considerar que
    // o gesto acabou.
    final erro = await AvisosService.ativar(userId: eu.id, userName: eu.name);
    if (!mounted) return;
    await _conferir();
    _dizer(erro ?? 'Avisos ativados neste aparelho.', erro: erro != null);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final estado = _estado;

    if (estado == null) {
      return const _SettingRow(
        icon: Icons.notifications_none_rounded,
        label: 'Avisos',
        trailing: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    final corFraca = isDark
        ? AppColors.textSecondaryDark
        : AppColors.textSecondaryLight;

    Widget explicacao(String texto) => Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            texto,
            style: TextStyle(fontFamily: 'Poppins', fontSize: 12.5,
                height: 1.45, color: corFraca),
          ),
        );

    final miolo = <Widget>[];

    switch (estado) {
      case EstadoDosAvisos.naoConfigurado:
        miolo.add(explicacao(
          'Os avisos ainda não foram configurados neste app. Falta publicar '
          'o mini-servidor e colar as duas linhas em avisos_config.dart.',
        ));

      case EstadoDosAvisos.precisaInstalar:
        miolo.add(explicacao(
          'No iPhone, o aviso só funciona com o app instalado na tela de '
          'início. Toque no botão de Compartilhar do Safari (o quadrado com '
          'a seta para cima), depois em "Adicionar à Tela de Início" e abra '
          'o app por lá. Este botão aparece quando você voltar.',
        ));

      case EstadoDosAvisos.semSuporte:
        miolo.add(explicacao(
          'Este navegador não sabe receber avisos. No computador, use o '
          'Chrome; no celular, instale o app na tela de início.',
        ));

      case EstadoDosAvisos.negado:
        miolo.add(explicacao(
          'Você recusou os avisos neste aparelho, e o navegador não pergunta '
          'de novo. Para liberar: ajustes do navegador → Notificações → '
          'procure o LevitaSync e permita.',
        ));

      case EstadoDosAvisos.podeAtivar:
        miolo
          ..add(explicacao(
            'Receba aviso de mensagem nova, de quando você for escalado e '
            'do lembrete na véspera do culto — mesmo com o app fechado. '
            'Depois você escolhe quais quer.',
          ))
          ..add(const SizedBox(height: 10))
          ..add(SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _ativar,
              icon: const Icon(Icons.notifications_active_rounded, size: 18),
              label: const Text('Ativar avisos'),
              style: FilledButton.styleFrom(backgroundColor: AppColors.blue),
            ),
          ));

      case EstadoDosAvisos.ligado:
      case EstadoDosAvisos.desligado:
        final ligado = estado == EstadoDosAvisos.ligado;
        final ate = _silenciadoAte;
        miolo.add(explicacao(ligado
            ? (ate != null
                ? 'Silenciado até ${DateFormat('HH:mm', 'pt_BR').format(ate)} '
                    'de ${DateFormat('d/MM', 'pt_BR').format(ate)}.'
                : 'Ligados neste aparelho.')
            : 'Desligados neste aparelho.'));
        miolo.add(const SizedBox(height: 4));
        if (ligado) {
          // Um liga-desliga por tipo. São incômodos diferentes: mensagem de
          // chat chega a toda hora, "você foi escalado" chega raro e importa,
          // e o lembrete da véspera é o que faz a pessoa não esquecer o
          // culto. Quem desliga o chat quase nunca quer desligar os outros.
          // "Novo pedido de entrada" só vale para o líder: é ele que
          // aprova, e o Worker manda só para ele. Um liga-desliga de algo que
          // nunca chega é só confusão na tela de quem não é líder.
          final souLider = context.read<AuthProvider>().isAdmin;
          final tipos = TipoDeAviso.values
              .where((t) => t != TipoDeAviso.pedido || souLider);
          for (final tipo in tipos) {
            miolo.add(Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      tipo.rotulo,
                      style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 12.5,
                          color: isDark
                              ? AppColors.textPrimaryDark
                              : AppColors.textPrimaryLight),
                    ),
                  ),
                  Transform.scale(
                    scale: 0.82,
                    child: Switch(
                      value: _ligados.contains(tipo),
                      activeColor: AppColors.blue,
                      onChanged: _trabalhando
                          ? null
                          : (quer) => _comEspera(
                                () => AvisosService.ligarTipo(tipo, quer),
                                deuCerto: quer
                                    ? '${tipo.rotulo}: ligado.'
                                    : '${tipo.rotulo}: desligado.',
                              ),
                    ),
                  ),
                ],
              ),
            ));
          }
          miolo.add(const SizedBox(height: 6));
          miolo.add(Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _trabalhando || ate != null
                    ? null
                    : () => _comEspera(
                          () => AvisosService.silenciar(DateTime.now()),
                          deuCerto: 'Silenciado até amanhã de manhã.',
                        ),
                child: const Text('Silenciar até amanhã',
                    style: TextStyle(fontSize: 12.5)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                onPressed: _trabalhando
                    ? null
                    : () => _comEspera(
                          AvisosService.testar,
                          deuCerto: 'Aviso de teste enviado.',
                        ),
                child: const Text('Testar aviso',
                    style: TextStyle(fontSize: 12.5)),
              ),
            ),
          ]));
        }
    }

    final podeAlternar = estado == EstadoDosAvisos.ligado ||
        estado == EstadoDosAvisos.desligado;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.cardDark : AppColors.cardLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.grey.shade800 : Colors.grey.shade100,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(
              estado == EstadoDosAvisos.ligado
                  ? Icons.notifications_active_rounded
                  : Icons.notifications_none_rounded,
              size: 20,
              color: AppColors.blue,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Avisos',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 14,
                  color: isDark
                      ? AppColors.textPrimaryDark
                      : AppColors.textPrimaryLight,
                ),
              ),
            ),
            if (podeAlternar)
              Switch(
                value: estado == EstadoDosAvisos.ligado,
                activeColor: AppColors.blue,
                onChanged: _trabalhando
                    ? null
                    : (quer) => _comEspera(
                          () => AvisosService.ligar(quer),
                          deuCerto: quer
                              ? 'Avisos ligados.'
                              : 'Avisos desligados neste aparelho.',
                        ),
              ),
          ]),
          ...miolo,
        ],
      ),
    );
  }
}
