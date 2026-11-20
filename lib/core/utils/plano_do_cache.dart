/// Quais itens um cache com limite de espaço precisa soltar para caber mais um.
///
/// Função pura: o cache de áudios (e qualquer outro) diz o que tem e quanto o
/// novo ocupa, e recebe a lista do que apagar. Sai primeiro o que foi usado
/// há mais tempo — ouvir de novo um áudio de ontem é mais provável que ouvir
/// um de três semanas atrás.
library;

class ItemDoCache {
  final String id;
  final int bytes;
  final DateTime usadoEm;
  const ItemDoCache(this.id, this.bytes, this.usadoEm);
}

/// Os ids a apagar para que [itens] + [novoTamanho] caibam em [limite].
///
/// Se o item novo sozinho passa do limite, devolve `null`: guardar um item
/// maior que o cache inteiro o esvaziaria só para o próprio item ocupar tudo.
/// Quem pede decide não guardar.
List<String>? planejarDespejo({
  required List<ItemDoCache> itens,
  required int novoTamanho,
  required int limite,
}) {
  if (novoTamanho > limite) return null;
  var total = novoTamanho + itens.fold<int>(0, (s, i) => s + i.bytes);
  if (total <= limite) return const [];
  final maisAntigoPrimeiro = [...itens]
    ..sort((a, b) {
      final c = a.usadoEm.compareTo(b.usadoEm);
      return c != 0 ? c : a.id.compareTo(b.id); // desempate estável
    });
  final saem = <String>[];
  for (final i in maisAntigoPrimeiro) {
    if (total <= limite) break;
    saem.add(i.id);
    total -= i.bytes;
  }
  return saem;
}
