import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/cifra_colada.dart';
import '../../../data/services/local_storage_service.dart';
import '../../providers/auth_provider.dart';
import '../../screens/songs/add_song_screen.dart';
import '../common/glass.dart';

/// "Toque para usar a cifra copiada", quando a pessoa volta do Cifra Club.
///
/// POR QUE ELA NÃO LÊ A ÁREA DE TRANSFERÊNCIA SOZINHA
///
/// No iPhone, ler o que está copiado exige um toque da pessoa — o Safari
/// mostra um pedido de permissão. Então a faixa não pode ler para decidir se
/// aparece: isso pediria permissão antes de ter o que oferecer, que é o
/// caminho mais rápido para a pessoa negar para sempre.
///
/// O sinal usado é outro, e é mais forte: a pessoa acabou de tocar em
/// "Buscar no Cifra Club", e o app guardou isso. Se ela voltou em menos de
/// 30 minutos, o que está copiado é quase certamente a cifra que ela foi
/// buscar. A leitura acontece só no toque — e, se o que vier não parecer
/// cifra, a faixa diz isso em vez de abrir um cadastro vazio.
class FaixaCifraCopiada extends StatefulWidget {
  const FaixaCifraCopiada({super.key});

  @override
  State<FaixaCifraCopiada> createState() => _FaixaCifraCopiadaState();
}

class _FaixaCifraCopiadaState extends State<FaixaCifraCopiada>
    with WidgetsBindingObserver {
  String? _procurado;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _conferir();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState estado) {
    // É aqui que a faixa aparece: a pessoa saiu para o navegador, copiou a
    // cifra e voltou. `resumed` é o evento desse retorno, e na web ele chega
    // quando a aba volta a ficar visível.
    if (estado == AppLifecycleState.resumed) _conferir();
  }

  void _conferir() {
    final novo = LocalStorageService.idaRecenteAoCifraClub();
    if (novo != _procurado && mounted) setState(() => _procurado = novo);
  }

  Future<void> _usar() async {
    final dados = await Clipboard.getData(Clipboard.kTextPlain);
    final texto = dados?.text ?? '';
    if (!mounted) return;

    if (texto.trim().isEmpty) {
      _dizer('Não achei nada copiado. Copie a cifra no Cifra Club e volte.');
      return;
    }

    // A mesma análise do campo "Colar cifra": se não há linha de acordes
    // nem texto suficiente, isto não é uma cifra — e abrir o cadastro com
    // lixo dentro seria pior que não oferecer nada.
    final r = CifraColada.analisar(texto);
    if (!r.temAcordes && r.letra.trim().length < 40) {
      _dizer('O que está copiado não parece uma cifra nem uma letra.');
      return;
    }

    await LocalStorageService.esquecerIdaAoCifraClub();
    if (!mounted) return;
    setState(() => _procurado = null);
    Navigator.push(
      context,
      GlassPageRoute(builder: (_) => AddSongScreen(cifraInicial: texto)),
    );
  }

  void _dizer(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      duration: const Duration(seconds: 4),
    ));
  }

  Future<void> _dispensar() async {
    await LocalStorageService.esquecerIdaAoCifraClub();
    if (mounted) setState(() => _procurado = null);
  }

  @override
  Widget build(BuildContext context) {
    // Só o líder cadastra música no banco. Para um levita esta faixa levaria
    // a um cadastro que a regra recusa no fim.
    if (!context.watch<AuthProvider>().isAdmin) return const SizedBox.shrink();
    final procurado = _procurado;
    if (procurado == null) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Material(
        color: AppColors.blue.withValues(alpha: isDark ? 0.22 : 0.10),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: _usar,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 11, 6, 11),
            child: Row(
              children: [
                const Icon(Icons.content_paste_rounded,
                    size: 20, color: AppColors.blue),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Toque para usar a cifra copiada',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? AppColors.textPrimaryDark
                              : AppColors.textPrimaryLight,
                        ),
                      ),
                      if (procurado.isNotEmpty)
                        Text(
                          'Você buscou "$procurado"',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 12,
                            color: isDark
                                ? AppColors.textSecondaryDark
                                : AppColors.textSecondaryLight,
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  tooltip: 'Dispensar',
                  onPressed: _dispensar,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
