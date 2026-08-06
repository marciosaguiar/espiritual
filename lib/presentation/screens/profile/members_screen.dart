import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/models/user_model.dart';
import '../../../data/services/auth_service.dart';

/// Ministry roster. Leaders use this to promote or step someone down —
/// the sign-up form no longer lets people pick their own role.
class MembersScreen extends StatelessWidget {
  const MembersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('Membros do ministério')),
      body: StreamBuilder<List<UserModel>>(
        stream: AuthService.getAllUsers(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _Message(
              icon: Icons.wifi_off_rounded,
              title: 'Não foi possível carregar os membros',
              detail: 'Verifique sua conexão e tente novamente.',
            );
          }
          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.blue),
            );
          }

          final members = snapshot.data!;
          if (members.isEmpty) {
            return _Message(
              icon: Icons.people_outline_rounded,
              title: 'Nenhum membro cadastrado',
              detail: 'Peça para o pessoal criar a conta no app.',
            );
          }

          final leaders = members.where((m) => m.isAdmin).length;

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 110),
            itemCount: members.length + 1,
            itemBuilder: (context, i) {
              if (i == 0) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Text(
                    '$leaders ${leaders == 1 ? 'líder' : 'líderes'} · '
                    '${members.length} ${members.length == 1 ? 'membro' : 'membros'}',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12.5,
                      color: isDark
                          ? AppColors.textSecondaryDark
                          : AppColors.textSecondaryLight,
                    ),
                  ),
                );
              }

              final member = members[i - 1];
              return _MemberRow(
                member: member,
                isMe: member.id == auth.user?.id,
                canManage: auth.isAdmin,
                isDark: isDark,
              );
            },
          );
        },
      ),
    );
  }
}

class _MemberRow extends StatefulWidget {
  final UserModel member;
  final bool isMe;
  final bool canManage;
  final bool isDark;

  const _MemberRow({
    required this.member,
    required this.isMe,
    required this.canManage,
    required this.isDark,
  });

  @override
  State<_MemberRow> createState() => _MemberRowState();
}

class _MemberRowState extends State<_MemberRow> {
  bool _saving = false;

  Future<void> _changeRole(UserRole role) async {
    final label = role == UserRole.admin ? 'Líder' : 'Levita';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Tornar $label?'),
        content: Text(
          role == UserRole.admin
              ? '${widget.member.name} poderá criar cultos, montar escalas e '
                  'cadastrar músicas.'
              : '${widget.member.name} deixará de gerenciar cultos, escalas e '
                  'músicas.',
          style: const TextStyle(fontFamily: 'Poppins', fontSize: 13.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.blue),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _saving = true);
    final result = await AuthService.setUserRole(widget.member, role);
    if (!mounted) return;
    setState(() => _saving = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.success
              ? '${widget.member.name} agora é $label.'
              : result.error ?? 'Não foi possível alterar a função.',
        ),
        backgroundColor: result.success ? AppColors.success : AppColors.red,
      ),
    );
  }

  /// Leader sets a temporary password and passes it on in person. Sign-in uses
  /// only a name, so there is no e-mail to send a reset link to.
  Future<void> _resetPassword() async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final novaSenha = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Redefinir senha de ${widget.member.name}'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Escolha uma senha provisória e combine com a pessoa. '
                'Ela pode trocar depois no Perfil.',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 13),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Nova senha',
                  hintText: 'Mínimo 6 caracteres',
                ),
                validator: (v) => (v == null ||
                        v.length < AuthService.minPasswordLength)
                    ? 'Mínimo ${AuthService.minPasswordLength} caracteres'
                    : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.pop(ctx, controller.text);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.blue),
            child: const Text('Redefinir'),
          ),
        ],
      ),
    );

    controller.dispose();
    if (novaSenha == null || !mounted) return;

    setState(() => _saving = true);
    final result = await AuthService.resetPassword(widget.member, novaSenha);
    if (!mounted) return;
    setState(() => _saving = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.success
              ? 'Senha de ${widget.member.name} redefinida. Avise a pessoa.'
              : result.error ?? 'Não foi possível redefinir a senha.',
        ),
        backgroundColor: result.success ? AppColors.success : AppColors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.member;
    final isDark = widget.isDark;
    final accent = m.isAdmin ? AppColors.red : AppColors.blue;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withOpacity(0.06)
            : Colors.white.withOpacity(0.55),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark
              ? Colors.white.withOpacity(0.10)
              : Colors.white.withOpacity(0.65),
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: accent.withOpacity(0.15),
            child: Text(
              m.name.isNotEmpty ? m.name[0].toUpperCase() : '?',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w700,
                color: accent,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        m.name,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? AppColors.textPrimaryDark
                              : AppColors.textPrimaryLight,
                        ),
                      ),
                    ),
                    if (widget.isMe)
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Text(
                          '(você)',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 11.5,
                            color: isDark
                                ? AppColors.textSecondaryDark
                                : AppColors.textSecondaryLight,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${m.isAdmin ? '👑 Líder' : '🎵 Levita'} · '
                  '${m.instrument.emoji} ${m.instrument.label}',
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
          if (widget.canManage) ...[
            const SizedBox(width: 4),
            if (_saving)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              PopupMenuButton<String>(
                tooltip: 'Opções',
                icon: const Icon(Icons.more_vert_rounded, size: 20),
                onSelected: (value) {
                  if (value == 'role') {
                    _changeRole(m.isAdmin ? UserRole.levita : UserRole.admin);
                  } else if (value == 'password') {
                    _resetPassword();
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'role',
                    child: Row(
                      children: [
                        Icon(
                          m.isAdmin
                              ? Icons.person_outline_rounded
                              : Icons.workspace_premium_outlined,
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Text(m.isAdmin ? 'Tornar levita' : 'Tornar líder'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'password',
                    child: Row(
                      children: [
                        Icon(Icons.key_outlined, size: 18),
                        SizedBox(width: 10),
                        Text('Redefinir senha'),
                      ],
                    ),
                  ),
                ],
              ),
          ],
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String title;
  final String detail;

  const _Message({
    required this.icon,
    required this.title,
    required this.detail,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 46,
                color: isDark ? Colors.white24 : Colors.black26),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: isDark
                    ? AppColors.textPrimaryDark
                    : AppColors.textPrimaryLight,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12.5,
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondaryLight,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
