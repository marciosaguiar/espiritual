import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';

/// O número que a pessoa está digitando, em letra grande: "HC 15".
class MostradorDoHino extends StatelessWidget {
  final String sigla;
  final String digitado;
  final bool isDark;

  const MostradorDoHino({
    super.key,
    required this.sigla,
    required this.digitado,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final vazio = digitado.isEmpty;
    return Container(
      alignment: Alignment.center,
      height: 64,
      decoration: BoxDecoration(
        color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        vazio ? 'Digite o número' : '$sigla $digitado',
        style: TextStyle(
          fontFamily: 'Poppins',
          fontSize: vazio ? 17 : 38,
          fontWeight: vazio ? FontWeight.w500 : FontWeight.w700,
          height: 1.1,
          color: vazio
              ? (isDark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondaryLight)
              : (isDark
                  ? AppColors.textPrimaryDark
                  : AppColors.textPrimaryLight),
        ),
      ),
    );
  }
}

/// O teclado de números na tela. Só aparece para quem usa o dedo: com um
/// teclado de verdade, digitar o número e dar Enter é mais rápido.
class TecladoDeHino extends StatelessWidget {
  final bool isDark;
  final ValueChanged<String> onDigito;
  final VoidCallback onApagar;
  final VoidCallback onLimpar;
  final bool podeApagar;

  /// Altura de cada tecla. A tela escolhe conforme o espaço que sobra: em
  /// celular alto as teclas crescem, porque é tela usada de pé e tecla grande
  /// erra menos.
  final double alturaDaTecla;

  const TecladoDeHino({
    super.key,
    required this.isDark,
    required this.onDigito,
    required this.onApagar,
    required this.onLimpar,
    required this.podeApagar,
    this.alturaDaTecla = 52,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final linha in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ])
          Row(
            children: linha
                .map((d) => _Tecla(
                      rotulo: d,
                      isDark: isDark,
                      altura: alturaDaTecla,
                      onTap: () => onDigito(d),
                    ))
                .toList(),
          ),
        Row(
          children: [
            _Tecla(
              rotulo: 'C',
              isDark: isDark,
              altura: alturaDaTecla,
              suave: true,
              onTap: podeApagar ? onLimpar : null,
            ),
            _Tecla(
              rotulo: '0',
              isDark: isDark,
              altura: alturaDaTecla,
              onTap: () => onDigito('0'),
            ),
            _Tecla(
              rotulo: '⌫',
              isDark: isDark,
              altura: alturaDaTecla,
              suave: true,
              onTap: podeApagar ? onApagar : null,
            ),
          ],
        ),
      ],
    );
  }
}

class _Tecla extends StatelessWidget {
  final String rotulo;
  final bool isDark;
  final bool suave;
  final double altura;
  final VoidCallback? onTap;

  const _Tecla({
    required this.rotulo,
    required this.isDark,
    required this.altura,
    this.onTap,
    this.suave = false,
  });

  @override
  Widget build(BuildContext context) {
    final desligada = onTap == null;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Material(
          color: suave
              ? (isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.04))
              : (isDark ? Colors.white12 : Colors.white),
          borderRadius: BorderRadius.circular(14),
          elevation: suave ? 0 : 1,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            // Alto de propósito: é tela usada de pé, com a igreja esperando,
            // e tecla pequena erra. 52 px ainda é mais que o mínimo de 48 que
            // os guias de acessibilidade pedem para o dedo.
            child: SizedBox(
              height: altura,
              child: Center(
                child: Text(
                  rotulo,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 23,
                    fontWeight: FontWeight.w600,
                    color: desligada
                        ? (isDark ? Colors.white24 : Colors.black26)
                        : (isDark
                            ? AppColors.textPrimaryDark
                            : AppColors.textPrimaryLight),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
