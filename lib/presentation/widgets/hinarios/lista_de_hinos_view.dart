import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/hinarios.dart';
import '../../../core/utils/lista_de_hinos.dart';

/// Em que pé está a busca DENTRO das letras.
///
/// A letra de um hino da biblioteca só chega ao aparelho quando alguém o abre
/// — são 640 documentos, e baixar tudo ao abrir o app custaria 640 leituras
/// por pessoa por dia, num plano grátis de 50 mil. Então a busca por trecho
/// pergunta antes: baixa uma vez, guarda no aparelho, e daí em diante procura
/// sem custo.
enum EstadoDasLetras {
  /// Nada a oferecer: ainda não há busca por texto, ou o hinário não tem
  /// biblioteca.
  nenhum,

  /// A busca é por texto, e as letras ainda não estão neste aparelho.
  oferecer,

  /// Baixando.
  baixando,

  /// As letras estão aqui e a busca já as lê.
  prontas,
}

/// Busca, ordem e a lista de TODOS os hinos do hinário.
///
/// É o "Ver todos os hinos": uma lista só, rolável, onde cabem o repertório e
/// a biblioteca juntos, com a ordem sempre à vista. A ordem era um ícone
/// escondido embaixo do teclado, quase fora da tela — e o que fica escondido
/// não existe para quem "só sabe usar WhatsApp".
class ListaDeHinosView extends StatelessWidget {
  final TextEditingController controle;
  final FocusNode foco;
  final bool autofoco;

  /// A pessoa tocou fora do campo de busca.
  final VoidCallback? onTapFora;
  final String busca;
  final ValueChanged<String> onBusca;
  final ValueChanged<String> onEnviar;

  /// A ordem que está valendo (que pode não ser a escolhida: "mais tocados"
  /// sem culto nenhum registrado cai para o número, e [avisoDaOrdem] diz).
  final OrdemDosHinos ordem;
  final ValueChanged<OrdemDosHinos> onOrdem;
  final String? avisoDaOrdem;

  /// Já filtrados e em ordem.
  final List<ItemDeHino> itens;
  final int totalDoHinario;
  final Hinario hinario;
  final Set<String> favoritas;
  final int? selecionado;
  final bool isDark;
  final ValueChanged<ItemDeHino> onAbrir;
  final Widget? vazio;

  final EstadoDasLetras letras;
  final VoidCallback? onBaixarLetras;

  const ListaDeHinosView({
    super.key,
    required this.controle,
    required this.foco,
    required this.autofoco,
    this.onTapFora,
    required this.busca,
    required this.onBusca,
    required this.onEnviar,
    required this.ordem,
    required this.onOrdem,
    this.avisoDaOrdem,
    required this.itens,
    required this.totalDoHinario,
    required this.hinario,
    required this.favoritas,
    this.selecionado,
    required this.isDark,
    required this.onAbrir,
    this.vazio,
    this.letras = EstadoDasLetras.nenhum,
    this.onBaixarLetras,
  });

  @override
  Widget build(BuildContext context) {
    final secundaria =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final resumo = busca.trim().isEmpty
        ? (totalDoHinario == 1 ? '1 hino' : '$totalDoHinario hinos')
        : (itens.length == 1
            ? '1 hino encontrado'
            : '${itens.length} de $totalDoHinario hinos');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: controle,
          focusNode: foco,
          autofocus: autofoco,
          onTapOutside: (_) => onTapFora?.call(),
          onChanged: onBusca,
          onSubmitted: onEnviar,
          textInputAction: TextInputAction.search,
          style: const TextStyle(fontFamily: 'Poppins', fontSize: 15),
          decoration: InputDecoration(
            hintText: 'Nome, número ou trecho da letra',
            prefixIcon: const Icon(Icons.search_rounded, size: 21),
            suffixIcon: busca.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Limpar a busca',
                    icon: const Icon(Icons.close_rounded, size: 19),
                    onPressed: () {
                      controle.clear();
                      onBusca('');
                    },
                  ),
            isDense: true,
            filled: true,
            fillColor:
                isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 8),
        _FilaDeOrdens(
          ordem: ordem,
          onOrdem: onOrdem,
          isDark: isDark,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 6, 4, 4),
          child: Text(
            avisoDaOrdem ?? '$resumo · ${hinario.nome}',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 12,
              height: 1.35,
              color: secundaria,
            ),
          ),
        ),
        if (letras == EstadoDasLetras.oferecer ||
            letras == EstadoDasLetras.baixando)
          _OfertaDeLetras(
            baixando: letras == EstadoDasLetras.baixando,
            onBaixar: onBaixarLetras,
            isDark: isDark,
          ),
        Expanded(
          child: itens.isEmpty
              ? SingleChildScrollView(child: vazio ?? const SizedBox.shrink())
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: itens.length,
                  // Altura fixa: com 640 linhas, medir cada uma custaria o
                  // scroll inteiro, e a lista não dançaria de altura.
                  itemExtent: 64,
                  itemBuilder: (_, i) {
                    final item = itens[i];
                    return LinhaDeHino(
                      item: item,
                      busca: busca,
                      favorito: item.musica != null &&
                          favoritas.contains(item.musica!.id),
                      selecionada: selecionado == item.numero,
                      isDark: isDark,
                      onAbrir: () => onAbrir(item),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// As ordens possíveis, todas à vista, de um toque.
///
/// Pastilhas e não um menu: o que está atrás de um ícone não é visto, e a
/// pergunta "em que ordem isto está?" tem de ter resposta sem tocar em nada.
class _FilaDeOrdens extends StatelessWidget {
  final OrdemDosHinos ordem;
  final ValueChanged<OrdemDosHinos> onOrdem;
  final bool isDark;

  const _FilaDeOrdens({
    required this.ordem,
    required this.onOrdem,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        children: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                'Ordem',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: isDark
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondaryLight,
                ),
              ),
            ),
          ),
          for (final o in OrdemDosHinos.values)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text(o.curto),
                selected: o == ordem,
                showCheckmark: false,
                visualDensity: VisualDensity.compact,
                labelStyle: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  fontWeight: o == ordem ? FontWeight.w600 : FontWeight.w500,
                  color: o == ordem
                      ? Colors.white
                      : (isDark
                          ? AppColors.textPrimaryDark
                          : AppColors.textPrimaryLight),
                ),
                selectedColor: AppColors.blue,
                backgroundColor: isDark
                    ? Colors.white10
                    : Colors.black.withValues(alpha: 0.06),
                side: BorderSide.none,
                onSelected: (_) => onOrdem(o),
              ),
            ),
        ],
      ),
    );
  }
}

class _OfertaDeLetras extends StatelessWidget {
  final bool baixando;
  final VoidCallback? onBaixar;
  final bool isDark;

  const _OfertaDeLetras({
    required this.baixando,
    required this.onBaixar,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: AppColors.yellow.withValues(alpha: isDark ? 0.14 : 0.14),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              baixando
                  ? 'Trazendo as letras para este aparelho… Pode continuar '
                      'procurando pelos nomes enquanto isso.'
                  : 'Estou procurando só pelos nomes. Para achar também '
                      'pelo que está escrito nas letras, o aparelho precisa '
                      'trazê-las uma vez (usa a internet por alguns '
                      'segundos).',
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
          if (baixando)
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            )
          else
            FilledButton(
              onPressed: onBaixar,
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
                minimumSize: const Size(0, 36),
              ),
              child: const Text('Trazer'),
            ),
        ],
      ),
    );
  }
}

/// Uma linha da lista: o número, o nome e, embaixo, o verso em que a busca
/// apareceu — ou, sem busca, em que pé o hino está.
class LinhaDeHino extends StatelessWidget {
  final ItemDeHino item;
  final String busca;
  final bool favorito;
  final bool selecionada;
  final bool isDark;
  final VoidCallback onAbrir;

  const LinhaDeHino({
    super.key,
    required this.item,
    required this.busca,
    required this.favorito,
    required this.selecionada,
    required this.isDark,
    required this.onAbrir,
  });

  @override
  Widget build(BuildContext context) {
    final secundaria =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final trecho = trechoDaBusca(item.letra, busca);
    final embaixo = trecho != null
        ? '“$trecho”'
        : (item.noRepertorio
            ? 'No repertório · Tom ${item.musica!.originalKey}'
            : 'Toque para ler');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: selecionada
            ? AppColors.blue.withValues(alpha: isDark ? 0.28 : 0.14)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onAbrir,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 50,
                  child: Text(
                    '${item.numero}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: AppColors.blue,
                    ),
                  ),
                ),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.titulo,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        embaixo,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 12.5,
                          fontStyle: trecho != null
                              ? FontStyle.italic
                              : FontStyle.normal,
                          color: secundaria,
                        ),
                      ),
                    ],
                  ),
                ),
                if (favorito)
                  const Padding(
                    padding: EdgeInsets.only(left: 6, right: 8),
                    child: Icon(Icons.favorite_rounded,
                        size: 17, color: AppColors.red),
                  )
                else
                  const SizedBox(width: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
