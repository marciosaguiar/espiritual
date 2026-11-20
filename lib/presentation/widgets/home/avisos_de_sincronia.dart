import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../data/models/aviso_de_sincronia.dart';
import '../../../data/services/avisos_de_sincronia.dart';
import '../../../data/services/fila_service.dart';

/// Os recados sobre o que a pessoa fez e não terminou como ela esperava:
/// uma edição que perdeu para quem chegou antes ao banco, uma confirmação que
/// o banco recusou depois de a pessoa ter ido embora da tela.
///
/// Aparece no Início, e SÓ quando há recado. Não some sozinho: um aviso que
/// sumisse seria a falha silenciosa que este app não aceita — a pessoa
/// acharia que a alteração dela valeu. Sai quando ela toca em "Entendi".
///
/// Máximo de três na tela, com "e mais N" para o resto: uma pilha de
/// recados é parede, e parede não se lê.
class CartaoDeAvisosDeSincronia extends StatelessWidget {
  /// Só os testes trocam.
  final AvisosDeSincronia? avisos;
  final Future<void> Function(AvisoDeSincronia)? aoReaplicar;

  const CartaoDeAvisosDeSincronia({super.key, this.avisos, this.aoReaplicar});

  static const int _maximoNaTela = 3;

  @override
  Widget build(BuildContext context) {
    final fonte = avisos ?? AvisosDeSincronia.instancia;
    return ListenableBuilder(
      listenable: fonte,
      builder: (context, _) {
        final lista = fonte.lista;
        if (lista.isEmpty) return const SizedBox.shrink();
        final visiveis = lista.take(_maximoNaTela).toList();
        final resto = lista.length - visiveis.length;
        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final a in visiveis)
                _Aviso(
                  aviso: a,
                  aoEntender: () => fonte.remover(a.id),
                  aoReaplicar: () async {
                    await (aoReaplicar ?? FilaService.reaplicar)(a);
                  },
                ),
              if (resto > 0)
                Padding(
                  padding: const EdgeInsets.only(left: 4, top: 4),
                  child: Text(
                    resto == 1 ? 'e mais 1 recado' : 'e mais $resto recados',
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12,
                      color: AppColors.textSecondaryLight,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Aviso extends StatelessWidget {
  final AvisoDeSincronia aviso;
  final VoidCallback aoEntender;
  final VoidCallback aoReaplicar;

  const _Aviso({
    required this.aviso,
    required this.aoEntender,
    required this.aoReaplicar,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final texto =
        isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      decoration: BoxDecoration(
        color: AppColors.yellow.withValues(alpha: isDark ? 0.10 : 0.14),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.yellow.withValues(alpha: isDark ? 0.35 : 0.55),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 1),
                child: Icon(Icons.info_outline_rounded,
                    size: 18, color: AppColors.yellow),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  aviso.titulo,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                    color: texto,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            aviso.texto,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 12.5,
              height: 1.45,
              color: texto,
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            alignment: WrapAlignment.end,
            children: [
              if (aviso.podeReaplicar)
                TextButton(
                  onPressed: aoReaplicar,
                  child: const Text('Aplicar a minha mesmo assim'),
                ),
              TextButton(
                onPressed: aoEntender,
                child: const Text('Entendi'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
