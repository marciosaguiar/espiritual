import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../../providers/saude_provider.dart';

/// O aviso vermelho no Início quando um robô parou de rodar.
///
/// POR QUE ELE É VERMELHO E NÃO SAI COM UM TOQUE
///
/// Os robôs falharam em silêncio por dias. A informação existia — no log do
/// Worker — e não chegava a ninguém. Um cartão que o líder possa dispensar
/// voltaria ao mesmo lugar: o toque sem pensar do primeiro dia, e o aviso
/// nunca mais aparece. Este sai sozinho quando o problema se resolve, e não
/// antes.
///
/// SÓ PARA LÍDER, e só quando há o que fazer
///
/// Um levita não aprova cadastro nem mexe na Cloudflare: para ele isto seria
/// susto sem conserto. E "não consegui falar com o servidor" NUNCA acende —
/// celular sem internet não é sistema quebrado, e alarme que mente é alarme
/// que se aprende a ignorar.
class AvisoDeSaude extends StatefulWidget {
  /// Chamado quando o líder toca no aviso: leva ao Perfil, onde está o
  /// cartão com as cinco linhas e o que fazer em cada uma.
  final VoidCallback onAbrir;

  const AvisoDeSaude({super.key, required this.onAbrir});

  @override
  State<AvisoDeSaude> createState() => _AvisoDeSaudeState();
}

class _AvisoDeSaudeState extends State<AvisoDeSaude> {
  @override
  void initState() {
    super.initState();
    // Carrega aqui, e não só no Perfil: ninguém abre o Perfil por conta
    // própria, e um alarme que só aparece para quem foi procurá-lo não é
    // alarme. Uma vez por abertura do app, e só para líder.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (context.read<AuthProvider>().isAdmin) {
        context.read<SaudeProvider>().carregarUmaVez();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (!auth.isAdmin) return const SizedBox.shrink();

    final p = context.watch<SaudeProvider>();
    final pior = p.pior;
    if (!p.temAlarme || pior == null) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: widget.onAbrir,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.red.withValues(alpha: isDark ? 0.18 : 0.10),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.red.withValues(alpha: 0.45)),
          ),
          child: Row(
            children: [
              const Icon(Icons.warning_amber_rounded,
                  color: AppColors.red, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${pior.titulo}: ${pior.detalhe}',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        height: 1.35,
                        color: isDark
                            ? AppColors.textPrimaryDark
                            : AppColors.textPrimaryLight,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      pior.oQueFazer ?? 'Veja em Perfil → Painel do líder → Saúde do sistema.',
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12.5,
                        height: 1.4,
                        color: AppColors.red,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.red),
            ],
          ),
        ),
      ),
    );
  }
}
