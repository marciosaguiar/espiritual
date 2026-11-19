import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../data/models/saude_model.dart';
import '../../providers/saude_provider.dart';
import '../common/glass.dart';

/// "Saúde do sistema", no Perfil do líder.
///
/// POR QUE ESTA TELA EXISTE
///
/// Os robôs falharam em silêncio por dias: a rotina diária batia num 403, o
/// motivo ficava no log do Worker, e ninguém abre log de Worker. A escala
/// parou de ser criada e o lembrete da véspera parou de chegar sem nada
/// vermelho em lugar nenhum.
///
/// Então o diagnóstico virou tela — e tela que diz O QUE FAZER, não o
/// número. "O Worker respondeu 403" não é informação para quem vai consertar;
/// "o robô não é líder: promova-o em Membros" é.
class CartaoSaude extends StatefulWidget {
  const CartaoSaude({super.key});

  @override
  State<CartaoSaude> createState() => _CartaoSaudeState();
}

class _CartaoSaudeState extends State<CartaoSaude> {
  @override
  void initState() {
    super.initState();
    // Depois do primeiro quadro: carregar durante o build dispararia
    // notifyListeners no meio da árvore.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<SaudeProvider>().carregarUmaVez();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final p = context.watch<SaudeProvider>();
    final saude = p.saude;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.06)
            : Colors.white.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: p.temAlarme
              ? AppColors.red.withValues(alpha: 0.5)
              : (isDark
                  ? Colors.white.withValues(alpha: 0.10)
                  : Colors.white.withValues(alpha: 0.7)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                p.temAlarme
                    ? Icons.warning_amber_rounded
                    : Icons.favorite_rounded,
                size: 19,
                color: p.temAlarme ? AppColors.red : AppColors.success,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Saúde do sistema',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? AppColors.textPrimaryDark
                        : AppColors.textPrimaryLight,
                  ),
                ),
              ),
              if (p.carregando)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                IconButton(
                  icon: const Icon(Icons.refresh_rounded, size: 19),
                  tooltip: 'Conferir de novo',
                  onPressed: () => context.read<SaudeProvider>().conferir(),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          if (saude == null && !p.carregando)
            _Linha(
              item: const ItemDeSaude(
                titulo: 'Ainda não conferi',
                estado: EstadoDeSaude.desconhecido,
                detalhe: 'Toque na seta para conferir agora.',
              ),
              isDark: isDark,
            )
          else if (saude != null)
            ...saude.itens.map((i) => _Linha(item: i, isDark: isDark)),
          const SizedBox(height: 4),
          Text(
            'Os avisos e a criação dos cultos dependem de robôs que rodam '
            'sozinhos. Esta é a única tela em que dá para ver se eles estão '
            'rodando.',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 11.5,
              height: 1.45,
              color: isDark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondaryLight,
            ),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

/// Uma linha: bolinha de cor, título, o que está acontecendo e o que fazer.
class _Linha extends StatelessWidget {
  final ItemDeSaude item;
  final bool isDark;

  const _Linha({required this.item, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                color: corDe(item.estado),
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.titulo,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? AppColors.textPrimaryDark
                        : AppColors.textPrimaryLight,
                  ),
                ),
                Text(
                  item.detalhe,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12.5,
                    height: 1.4,
                    color: isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondaryLight,
                  ),
                ),
                // "O que fazer" aparece SÓ quando há o que fazer. Instrução
                // na tela com tudo em ordem ensina a não ler instrução.
                if (item.oQueFazer != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    item.oQueFazer!,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12.5,
                      height: 1.4,
                      fontWeight: FontWeight.w500,
                      color: corDe(item.estado),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A cor de cada estado, num lugar só — a usam o cartão e o aviso do Início.
Color corDe(EstadoDeSaude e) {
  switch (e) {
    case EstadoDeSaude.ok:
      return AppColors.success;
    case EstadoDeSaude.alerta:
      return AppColors.warning;
    case EstadoDeSaude.ruim:
      return AppColors.red;
    case EstadoDeSaude.desconhecido:
      return AppColors.textSecondaryLight;
  }
}

/// A tarja curta de saúde, no Perfil do líder: "Algo parou — toque para ver".
///
/// POR QUE ELA É CURTA, E POR QUE SOME
///
/// O cartão com as cinco linhas saiu do Perfil e foi para o Painel do líder:
/// cinco linhas de diagnóstico na tela principal, com tudo verde, é o jeito
/// de a pessoa aprender a passar o olho por cima. Aqui fica só o aviso, e só
/// quando há o que ver — **tudo verde é invisível**.
///
/// Ela não acende em `desconhecido`: "não consegui falar com o Worker" é o
/// wi-fi da igreja, não o sistema (ver `SaudeDoSistema`).
class AvisoCurtoDeSaude extends StatefulWidget {
  const AvisoCurtoDeSaude({super.key});

  @override
  State<AvisoCurtoDeSaude> createState() => _AvisoCurtoDeSaudeState();
}

class _AvisoCurtoDeSaudeState extends State<AvisoCurtoDeSaude> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<SaudeProvider>().carregarUmaVez();
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<SaudeProvider>();
    final saude = p.saude;
    if (saude == null) return const SizedBox.shrink();

    // Amarelo também aparece: "já passou da hora de hoje" é o aviso que
    // ainda dá tempo de agir antes de alguém ficar sem o lembrete.
    final ruim = saude.pior;
    final alerta = ruim ??
        saude.itens.cast<ItemDeSaude?>().firstWhere(
              (i) => i?.estado == EstadoDeSaude.alerta,
              orElse: () => null,
            );
    if (alerta == null) return const SizedBox.shrink();

    final cor = corDe(alerta.estado);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Material(
        color: cor.withValues(alpha: isDark ? 0.16 : 0.10),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => Navigator.push(
            context,
            GlassPageRoute(
              builder: (_) => Scaffold(
                appBar: AppBar(title: const Text('Saúde do sistema')),
                body: const SafeArea(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.all(20),
                    child: CartaoSaude(),
                  ),
                ),
              ),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(13),
            child: Row(
              children: [
                Icon(Icons.warning_amber_rounded, size: 20, color: cor),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${alerta.titulo}: toque para ver',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? AppColors.textPrimaryDark
                          : AppColors.textPrimaryLight,
                    ),
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: cor),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
