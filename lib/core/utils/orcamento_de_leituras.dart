/// Quantas leituras do banco o app gasta, por dia, para deixar as coisas no
/// aparelho.
///
/// POR QUE UM ORÇAMENTO
///
/// O plano grátis dá 50.000 leituras por dia para o ministério inteiro. Baixar
/// os dois hinários (1.221 documentos) e todas as cifras no primeiro dia de
/// cada uma das 30 pessoas seria 36.000 leituras só nisso — e acabada a cota o
/// app inteiro para de ler, não só o que estava baixando. Então o app baixa AOS
/// POUCOS: cada aparelho tem uma cota diária de leituras de preparação, e o
/// que não coube hoje espera amanhã.
///
/// Só entram aqui as leituras que a PREPARAÇÃO provoca. As que a pessoa causa
/// (abrir uma música, trazer um hinário porque pediu) não são limitadas — ela
/// pediu.
///
/// Função pura: o dia e a conta vêm de fora.
library;

class OrcamentoDeLeituras {
  /// Quantas leituras de preparação cada aparelho pode gastar por dia.
  static const int limiteDiario = 250;

  /// O dia da conta (`yyyy-mm-dd`, do relógio do aparelho) e o gasto nele.
  final String dia;
  final int gasto;

  const OrcamentoDeLeituras({required this.dia, required this.gasto});

  static String diaDe(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// O orçamento de hoje: o de ontem não vale, a conta recomeça.
  OrcamentoDeLeituras em(DateTime agora) {
    final hoje = diaDe(agora);
    return hoje == dia ? this : OrcamentoDeLeituras(dia: hoje, gasto: 0);
  }

  int restante(DateTime agora, {int limite = limiteDiario}) {
    final r = limite - em(agora).gasto;
    return r < 0 ? 0 : r;
  }

  OrcamentoDeLeituras gastando(int n, DateTime agora) {
    final h = em(agora);
    return OrcamentoDeLeituras(dia: h.dia, gasto: h.gasto + n);
  }

  Map<String, dynamic> toJson() => {'dia': dia, 'gasto': gasto};

  factory OrcamentoDeLeituras.fromJson(Map<String, dynamic>? j, DateTime agora) =>
      j == null
          ? OrcamentoDeLeituras(dia: diaDe(agora), gasto: 0)
          : OrcamentoDeLeituras(
              dia: (j['dia'] as String?) ?? diaDe(agora),
              gasto: (j['gasto'] as num?)?.toInt() ?? 0);
}
