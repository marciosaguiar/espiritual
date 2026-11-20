/// O que fazer quando duas pessoas editam a mesma música, uma delas sem
/// internet.
///
/// A POLÍTICA (decidida aqui, uma vez, e repetida na tela):
///
/// 1. A edição é por CAMPO, não pela música inteira. Quem mudou só o tom não
///    briga com quem mudou só o nome.
/// 2. Cada edição guarda o valor que o campo tinha QUANDO A PESSOA COMEÇOU
///    (`base`). Ao enviar, o app compara com o que está no banco agora:
///    - igual à base: ninguém mexeu — a edição entra;
///    - já igual ao valor novo: já está lá — nada a fazer;
///    - OUTRO valor: alguém mudou antes. **Quem chegou primeiro ao banco
///      vence, e a edição que chegou depois NÃO sobrescreve.**
/// 3. Quem perdeu é AVISADO, com o valor que ficou e o valor que era dele, e
///    pode reaplicar o seu por cima. Nada some em silêncio — nem o texto de
///    uma cifra que levou uma hora para ser digitada.
///
/// POR QUE "QUEM CHEGOU PRIMEIRO" E NÃO "QUEM EDITOU PRIMEIRO": o relógio do
/// aparelho que ficou offline não vale nada para ordenar (pode estar errado, e
/// a edição pode ter sido feita no sábado e enviada na segunda). O banco é a
/// única ordem em que todos concordam.
///
/// Função pura: recebe os mapas, devolve a decisão. Quem grava é outro.
library;

/// Um campo que a pessoa mudou: o que havia e o que ela pôs.
class CampoEditado {
  final Object? base;
  final Object? novo;
  const CampoEditado({required this.base, required this.novo});

  Map<String, dynamic> toJson() => {'base': base, 'novo': novo};

  factory CampoEditado.fromJson(Map<String, dynamic> j) =>
      CampoEditado(base: j['base'], novo: j['novo']);
}

/// Um campo em que a edição perdeu.
class PerdaDeCampo {
  final String campo;

  /// O que a pessoa tinha posto.
  final Object? minha;

  /// O que ficou no banco.
  final Object? atual;

  const PerdaDeCampo(
      {required this.campo, required this.minha, required this.atual});

  Map<String, dynamic> toJson() =>
      {'campo': campo, 'minha': minha, 'atual': atual};

  factory PerdaDeCampo.fromJson(Map<String, dynamic> j) => PerdaDeCampo(
      campo: j['campo'] as String, minha: j['minha'], atual: j['atual']);
}

class ResultadoDaFusao {
  /// O que vai para o banco: só os campos que entram.
  final Map<String, Object?> aplicar;

  /// Os campos em que alguém chegou antes.
  final List<PerdaDeCampo> perdas;

  /// Os campos que já estavam como a pessoa queria.
  final List<String> jaIguais;

  const ResultadoDaFusao(
      {required this.aplicar, required this.perdas, required this.jaIguais});

  bool get nadaAGravar => aplicar.isEmpty;
}

/// Igualdade profunda de valores de documento (texto, número, lista, mapa).
bool valoresIguais(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return false;
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final k in a.keys) {
      if (!b.containsKey(k) || !valoresIguais(a[k], b[k])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!valoresIguais(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}

/// Decide, campo a campo, o que entra.
///
/// [servidor] é o documento como está AGORA no banco; campo ausente conta
/// como nulo (é o que um campo que nunca foi gravado vale).
ResultadoDaFusao fundirEdicao({
  required Map<String, CampoEditado> meus,
  required Map<String, Object?> servidor,
}) {
  final aplicar = <String, Object?>{};
  final perdas = <PerdaDeCampo>[];
  final jaIguais = <String>[];

  for (final e in meus.entries) {
    final campo = e.key;
    final atual = servidor[campo];
    if (valoresIguais(atual, e.value.novo)) {
      jaIguais.add(campo);
    } else if (valoresIguais(atual, e.value.base)) {
      aplicar[campo] = e.value.novo;
    } else {
      perdas.add(
          PerdaDeCampo(campo: campo, minha: e.value.novo, atual: atual));
    }
  }
  return ResultadoDaFusao(
      aplicar: aplicar, perdas: perdas, jaIguais: jaIguais);
}

/// Junta duas edições do MESMO documento feitas uma depois da outra, ainda
/// sem internet: vale o valor mais novo de cada campo, e a BASE é a do
/// começo de tudo (a mais antiga) — é contra ela que o banco será conferido.
///
/// Campo que voltou ao que era no começo some: não há o que enviar.
Map<String, CampoEditado> juntarEdicoes(
  Map<String, CampoEditado> anterior,
  Map<String, CampoEditado> nova,
) {
  final saida = <String, CampoEditado>{...anterior};
  for (final e in nova.entries) {
    final antiga = anterior[e.key];
    saida[e.key] = CampoEditado(
      base: antiga != null ? antiga.base : e.value.base,
      novo: e.value.novo,
    );
  }
  saida.removeWhere((_, c) => valoresIguais(c.base, c.novo));
  return saida;
}
