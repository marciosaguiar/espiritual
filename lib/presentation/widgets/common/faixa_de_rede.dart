import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/frescor.dart';
import '../../../data/services/estado_da_rede.dart';
import '../../../data/services/fila_service.dart';

/// A faixa discreta de "sem internet" e "atualizado há X".
///
/// Só aparece quando FAZ diferença (a regra mora em `textoDaFaixa`, que é pura
/// e testada): com internet e nada esperando, não existe. O app inteiro
/// funciona sem rede — a faixa não é um alarme, é a resposta à pergunta "por
/// que isto não atualizou?".
///
/// Ela empurra o conteúdo para baixo em vez de flutuar por cima: no celular
/// o rodapé do chat é o campo de texto, e uma pílula flutuando ali o cobriria
/// justamente quando a pessoa quer escrever.
///
/// A estrutura da árvore é a MESMA com e sem faixa. Se o filho mudasse de
/// lugar na árvore quando ela aparece, o Flutter o reconstruiria do zero — e
/// a pessoa perderia a busca digitada e a rolagem da aba por causa de um
/// elevador.
class FaixaDeRede extends StatefulWidget {
  final Widget child;

  /// Só os testes trocam: o relógio e a situação.
  final EstadoDaRede? estado;
  final Listenable? fila;
  final DateTime Function()? agora;

  const FaixaDeRede({
    super.key,
    required this.child,
    this.estado,
    this.fila,
    this.agora,
  });

  @override
  State<FaixaDeRede> createState() => _FaixaDeRedeState();
}

class _FaixaDeRedeState extends State<FaixaDeRede> {
  late final EstadoDaRede _estado = widget.estado ?? EstadoDaRede.instancia;
  late final Listenable _fila = widget.fila ?? FilaService.fila;
  Timer? _relogio;

  DateTime get _agora => (widget.agora ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _estado.addListener(_mudou);
    _fila.addListener(_mudou);
    // O texto depende da HORA ("sem internet há 10 s" só vale depois de 10 s):
    // sem relógio, a faixa só apareceria na próxima mudança de rede.
    _relogio = Timer.periodic(const Duration(seconds: 5), (_) => _mudou());
  }

  void _mudou() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _estado.removeListener(_mudou);
    _fila.removeListener(_mudou);
    _relogio?.cancel();
    super.dispose();
  }

  String? _texto() {
    final fila = FilaService.fila;
    final s = _estado.situacao(
      pendentes: fila.pendentes,
      pendenteDesde: fila.pendenteDesde,
    );
    return textoDaFaixa(s, _agora);
  }

  @override
  Widget build(BuildContext context) {
    final texto = _texto();
    final offline = !_estado.online;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          alignment: Alignment.topCenter,
          child: texto == null
              ? const SizedBox(width: double.infinity)
              : Material(
                  color: AppColors.yellow.withValues(alpha: isDark ? 0.18 : 0.30),
                  child: SafeArea(
                    bottom: false,
                    child: Semantics(
                      liveRegion: true,
                      label: texto,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        child: Row(
                          children: [
                            Icon(
                              offline
                                  ? Icons.cloud_off_rounded
                                  : Icons.sync_rounded,
                              size: 16,
                              color: isDark
                                  ? AppColors.textPrimaryDark
                                  : AppColors.textPrimaryLight,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ExcludeSemantics(
                                child: Text(
                                  texto,
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
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
        ),
        Expanded(
          // Com a faixa na tela ela já ocupou a área do topo (barra de status);
          // sem tirar o recuo, cada aba o somaria de novo e abriria um vazio.
          child: MediaQuery.removePadding(
            context: context,
            removeTop: texto != null,
            child: widget.child,
          ),
        ),
      ],
    );
  }
}
