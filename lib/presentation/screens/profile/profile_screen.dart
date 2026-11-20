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
import '../../../data/services/fila_service.dart';
import '../../../data/services/auth_service.dart';
import '../../../data/services/avisos_service.dart';
import '../../../data/services/firestore_service.dart';
import '../../providers/agenda_provider.dart';
import '../../providers/scale_provider.dart';
import '../../widgets/profile/cartao_saude.dart';
import 'fixed_schedule_screen.dart';
import 'importar_hinario_screen.dart';
import 'members_screen.dart';
import 'teams_screen.dart';
import '../../widgets/common/glass.dart';
import '../../widgets/common/responsivo.dart';
import '../../widgets/common/install_banner.dart';
import '../../widgets/common/selecao_de_funcoes.dart';
import '../../widgets/common/recuperacao_por_email.dart';

class ProfileScreen extends StatefulWidget {
  /// Abre a aba Músicas já com o filtro escolhido.
  ///
  /// Vem de fora porque quem troca de aba é o `main_screen`. É o que faz os
  /// contadores de "Favoritas" e "No celular" levarem às listas que já
  /// existem lá, em vez de o Perfil ter cópias delas no fim da tela — que
  /// era o jeito antigo, e ninguém rolava até lá.
  final void Function(SongsFilter)? onAbrirMusicas;

  const ProfileScreen({super.key, this.onAbrirMusicas});

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
        // O guia das cinco abas, com a navegação NOVA.
        //
        // O texto antigo mandava a pessoa procurar o versículo e os atalhos
        // no Início, e a Bíblia no Perfil — as três coisas mudaram de lugar
        // nesta rodada. Guia que descreve a tela de antes é pior que guia
        // nenhum: ele faz a pessoa achar que o app está quebrado.
        //
        // E "offline" saiu daqui também: para quem só usa WhatsApp é palavra
        // de técnico, e é justamente o recurso que serve ao culto sem
        // internet.
        const items = [
          (
            Icons.home_rounded,
            'Início',
            'O que você precisa fazer agora: o seu próximo culto, as '
                'músicas dele e o que está esperando por você.'
          ),
          (
            Icons.music_note_rounded,
            'Músicas',
            'O repertório da igreja, os hinários (hino pelo número) e a '
                'Bíblia. Dá para mudar o tom e guardar no celular. Nos '
                'hinários, digite o número para abrir o hino, ou procure '
                'pelo nome; o botão ao lado da busca muda a ordem da lista, '
                'e dá para arrastar os hinários: o primeiro é o que abre. '
                'Quem é líder coloca o texto dos hinários em Perfil → '
                'Painel do líder → Importar hinário.'
          ),
          (
            Icons.calendar_month_rounded,
            'Escala',
            'Todos os cultos, confirmar presença e montar o repertório.'
          ),
          (
            Icons.chat_bubble_rounded,
            'Chat',
            'Converse com o ministério, mande áudio e compartilhe '
                'músicas.'
          ),
          (
            Icons.person_rounded,
            'Perfil',
            'Se você canta ou toca, suas favoritas, seus tons e os '
                'avisos.'
          ),
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
                          child: Icon(it.$1, color: AppColors.blue, size: 20),
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

  // ── As telas da lista curta ─────────────────────────────────────────────
  //
  // Cada uma responde UMA pergunta, e todas são construídas aqui dentro, em
  // closures: assim elas alcançam os métodos desta tela (trocar senha, sair)
  // sem precisar de uma fila de callbacks atravessando cinco arquivos.

  void _abrirEm(String titulo, WidgetBuilder corpo) {
    Navigator.push(
      context,
      GlassPageRoute(
        builder: (ctx) => Scaffold(
          appBar: AppBar(title: Text(titulo)),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 60),
              child: corpo(ctx),
            ),
          ),
        ),
      ),
    );
  }

  void _abrirAvisos() => _abrirEm(
      'Avisos',
      (_) => const Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [_AvisosDoApp()],
          ));

  void _abrirConta() {
    final user = context.read<AuthProvider>().user;
    if (user == null) return;
    _abrirEm('Conta', (ctx) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Vem ANTES de "Alterar minha senha" de propósito: esta é a que a
          // pessoa precisa ter feito ANTES de precisar dela. Sem e-mail
          // cadastrado, senha esquecida é acesso perdido — não existe quem
          // destrave depois, nem o líder.
          _SettingRow(
            icon: user.recuperacaoPorEmail
                ? Icons.verified_user_outlined
                : Icons.shield_outlined,
            label: 'Recuperar a senha',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  user.recuperacaoPorEmail ? 'Pronto' : 'Falta cadastrar',
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
            onTap: () => mostrarRecuperacaoPorEmail(ctx),
          ),
          const SizedBox(height: 8),
          _SettingRow(
            icon: Icons.key_outlined,
            label: 'Alterar minha senha',
            trailing: const Icon(Icons.chevron_right_rounded,
                color: AppColors.textSecondaryLight),
            onTap: () => _showChangePasswordSheet(ctx, user),
          ),
          const SizedBox(height: 22),
          const _SairDoMinisterio(),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: ctx,
                  builder: (_) => AlertDialog(
                    title: const Text('Sair da conta'),
                    content: Text(
                      FilaService.fila.pendentes > 0
                          ? 'Você tem ${FilaService.fila.pendentes == 1 ? '1 alteração que ainda não foi enviada' : '${FilaService.fila.pendentes} alterações que ainda não foram enviadas'}, '
                              'porque falta internet. Se sair agora, '
                              '${FilaService.fila.pendentes == 1 ? 'ela se perde' : 'elas se perdem'}.\n\n'
                              'Deseja sair mesmo assim?'
                          : 'Deseja realmente sair da sua conta?',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancelar'),
                      ),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.red),
                        child: const Text('Sair'),
                      ),
                    ],
                  ),
                );
                if (confirm == true && mounted) {
                  await context.read<AuthProvider>().logout();
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
        ],
      );
    });
  }

  void _abrirAjuda() => _abrirEm(
      'Ajuda',
      (ctx) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SettingRow(
                icon: Icons.menu_book_rounded,
                label: 'Como usar o app',
                trailing: const Icon(Icons.chevron_right_rounded,
                    color: AppColors.textSecondaryLight),
                onTap: () => _showHelpSheet(ctx),
              ),
              const SizedBox(height: 8),
              _SettingRow(
                icon: Icons.info_outline_rounded,
                label: 'Sobre o ${AppStrings.appName}',
                trailing: const Icon(Icons.chevron_right_rounded,
                    color: AppColors.textSecondaryLight),
                onTap: () => _showAboutSheet(ctx),
              ),
            ],
          ));

  /// O Painel do líder: as ferramentas de quem cuida do ministério.
  ///
  /// Em tela larga a lista fica à esquerda e a ferramenta escolhida abre à
  /// direita — o líder que aprova um pedido, ajusta uma equipe e confere a
  /// saúde do sistema trabalha sem ficar indo e voltando. No celular, cada uma
  /// abre por cima, como sempre.
  void _abrirPainelDoLider() {
    Navigator.push(
      context,
      GlassPageRoute(
        larguraMaxima: 1240,
        builder: (ctx) => Scaffold(
          appBar: AppBar(title: const Text('Painel do líder')),
          body: SafeArea(
            child: MestreDetalhe(
              vazioIcone: Icons.admin_panel_settings_outlined,
              vazioTitulo: 'Escolha uma ferramenta',
              vazioTexto: 'Membros, equipes, agenda fixa e o hinário abrem '
                  'aqui, ao lado da lista.',
              mestre: Builder(
                builder: (ctx) => SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 60),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // A saúde do sistema vem PRIMEIRO: é a única coisa aqui
                      // que pode estar quebrada agora.
                      const CartaoSaude(),
                      const SizedBox(height: 14),
                      _SettingRow(
                        icon: Icons.groups_rounded,
                        label: 'Membros e pedidos de entrada',
                        trailing: const _SeloPendentes(),
                        onTap: () =>
                            abrirTela(ctx, (_) => const MembersScreen()),
                      ),
                      const SizedBox(height: 8),
                      _SettingRow(
                        icon: Icons.diversity_3_rounded,
                        label: 'Equipes',
                        trailing: const Icon(Icons.chevron_right_rounded,
                            color: AppColors.textSecondaryLight),
                        onTap: () => abrirTela(ctx, (_) => const TeamsScreen()),
                      ),
                      const SizedBox(height: 8),
                      _SettingRow(
                        icon: Icons.event_repeat_rounded,
                        label: 'Agenda fixa',
                        trailing: const Icon(Icons.chevron_right_rounded,
                            color: AppColors.textSecondaryLight),
                        onTap: () =>
                            abrirTela(ctx, (_) => const FixedScheduleScreen()),
                      ),
                      const SizedBox(height: 8),
                      _SettingRow(
                        icon: Icons.library_books_rounded,
                        label: 'Importar hinário',
                        trailing: const Icon(Icons.chevron_right_rounded,
                            color: AppColors.textSecondaryLight),
                        onTap: () => abrirTela(
                            ctx, (_) => const ImportarHinarioScreen()),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// "Tons salvos": o tom em que EU toco cada música.
  ///
  /// A lista morava no fim do Perfil, depois de tudo — ninguém rolava até
  /// lá. Virou a tela que o contador abre.
  void _abrirTonsSalvos() {
    _abrirEm('Tons salvos', (ctx) {
      final auth = ctx.read<AuthProvider>();
      final songs = ctx.read<SongsProvider>();
      final isDark = Theme.of(ctx).brightness == Brightness.dark;
      final entradas = auth.songPrefs.entries.toList();

      if (entradas.isEmpty) {
        return Text(
          'Nenhum tom salvo ainda.\n\nQuando você mudar o tom de uma música '
          'com o − ou o +, ele fica salvo para você e aparece aqui.',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 14,
            height: 1.5,
            color: isDark
                ? AppColors.textSecondaryDark
                : AppColors.textSecondaryLight,
          ),
        );
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: entradas.map((e) {
          final song = songs.getSongById(e.key);
          if (song == null) return const SizedBox.shrink();
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isDark ? AppColors.cardDark : AppColors.cardLight,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark ? Colors.grey.shade800 : Colors.grey.shade100,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    song.name,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 14,
                      color: isDark
                          ? AppColors.textPrimaryDark
                          : AppColors.textPrimaryLight,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.blue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  // O tom em que a pessoa toca, não o deslocamento: "+2" não
                  // diz nada para quem canta, "D → E" diz.
                  child: Text(
                    '${song.originalKey} → '
                    '${ChordTransposer.getKeyName(song.originalKey, e.value.semitones)}',
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.blue,
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      );
    });
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

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // Profile header
          SliverAppBar(
            expandedHeight: 240,
            pinned: true,
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            flexibleSpace: LayoutBuilder(
              builder: (context, c) {
                // QUANTO DO CABEÇALHO AINDA ESTÁ ABERTO: 1 = inteiro, 0 =
                // recolhido na barra de cima.
                //
                // O conteúdo (avatar, nome, etiquetas) tem altura fixa, e o
                // cabeçalho encolhe ao rolar. Antes o conteúdo continuava do
                // mesmo tamanho e a barra o cortava ao meio — o avatar ficava
                // pela metade —, e no fim sobrava uma barra de vidro vazia. Agora
                // o conteúdo ENCOLHE junto com o cabeçalho (FittedBox) e some
                // antes de ficar pequeno demais, e a barra recolhida mostra uma
                // versão compacta: avatar pequeno e nome.
                final topo = MediaQuery.paddingOf(context).top;
                final recolhido = kToolbarHeight + topo;
                final t = ((c.maxHeight - recolhido) / (240 - kToolbarHeight))
                    .clamp(0.0, 1.0);
                final inicial = user.name.trim().isEmpty
                    ? '?'
                    // `''[0]` LANÇA, e aqui derrubaria a aba Perfil inteira —
                    // um cadastro com o nome em branco (mexido no console, ou
                    // gravado pela metade) não pode fazer isso. Mesma armadilha
                    // do culto.
                    : user.name.trim()[0].toUpperCase();

                return Stack(
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
                    Opacity(
                      opacity: t,
                      child: Container(
                        decoration: const BoxDecoration(
                          gradient: AppColors.primaryGradient,
                        ),
                        padding: EdgeInsets.only(top: topo, bottom: 8),
                        child: Center(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Opacity(
                              opacity: ((t - 0.25) / 0.75).clamp(0.0, 1.0),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  CircleAvatar(
                                    radius: 48,
                                    backgroundColor:
                                        Colors.white.withOpacity(0.3),
                                    child: Text(
                                      inicial,
                                      style: const TextStyle(
                                        fontFamily: 'Poppins',
                                        fontSize: 36,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                      ),
                                    ),
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
                                    mainAxisAlignment:
                                        MainAxisAlignment.center,
                                    children: [
                                      _EtiquetaDoPerfil(
                                        user.isAdmin
                                            ? '👑 ${user.role.label}'
                                            : '🎵 ${user.role.label}',
                                      ),
                                      const SizedBox(width: 8),
                                      _EtiquetaDoPerfil(
                                        '${user.instrument.emoji} ${user.instrument.label}',
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Recolhido: uma barra comum, com o avatar pequeno e o nome.
                    Opacity(
                      opacity: (1 - t * 3).clamp(0.0, 1.0),
                      child: Padding(
                        padding: EdgeInsets.only(top: topo, left: 56, right: 56),
                        child: Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircleAvatar(
                                radius: 15,
                                backgroundColor:
                                    AppColors.blue.withOpacity(0.15),
                                child: Text(
                                  inicial,
                                  style: const TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.blue,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Flexible(
                                child: Text(
                                  user.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: isDark
                                        ? AppColors.textPrimaryDark
                                        : AppColors.textPrimaryLight,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
            actions: [
              IconButton(
                tooltip: _isEditing ? 'Salvar alterações' : 'Editar perfil',
                icon:
                    Icon(_isEditing ? Icons.check_rounded : Icons.edit_rounded),
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

                  // Os três contadores, agora TOCÁVEIS.
                  //
                  // Eram números decorativos, e as listas que eles contavam
                  // ficavam no FIM do Perfil, depois de tudo — então o número
                  // dizia "você tem 12 favoritas" e não levava a lugar
                  // nenhum. Agora cada um abre a sua lista, e as duas seções
                  // do fim do Perfil deixaram de existir: "Favoritas" e "No
                  // celular" são filtros que já existiam na aba Músicas.
                  Row(
                    children: [
                      _StatCard(
                        label: 'Favoritas',
                        value: '${user.favoriteSongs.length}',
                        icon: Icons.favorite_rounded,
                        color: AppColors.red,
                        onTap: () =>
                            widget.onAbrirMusicas?.call(SongsFilter.favorites),
                      ),
                      const SizedBox(width: 12),
                      _StatCard(
                        label: 'Tons salvos',
                        value: '${auth.songPrefs.length}',
                        icon: Icons.music_note_rounded,
                        color: AppColors.blue,
                        onTap: _abrirTonsSalvos,
                      ),
                      const SizedBox(width: 12),
                      _StatCard(
                        label: 'No celular',
                        value: '${songs.offlineCount}',
                        icon: Icons.download_done_rounded,
                        color: AppColors.success,
                        onTap: () =>
                            widget.onAbrirMusicas?.call(SongsFilter.offline),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // O AVISO de saúde, e só quando há o que ver.
                  //
                  // O cartão com as cinco linhas saiu do Perfil: ele mora no
                  // Painel do líder. Aqui fica só a tarja, quando algo está
                  // amarelo ou vermelho — tudo verde é invisível, porque
                  // diagnóstico na cara quando não há nada a fazer ensina a
                  // não olhar.
                  if (auth.isAdmin) ...[
                    const AvisoCurtoDeSaude(),
                  ],

                  // A LISTA CURTA.
                  //
                  // Eram treze linhas e duas listas compridas no fim. Agora
                  // são quatro linhas e, para o líder, uma quinta. Cada uma
                  // abre uma tela que responde uma pergunta só.
                  if (caminhoDeInstalacao != InstallRoute.naoSeAplica) ...[
                    _SettingRow(
                      icon: Icons.add_to_home_screen_rounded,
                      label: 'Instalar o app no celular',
                      trailing: const Icon(Icons.chevron_right_rounded,
                          color: AppColors.textSecondaryLight),
                      onTap: () => mostrarComoInstalar(context),
                    ),
                    const SizedBox(height: 8),
                  ],
                  _SettingRow(
                    icon: Icons.notifications_none_rounded,
                    label: 'Avisos',
                    trailing: const Icon(Icons.chevron_right_rounded,
                        color: AppColors.textSecondaryLight),
                    onTap: _abrirAvisos,
                  ),
                  const SizedBox(height: 8),
                  _SettingRow(
                    icon: Icons.person_outline_rounded,
                    label: 'Conta',
                    trailing: const Icon(Icons.chevron_right_rounded,
                        color: AppColors.textSecondaryLight),
                    onTap: _abrirConta,
                  ),
                  const SizedBox(height: 8),
                  // MODO ESCURO fica aqui, com o interruptor à vista.
                  //
                  // Você deixou a escolha para mim: uma linha "Aparência" que
                  // abre uma tela com um interruptor só, ou o interruptor na
                  // própria linha. Para quem só usa WhatsApp, um interruptor
                  // que se vê e se vira num toque ganha de uma tela que
                  // esconde um interruptor.
                  _SettingRow(
                    icon: isDark
                        ? Icons.light_mode_rounded
                        : Icons.dark_mode_rounded,
                    label: 'Modo escuro',
                    trailing: Switch(
                      value: isDark,
                      onChanged: (_) => theme.toggleTheme(),
                      activeColor: AppColors.blue,
                    ),
                    onTap: () => theme.toggleTheme(),
                  ),
                  const SizedBox(height: 8),
                  _SettingRow(
                    icon: Icons.help_outline_rounded,
                    label: 'Ajuda',
                    trailing: const Icon(Icons.chevron_right_rounded,
                        color: AppColors.textSecondaryLight),
                    onTap: _abrirAjuda,
                  ),
                  if (auth.isAdmin) ...[
                    const SizedBox(height: 18),
                    _SettingRow(
                      icon: Icons.shield_outlined,
                      label: 'Painel do líder',
                      trailing: const _SeloPendentes(),
                      onTap: _abrirPainelDoLider,
                    ),
                  ],
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

/// A pastilha clara do cabeçalho do Perfil ("👑 Líder", "🎤 Cantor(a)").
class _EtiquetaDoPerfil extends StatelessWidget {
  final String texto;
  const _EtiquetaDoPerfil(this.texto);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        texto,
        style: const TextStyle(
          fontFamily: 'Poppins',
          fontSize: 12,
          color: Colors.white,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  /// O toque que abre a lista contada.
  ///
  /// Eram números decorativos: diziam "12 favoritas" e não levavam a lugar
  /// nenhum — as listas ficavam no FIM do Perfil, e ninguém rolava até lá.
  final VoidCallback? onTap;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Expanded(
      child: Material(
        color: isDark ? AppColors.cardDark : AppColors.cardLight,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isDark ? Colors.grey.shade800 : Colors.grey.shade100,
              ),
            ),
            child: Column(
              children: [
                Icon(icon, color: color, size: 22),
                const SizedBox(height: 6),
                Text(
                  value,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? AppColors.textPrimaryDark
                        : AppColors.textPrimaryLight,
                  ),
                ),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11.5,
                    color: isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondaryLight,
                  ),
                ),
              ],
            ),
          ),
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
                  color: isDark
                      ? AppColors.textPrimaryDark
                      : AppColors.textPrimaryLight,
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
            color:
                isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
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

    final corFraca =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    Widget explicacao(String texto) => Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            texto,
            style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12.5,
                height: 1.45,
                color: corFraca),
          ),
        );

    final miolo = <Widget>[];

    switch (estado) {
      case EstadoDosAvisos.naoConfigurado:
        // ISTO É LIDO POR QUEM NÃO É LÍDER TAMBÉM.
        //
        // O texto antigo dizia "falta publicar o mini-servidor e colar as
        // duas linhas em avisos_config.dart". Para quem só usa WhatsApp isso
        // é tão útil quanto um código de erro: não dá nem para saber se é
        // problema do celular dele. Agora a frase diz de quem é a tarefa, e o
        // detalhe técnico fica onde serve — no Painel do líder.
        miolo.add(explicacao(
          'Os avisos ainda não estão ligados neste ministério. Isso é '
          'configuração do líder, não do seu celular.',
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
          const soDoLider = {TipoDeAviso.pedido, TipoDeAviso.confirmacao};
          final tipos = TipoDeAviso.values
              .where((t) => !soDoLider.contains(t) || souLider);
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

    final podeAlternar =
        estado == EstadoDosAvisos.ligado || estado == EstadoDosAvisos.desligado;

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
