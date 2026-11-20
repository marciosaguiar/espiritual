/// O tamanho de letra em que as linhas do texto cabem SEM quebrar.
///
/// POR QUE ISTO EXISTE
///
/// Uma letra de hino é escrita em versos: cada linha é uma frase que o
/// ministério canta de uma vez. Quando a tela é estreita para a linha, ela
/// quebra no meio da frase e a continuação parece um verso novo — no
/// telão, no computador do culto, o resultado é uma estrofe que não se lê.
///
/// Em vez de quebrar, a letra encolhe um pouco, até o tamanho em que a linha
/// mais comprida cabe. É só para tela larga (no celular, quem canta quer a
/// letra grande, mesmo que ela quebre) e nunca desce de [minimo]: letra
/// pequena demais não se lê de longe.
///
/// É uma função pura de medida: recebe o texto, o estilo e a largura, e não
/// conhece tela nem provider — por isso tem teste.
library;

import 'package:flutter/painting.dart';

/// O maior tamanho de fonte entre [minimo] e [maximo] em que cada linha de
/// [texto] cabe em [largura] sem quebrar.
///
/// - Se cabe em [maximo], devolve [maximo]: o texto curto não é mexido.
/// - Se NÃO cabe nem em [minimo], devolve [maximo]: a quebra é inevitável, e
///   então vale o tamanho que a pessoa pediu — encolher até o mínimo sem
///   resolver nada só deixaria a letra pior.
double tamanhoQueCabe({
  required String texto,
  required TextStyle estilo,
  required double largura,
  required double maximo,
  double minimo = 16,
}) {
  if (texto.trim().isEmpty || !largura.isFinite || largura <= 0) return maximo;
  if (maximo <= minimo) return maximo;

  final chave = _Chave(texto, estilo.fontFamily, estilo.fontWeight,
      largura.roundToDouble(), maximo, minimo);
  final guardado = _memoria[chave];
  if (guardado != null) return guardado;

  final resultado = _calcular(texto, estilo, largura, maximo, minimo);
  if (_memoria.length >= 16) _memoria.remove(_memoria.keys.first);
  _memoria[chave] = resultado;
  return resultado;
}

/// A largura da linha mais larga de [texto] no tamanho [fonte].
double _larguraMaisLarga(String texto, TextStyle estilo, double fonte) {
  var maior = 0.0;
  for (final linha in texto.split('\n')) {
    if (linha.trim().isEmpty) continue;
    final p = TextPainter(
      text: TextSpan(text: linha, style: estilo.copyWith(fontSize: fonte)),
      textDirection: TextDirection.ltr,
    )..layout();
    if (p.width > maior) maior = p.width;
  }
  return maior;
}

double _calcular(
    String texto, TextStyle estilo, double largura, double maximo, double minimo) {
  final noMaximo = _larguraMaisLarga(texto, estilo, maximo);
  if (noMaximo <= largura) return maximo;

  // A largura do texto cresce com a fonte, quase em linha reta: a conta
  // proporcional dá o palpite, e a conferência abaixo o corrige (o desenho
  // das letras não escala em pixels exatos).
  var tamanho = (maximo * largura / noMaximo).floorToDouble();
  if (tamanho < minimo) {
    return _larguraMaisLarga(texto, estilo, minimo) <= largura
        ? minimo
        : maximo;
  }
  while (tamanho > minimo &&
      _larguraMaisLarga(texto, estilo, tamanho) > largura) {
    tamanho -= 1;
  }
  return tamanho.clamp(minimo, maximo);
}

final _memoria = <_Chave, double>{};

class _Chave {
  final String texto;
  final String? familia;
  final FontWeight? peso;
  final double largura;
  final double maximo;
  final double minimo;
  const _Chave(
      this.texto, this.familia, this.peso, this.largura, this.maximo, this.minimo);

  @override
  bool operator ==(Object o) =>
      o is _Chave &&
      o.texto == texto &&
      o.familia == familia &&
      o.peso == peso &&
      o.largura == largura &&
      o.maximo == maximo &&
      o.minimo == minimo;

  @override
  int get hashCode =>
      Object.hash(texto, familia, peso, largura, maximo, minimo);
}
