import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/hinarios.dart';

/// Os hinários lado a lado, como pastilhas — e a pessoa muda a ordem delas.
///
/// POR QUE PASTILHAS, E NÃO A LISTA DE PÉ
///
/// A rodada anterior fez os hinários virarem uma lista vertical para dar
/// para arrastar e reordenar. Funcionou, mas custou duas faixas enormes: a
/// Harpa e o Cantor ocupavam um terço da tela de um iPhone, empurrando o
/// teclado para baixo. Pastilhas ocupam uma fila de 44 px, rolam para o lado
/// quando houver mais hinários que cabem, e a ordem delas ainda importa — a
/// primeira é a que abre quando a pessoa entra.
///
/// COMO SE MUDA A ORDEM, SEM ARRASTAR
///
/// Arrastar uma pastilha pequena exige firmeza na mão, e metade deste
/// ministério tem mais de sessenta anos. Então há um botão com TEXTO, "Mudar a
/// ordem", que acende setas ◀ ▶ em cada pastilha. Texto e não ícone, porque
/// um ícone de setas trocadas não diz nada a quem nunca o viu; e as setas só
/// aparecem quando a pessoa pede, para não poluir a fila de quem só quer
/// abrir o hino 15.
class PastilhasDeHinario extends StatelessWidget {
  final List<Hinario> ordem;
  final Hinario escolhido;
  final bool organizando;
  final bool isDark;
  final ValueChanged<Hinario> onEscolher;
  final void Function(Hinario h, int passos) onMover;
  final VoidCallback onAlternarOrganizar;

  const PastilhasDeHinario({
    super.key,
    required this.ordem,
    required this.escolhido,
    required this.organizando,
    required this.isDark,
    required this.onEscolher,
    required this.onMover,
    required this.onAlternarOrganizar,
  });

  @override
  Widget build(BuildContext context) {
    final podeOrganizar = ordem.length > 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            // Lista rolável aninhada diz o próprio recuo, senão herda o do
            // MediaQuery — que aqui é a barra inteira da aba Músicas.
            padding: EdgeInsets.zero,
            itemCount: ordem.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) => _Pastilha(
              hinario: ordem[i],
              ativa: ordem[i].id == escolhido.id,
              organizando: organizando,
              podeSubir: i > 0,
              podeDescer: i < ordem.length - 1,
              isDark: isDark,
              onEscolher: () => onEscolher(ordem[i]),
              onMover: (passos) => onMover(ordem[i], passos),
            ),
          ),
        ),
        if (organizando)
          _CartaoDeOrdem(isDark: isDark, onPronto: onAlternarOrganizar)
        else if (podeOrganizar)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onAlternarOrganizar,
              icon: const Icon(Icons.swap_horiz_rounded, size: 17),
              label: const Text('Mudar a ordem'),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                minimumSize: const Size(0, 30),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Pastilha extends StatelessWidget {
  final Hinario hinario;
  final bool ativa;
  final bool organizando;
  final bool podeSubir;
  final bool podeDescer;
  final bool isDark;
  final VoidCallback onEscolher;
  final ValueChanged<int> onMover;

  const _Pastilha({
    required this.hinario,
    required this.ativa,
    required this.organizando,
    required this.podeSubir,
    required this.podeDescer,
    required this.isDark,
    required this.onEscolher,
    required this.onMover,
  });

  @override
  Widget build(BuildContext context) {
    final fundo = ativa
        ? AppColors.blue
        : (isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.06));
    final texto = ativa
        ? Colors.white
        : (isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight);

    Widget seta(IconData icone, String dica, VoidCallback onTap) => Tooltip(
          message: dica,
          child: InkResponse(
            onTap: onTap,
            radius: 20,
            child: SizedBox(
              width: 34,
              height: 40,
              child: Icon(icone, size: 22, color: texto),
            ),
          ),
        );

    return Semantics(
      button: true,
      selected: ativa,
      label: hinario.nome,
      child: Material(
        color: fundo,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onEscolher,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              organizando && podeSubir ? 0 : 16,
              0,
              organizando && podeDescer ? 0 : 16,
              0,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (organizando && podeSubir)
                  seta(Icons.chevron_left_rounded,
                      'Mover ${hinario.nome} para a esquerda', () => onMover(-1)),
                Text(
                  hinario.nome,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: texto,
                  ),
                ),
                if (organizando && podeDescer)
                  seta(Icons.chevron_right_rounded,
                      'Mover ${hinario.nome} para a direita', () => onMover(1)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CartaoDeOrdem extends StatelessWidget {
  final bool isDark;
  final VoidCallback onPronto;

  const _CartaoDeOrdem({required this.isDark, required this.onPronto});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
      decoration: BoxDecoration(
        color: AppColors.blue.withValues(alpha: isDark ? 0.18 : 0.10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Use as setas para mudar a ordem. O primeiro da fila é o que '
              'abre quando você entra aqui.',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12.5,
                height: 1.35,
                color: isDark
                    ? AppColors.textPrimaryDark
                    : AppColors.textPrimaryLight,
              ),
            ),
          ),
          const SizedBox(width: 6),
          FilledButton(
            onPressed: onPronto,
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              minimumSize: const Size(64, 36),
            ),
            child: const Text('Pronto'),
          ),
        ],
      ),
    );
  }
}
