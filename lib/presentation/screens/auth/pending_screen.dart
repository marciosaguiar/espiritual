import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../providers/auth_provider.dart';

/// A tela de quem se cadastrou e ainda não foi aprovado pelo líder.
///
/// Existe para que a trava não pareça defeito. As regras do banco não
/// devolvem nada para quem está pendente, então sem esta tela a pessoa cairia
/// nas cinco abas vazias — sem música, sem culto, sem chat — e concluiria que
/// o app está quebrado. Aqui ela lê o que aconteceu e o que falta.
///
/// Não tem botão de atualizar de propósito: o provider escuta o próprio
/// cadastro, e no segundo em que o líder aprova o app sai daqui sozinho.
class PendingScreen extends StatelessWidget {
  const PendingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final recusado = auth.recusado;

    final corTexto =
        isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final corFraca =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: (recusado ? AppColors.red : AppColors.blue)
                        .withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    recusado
                        ? Icons.do_not_disturb_on_outlined
                        : Icons.hourglass_top_rounded,
                    size: 34,
                    color: recusado ? AppColors.red : AppColors.blue,
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  recusado
                      ? 'Seu pedido não foi aprovado'
                      : 'Falta o líder aprovar',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                    color: corTexto,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  recusado
                      ? 'Fale com o líder do ministério. Se foi engano, ele '
                          'consegue liberar a sua entrada pelo app, sem você '
                          'precisar se cadastrar de novo.'
                      : 'Seu cadastro foi enviado. Um líder do ministério '
                          'precisa liberar a sua entrada — é assim que o '
                          'repertório e a escala ficam só para a equipe.',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 15,
                    height: 1.55,
                    color: corFraca,
                  ),
                ),
                if (!recusado) ...[
                  const SizedBox(height: 18),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.blue.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: AppColors.blue.withValues(alpha: 0.25)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle_outline_rounded,
                            size: 20, color: AppColors.blue),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Pode deixar esta tela aberta: assim que ele '
                            'aprovar, o app abre sozinho.',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 13.5,
                              height: 1.45,
                              color: corTexto,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                Row(
                  children: [
                    Icon(Icons.person_outline_rounded,
                        size: 18, color: corFraca),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Você entrou como ${auth.user?.name ?? ''}',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 13,
                          color: corFraca,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => context.read<AuthProvider>().logout(),
                    icon: const Icon(Icons.logout_rounded, size: 18),
                    label: const Text('Sair'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      foregroundColor: corTexto,
                      side: BorderSide(color: corFraca.withValues(alpha: 0.4)),
                      textStyle: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
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
