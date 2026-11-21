import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/utils/uso_de_leituras.dart';
import 'contador_de_leituras.dart';

/// O freio automático do plano grátis.
///
/// Passou de 80% das 50 mil leituras do dia, estimadas por todos os aparelhos
/// juntos: o app suspende o que NÃO é essencial até amanhã — a preparação em
/// segundo plano, a atualização das músicas e das pessoas, o histórico de
/// cultos. O que a pessoa precisa para o culto (a escala de agora, a cifra que
/// abriu, o chat, confirmar presença) continua.
///
/// Ninguém vê isto na tela, exceto o líder, na Saúde do sistema: um app que
/// se segura sozinho e conta para todo mundo ensina a ter medo dele.
///
/// Custa UMA leitura (`usoDiario/{hoje}`) a cada dez minutos por aparelho, no
/// máximo, somada ao que este aparelho ainda não gravou.
class ModoEconomia extends ChangeNotifier {
  ModoEconomia._();
  static final ModoEconomia instancia = ModoEconomia._();

  static const Duration validade = Duration(minutes: 10);

  UsoDoDia? _uso;
  DateTime? _em;
  String? _dia;

  /// O último uso conhecido DE HOJE, com o que este aparelho ainda não gravou.
  ///
  /// O uso de ontem não vale: a cota vira à meia-noite do Pacífico, e um
  /// aparelho que ficou aberto a noite toda continuaria em modo de economia —
  /// ou a mostrar 90% — com o dia já zerado.
  UsoDoDia? get uso {
    if (_uso == null || _dia != diaDaCota(DateTime.now())) return null;
    return _uso!.somando(ContadorDeLeituras.instancia.pendente);
  }

  NivelDeUso get nivel => uso?.nivel ?? NivelDeUso.normal;

  /// O app está se segurando?
  bool get ligado => nivel == NivelDeUso.economia;

  /// Confere o uso do dia no banco, no máximo a cada dez minutos.
  Future<void> atualizar({bool forcar = false, DateTime? agora}) async {
    final t = agora ?? DateTime.now();
    final dia = diaDaCota(t);
    final velho = _em == null || t.difference(_em!) > validade || _dia != dia;
    if (!forcar && !velho) return;
    final lido = await ContadorDeLeituras.lerDoDia(dia);
    if (lido == null) return; // sem resposta: fica com o que sabia
    _uso = lido;
    _em = t;
    _dia = dia;
    notifyListeners();
  }

  @visibleForTesting
  void definirParaTeste(UsoDoDia? u, {String? dia}) {
    _uso = u;
    _em = DateTime.now();
    _dia = dia ?? diaDaCota(DateTime.now());
    notifyListeners();
  }
}
