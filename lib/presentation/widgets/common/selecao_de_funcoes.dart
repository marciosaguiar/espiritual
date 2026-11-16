import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../data/models/user_model.dart';

/// Escolher as funções da pessoa: quantas ela faz, e qual é a principal.
///
/// Era uma função só, e no ministério é comum tocar duas — cantar e fazer
/// violão, baixo e teclado. Com uma só, o cadastro decidia errado a escala e
/// o modo de ver a música para sempre.
///
/// A PRINCIPAL é a primeira da lista, e aparece onde só cabe uma (lista de
/// membros, chat, selo da escala). Trocá-la não tira as outras.
class SelecaoDeFuncoes extends StatelessWidget {
  /// As funções escolhidas, na ordem — a primeira é a principal.
  final List<UserInstrument> funcoes;
  final ValueChanged<List<UserInstrument>> aoMudar;
  final bool isDark;

  const SelecaoDeFuncoes({
    super.key,
    required this.funcoes,
    required this.aoMudar,
    required this.isDark,
  });

  void _alternar(UserInstrument f) {
    if (funcoes.contains(f)) {
      // Nunca deixa ficar sem nenhuma: sem função, a escala não sabe o que
      // oferecer e o modo de leitura não tem de onde sair.
      if (funcoes.length == 1) return;
      aoMudar(funcoes.where((x) => x != f).toList());
      return;
    }
    aoMudar([...funcoes, f]);
  }

  void _tornarPrincipal(UserInstrument f) {
    if (funcoes.isEmpty || funcoes.first == f) return;
    aoMudar([f, ...funcoes.where((x) => x != f)]);
  }

  @override
  Widget build(BuildContext context) {
    final secundaria =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final principal = funcoes.isEmpty ? null : funcoes.first;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: UserInstrument.values.map((f) {
            final marcada = funcoes.contains(f);
            final ehPrincipal = principal == f;
            return GestureDetector(
              onTap: () => _alternar(f),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: marcada
                      ? AppColors.blue
                      : (isDark ? Colors.grey.shade800 : Colors.grey.shade100),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: marcada
                        ? AppColors.blue
                        : (isDark
                            ? Colors.grey.shade700
                            : Colors.grey.shade200),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (ehPrincipal)
                      const Padding(
                        padding: EdgeInsets.only(right: 4),
                        child: Icon(Icons.star_rounded,
                            size: 14, color: Colors.white),
                      ),
                    Text(
                      '${f.emoji} ${f.label}',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: marcada
                            ? Colors.white
                            : (isDark
                                ? AppColors.textPrimaryDark
                                : AppColors.textPrimaryLight),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
        if (funcoes.length > 1) ...[
          const SizedBox(height: 10),
          Text(
            'Principal (a que aparece na lista e no chat):',
            style: TextStyle(
                fontFamily: 'Poppins', fontSize: 11.5, color: secundaria),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: funcoes.map((f) {
              final ehPrincipal = principal == f;
              return GestureDetector(
                onTap: () => _tornarPrincipal(f),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: ehPrincipal
                        ? AppColors.blue.withValues(alpha: 0.15)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: ehPrincipal
                          ? AppColors.blue
                          : (isDark
                              ? Colors.grey.shade700
                              : Colors.grey.shade300),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        ehPrincipal
                            ? Icons.star_rounded
                            : Icons.star_outline_rounded,
                        size: 13,
                        color: ehPrincipal ? AppColors.blue : secundaria,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        f.label,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 11.5,
                          fontWeight: ehPrincipal
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: ehPrincipal ? AppColors.blue : secundaria,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ],
    );
  }
}
