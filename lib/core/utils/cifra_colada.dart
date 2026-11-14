import 'chord_transposer.dart';

/// Resultado de "Colar cifra": o texto colado do Cifra Club (ou de qualquer
/// site) vira a cifra limpa, a letra pura e o tom, quando o texto o informa.
///
/// Regras:
///   * as quebras de linha e os espaços são preservados — é o que mantém o
///     acorde em cima da sílaba certa;
///   * linhas de acordes são reconhecidas pela MESMA regra do transpositor
///     ([ChordTransposer.isChordLine]): "A", "E" e "Em" no meio de uma frase
///     não viram acorde;
///   * cabeçalhos de site ("… no Apple Music", "Tom: D", "Cifra Club") saem;
///     o tom vai para [tom];
///   * a letra pura tira acordes, tablaturas e acordes entre colchetes, e
///     mantém os rótulos de parte ("[Refrão]") para o cantor se localizar.
class CifraColada {
  final String cifra;
  final String letra;
  final String? tom;
  final int linhasDeAcordes;

  const CifraColada({
    required this.cifra,
    required this.letra,
    required this.tom,
    required this.linhasDeAcordes,
  });

  bool get temAcordes => linhasDeAcordes > 0;

  /// Cabeçalho de site: nunca é letra nem cifra.
  static final RegExp _cabecalho = RegExp(
    r'\bno (apple music|spotify|youtube|deezer|amazon music)\b|cifra ?club|cifraclub\.com|^\s*exibir cifra|^\s*cifra:\s',
    caseSensitive: false,
  );

  /// "Tom: D", "Tom: F#m (forma dos acordes no tom de E)".
  static final RegExp _linhaTom = RegExp(
    r'^\s*tom:?\s*([A-G][#b]?m?)\b',
    caseSensitive: false,
  );

  /// Parte da música entre colchetes no começo da linha: [Intro], [Refrão].
  static final RegExp _parte = RegExp(r'^\s*\[([^\]\n]+)\]\s*(.*)$');

  /// Acorde entre colchetes no meio da letra: [G]Eu te louvarei.
  static final RegExp _acordeEntreColchetes = RegExp(r'\[([^\]\n]*)\]');

  /// Tablatura: "E|---0---", "B|-----|".
  static final RegExp _tablatura = RegExp(r'^\s*[eEBGDAb]\|');

  static String _normalizar(String bruto) => bruto
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .replaceAll(' ', ' ')
      .replaceAll(' ', ' ')
      .replaceAll('\t', '    ');

  static bool _ehAcorde(String token) =>
      ChordTransposer.isChordLine(token.trim());

  /// Junta linhas vazias repetidas e tira as das pontas.
  static String _compactar(List<String> linhas) {
    final out = <String>[];
    for (final l in linhas) {
      if (l.trim().isEmpty && (out.isEmpty || out.last.trim().isEmpty)) continue;
      out.add(l);
    }
    while (out.isNotEmpty && out.last.trim().isEmpty) {
      out.removeLast();
    }
    return out.join('\n');
  }

  static CifraColada analisar(String bruto) {
    final linhas = _normalizar(bruto)
        .split('\n')
        .map((l) => l.replaceFirst(RegExp(r'\s+$'), ''))
        .toList();

    String? tom;
    final cifra = <String>[];
    final letra = <String>[];
    var acordes = 0;

    for (final linha in linhas) {
      final mTom = _linhaTom.firstMatch(linha);
      if (mTom != null && linha.trim().length <= 60) {
        tom ??= mTom.group(1);
        continue;
      }
      if (_cabecalho.hasMatch(linha)) continue;

      cifra.add(linha);

      if (_tablatura.hasMatch(linha)) continue;
      if (ChordTransposer.isChordLine(linha)) {
        acordes++;
        continue;
      }

      final mParte = _parte.firstMatch(linha);
      if (mParte != null && !_ehAcorde(mParte.group(1)!)) {
        final resto = mParte.group(2)!;
        if (resto.trim().isEmpty || ChordTransposer.isChordLine(resto)) {
          if (resto.trim().isNotEmpty) acordes++;
          letra.add('[${mParte.group(1)!.trim()}]');
          continue;
        }
      }

      // Acordes entre colchetes no meio da letra: tira só os que são acorde.
      var semColchetes = linha;
      if (_acordeEntreColchetes.hasMatch(linha)) {
        var achou = false;
        semColchetes = linha.replaceAllMapped(_acordeEntreColchetes, (m) {
          final dentro = m.group(1) ?? '';
          if (_ehAcorde(dentro)) {
            achou = true;
            return '';
          }
          return m.group(0)!;
        });
        if (achou) acordes++;
      }
      letra.add(semColchetes.replaceAll(RegExp(r' {2,}'), ' ').trimRight());
    }

    return CifraColada(
      cifra: _compactar(cifra),
      letra: _compactar(letra.map((l) => l.trimLeft()).toList()),
      tom: tom,
      linhasDeAcordes: acordes,
    );
  }

  /// O texto tem cara de cifra (para exibir em fonte de largura fixa)?
  static bool pareceCifra(String texto) {
    if (texto.trim().isEmpty) return false;
    var n = 0;
    for (final l in _normalizar(texto).split('\n')) {
      if (ChordTransposer.isChordLine(l)) {
        n++;
        if (n >= 2) return true;
      }
    }
    return false;
  }

  /// Letra pura de um texto que pode ser cifra (para quem canta).
  static String letraDe(String texto) =>
      pareceCifra(texto) ? analisar(texto).letra : texto;

  /// Endereço da busca do Cifra Club com o nome já digitado. Só abre a
  /// página do site no navegador; o app não lê nada de lá.
  static Uri buscaNoCifraClub(String musica, [String artista = '']) {
    final termo = [musica.trim(), artista.trim()].where((s) => s.isNotEmpty).join(' ');
    return Uri.https('www.cifraclub.com.br', '/', {'q': termo});
  }
}
