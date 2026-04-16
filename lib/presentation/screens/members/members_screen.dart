import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/models/user_model.dart';
import '../../../data/services/auth_service.dart';
import '../../providers/auth_provider.dart';

class MembersScreen extends StatelessWidget {
  const MembersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (!auth.isAdmin) {
      return const Scaffold(
        body: Center(child: Text('Acesso restrito ao líder.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Membros do Ministério',
          style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600),
        ),
      ),
      body: StreamBuilder<List<UserModel>>(
        stream: AuthService.getAllUsers(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Erro ao carregar membros: ${snapshot.error}',
                style: const TextStyle(fontFamily: 'Poppins'),
              ),
            );
          }

          final users = snapshot.data ?? [];

          if (users.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.people_outline_rounded,
                      size: 48,
                      color: isDark
                          ? Colors.grey.shade700
                          : Colors.grey.shade300),
                  const SizedBox(height: 12),
                  Text(
                    'Nenhum membro cadastrado',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 14,
                      color: isDark
                          ? AppColors.textSecondaryDark
                          : AppColors.textSecondaryLight,
                    ),
                  ),
                ],
              ),
            );
          }

          final admins = users.where((u) => u.isAdmin).toList();
          final levitas = users.where((u) => !u.isAdmin).toList();

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              _buildCountBadge(users.length, isDark),
              const SizedBox(height: 20),
              if (admins.isNotEmpty) ...[
                _SectionLabel(
                    label: 'Líderes (${admins.length})', color: AppColors.yellow),
                const SizedBox(height: 8),
                ...admins.map((u) => _MemberCard(user: u, isDark: isDark)),
                const SizedBox(height: 20),
              ],
              if (levitas.isNotEmpty) ...[
                _SectionLabel(
                    label: 'Levitas (${levitas.length})', color: AppColors.blue),
                const SizedBox(height: 8),
                ...levitas.map((u) => _MemberCard(user: u, isDark: isDark)),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildCountBadge(int total, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.people_rounded, color: Colors.white, size: 22),
          const SizedBox(width: 12),
          Text(
            '$total membro${total == 1 ? '' : 's'} cadastrado${total == 1 ? '' : 's'}',
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  final Color color;

  const _SectionLabel({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 18,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _MemberCard extends StatelessWidget {
  final UserModel user;
  final bool isDark;

  const _MemberCard({required this.user, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.cardDark : AppColors.cardLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? Colors.grey.shade800 : Colors.grey.shade100,
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: user.isAdmin
                ? AppColors.yellow.withOpacity(0.15)
                : AppColors.blue.withOpacity(0.15),
            child: Text(
              user.name[0].toUpperCase(),
              style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: user.isAdmin ? AppColors.yellow : AppColors.blue,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.name,
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
                  '${user.instrument.emoji} ${user.instrument.label}',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11,
                    color: isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondaryLight,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: user.isAdmin
                  ? AppColors.yellow.withOpacity(0.12)
                  : AppColors.blue.withOpacity(0.10),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              user.isAdmin ? '👑 ${user.role.label}' : '🎵 ${user.role.label}',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: user.isAdmin ? AppColors.yellow : AppColors.blue,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
