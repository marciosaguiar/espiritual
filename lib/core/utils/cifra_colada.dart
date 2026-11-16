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

  /// Título e artista lidos do cabeçalho do site, quando ele veio colado.
  ///
  /// Servem para duas coisas: sair do corpo da cifra, e a tela poder oferecer
  /// "o site diz que o artista é Joshua Coleman — usar?".
  final String? titulo;
  final String? artista;

  final int linhasDeAcordes;

  const CifraColada({
    required this.cifra,
    required this.letra,
    required this.tom,
    this.titulo,
    this.artista,
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

  /// O mesmo tom, em qualquer ponto da linha. Só vale dentro de uma linha já
  /// reconhecida como cabeçalho de site, onde não há letra para confundir:
  /// solto, pegaria o "tom" de um verso qualquer.
  static final RegExp _tomNoCabecalho = RegExp(
    r'\btom:\s*([A-G][#b]?m?)\b',
    caseSensitive: false,
  );

  /// Rótulos do cabeçalho do Cifra Club GRUDADOS na linha anterior.
  ///
  /// Copiar a página cola o cabeçalho sem as quebras de linha que a tela
  /// mostrava: "Tom: DAfinação: E A D G B E" e "Sou Grato Por Seu AmorGet
  /// de: Joshua Coleman" foram os dois casos reais. Grudado, o "Tom:" não era
  /// reconhecido — a música ficava com o tom antigo e a cifra em outro, que é
  /// o erro mais caro que isto podia dar: o levita toca no tom errado.
  ///
  /// O corte é de largura zero e só acontece ANTES de um rótulo conhecido.
  /// Cortar em toda troca de minúscula para maiúscula partiria nomes
  /// ("McDonald") e títulos no meio.
  /// O corte é EXATAMENTE antes do rótulo, sem nada opcional na frente.
  ///
  /// A primeira versão permitia até seis letras antes do "de:", para pegar o
  /// "Get" que o botão do site cola no texto. Resultado: a expressão casava
  /// em toda posição dentro dessas seis letras, e "Amor" virou "m\no\nr".
  /// Um padrão de largura zero não perdoa folga — ele casa em todo lugar
  /// onde a folga caiba.
  ///
  /// E "de:/por:" NÃO entra aqui: "Dificuldade: Fácil" tem "de:" dentro, e a
  /// palavra era cortada no meio ("Dificulda" / "de: Fácil"), com "Fácil"
  /// virando o artista. O artista é separado em
  /// [_separarTituloDoArtista], que sabe ignorar linha de rótulo.
  static final RegExp _grude = RegExp(
    r'(?<=[\wÀ-ú)\]])'
    r'(?=Tom:|Afina[çc][ãa]o:|Capotraste|Instrumento:|Tempo:|Dificuldade)',
  );

  /// "de: Joshua Coleman", "por: Fulano" — e com uma palavra solta na frente,
  /// que é como o botão do site entra no texto copiado ("Get de: ...").
  static final RegExp _linhaArtista = RegExp(
    r'^\s*(?:[A-Za-zÀ-ú]{1,6}\s+)?(?:de|por):\s*(.+)$',
    caseSensitive: false,
  );

  /// Os outros rótulos do cabeçalho: nunca são letra nem cifra.
  ///
  /// "Afinação: E A D G B E" é o pior deles para deixar passar, porque a
  /// linha é feita de nomes de acorde — ela entrava na cifra como se fosse
  /// uma linha de acordes de verdade.
  static final RegExp _outrosRotulos = RegExp(
    r'^\s*(afina[çc][ãa]o|capotraste|instrumento|tempo|dificuldade|'
    r'intérprete|interprete|composi[çc][ãa]o|compositor)\s*:?',
    caseSensitive: false,
  );

  /// Quantas linhas, do começo, contam como cabeçalho.
  ///
  /// Tudo o que é heurística de cabeçalho fica presa aqui dentro. Solta no
  /// texto inteiro, ela comeria verso ("de: " aparece em letra de música) —
  /// e comer um verso é pior que deixar um rótulo passar.
  static const int _linhasDeCabecalho = 8;

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

  /// Mesmo texto, ignorando caixa, acentos e espaço sobrando.
  static String _chave(String t) {
    const de = 'áàâãäéèêëíìîïóòôõöúùûüçñ';
    const para = 'aaaaaeeeeiiiiooooouuuucn';
    var s = t.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');
    for (var i = 0; i < de.length; i++) {
      s = s.replaceAll(de[i], para[i]);
    }
    return s.replaceAll(RegExp(r'[^a-z0-9 ]'), '');
  }

  /// O marcador de artista do site: "de: Fulano", "por: Fulano".
  static final RegExp _marcadorDeArtista =
      RegExp(r'(?:de|por):\s', caseSensitive: false);

  /// Separa o título do artista quando vieram grudados SEM espaço.
  ///
  /// "Sou Grato Por Seu AmorGet de: Joshua Coleman" — o grude está em
  /// "AmorGet", não antes do "de:", que tem espaço na frente. A única pista é
  /// a troca de minúscula para maiúscula; então o corte é na ÚLTIMA troca
  /// antes do marcador, e só em linha que tem marcador.
  ///
  /// Um título com maiúscula no meio de palavra ("McDonald") seria cortado
  /// errado. O estrago, nesse caso, é um título sugerido torto — nunca um
  /// tom errado, que é o que importa não errar aqui.
  static String _separarTituloDoArtista(String linha) {
    // Linha que JÁ é rótulo do site não se corta: "Dificuldade: Fácil" tem
    // "de:" dentro dela.
    if (_outrosRotulos.hasMatch(linha)) return linha;
    final m = _marcadorDeArtista.firstMatch(linha);
    if (m == null) return linha;
    var corte = -1;
    for (var i = 1; i < m.start; i++) {
      final antes = linha[i - 1];
      final depois = linha[i];
      final ehMinuscula =
          antes == antes.toLowerCase() && antes != antes.toUpperCase();
      final ehMaiuscula =
          depois == depois.toUpperCase() && depois != depois.toLowerCase();
      if (ehMinuscula && ehMaiuscula) corte = i;
    }
    // Sem troca de caixa, o grude pode ser direto no marcador
    // ("Grandes Coisasde: Fernandinho"): corta ali, se não houver espaço.
    if (corte <= 0 && m.start > 0 &&
        RegExp(r'[A-Za-zÀ-ú]').hasMatch(linha[m.start - 1])) {
      corte = m.start;
    }
    if (corte <= 0) return linha;
    return '${linha.substring(0, corte)}\n${linha.substring(corte)}';
  }

  /// Desgruda os rótulos do cabeçalho, só nas primeiras linhas.
  static List<String> _desgrudarCabecalho(List<String> linhas) {
    final saida = <String>[];
    var naoVazias = 0;
    for (final linha in linhas) {
      final noCabecalho = naoVazias < _linhasDeCabecalho;
      if (linha.trim().isNotEmpty) naoVazias++;
      if (!noCabecalho) {
        saida.add(linha);
        continue;
      }
      for (final pedaco in linha.replaceAll(_grude, '\n').split('\n')) {
        saida.addAll(_separarTituloDoArtista(pedaco).split('\n'));
      }
    }
    return saida;
  }

  /// O cabeçalho do site: o que ele diz, e quais linhas saem do corpo.
  ///
  /// `nomeConhecido` e `artistaConhecido` são o nome e o artista que a música
  /// JÁ tem no app. Com eles, tirar o título do corpo é comparação, não
  /// adivinhação — e é por isso que a tela os passa.
  static ({String? tom, String? titulo, String? artista, Set<int> descartar})
      _lerCabecalho(
    List<String> linhas, {
    String? nomeConhecido,
    String? artistaConhecido,
  }) {
    final descartar = <int>{};
    String? tom;
    String? artista;
    String? titulo;

    var naoVazias = 0;
    for (var i = 0; i < linhas.length && naoVazias < _linhasDeCabecalho; i++) {
      final linha = linhas[i];
      if (linha.trim().isEmpty) continue;
      naoVazias++;

      final mTom = _linhaTom.firstMatch(linha);
      if (mTom != null && linha.trim().length <= 60) {
        tom ??= mTom.group(1);
        descartar.add(i);
        continue;
      }
      if (_outrosRotulos.hasMatch(linha)) {
        descartar.add(i);
        continue;
      }
      // Linha de acordes nunca é artista, mesmo com ":" nela.
      final mArt = _linhaArtista.firstMatch(linha);
      if (mArt != null && !ChordTransposer.isChordLine(linha)) {
        artista ??= mArt.group(1)!.trim();
        descartar.add(i);
        continue;
      }
      if (_cabecalho.hasMatch(linha)) {
        tom ??= _tomNoCabecalho.firstMatch(linha)?.group(1);
        descartar.add(i);
        continue;
      }
      if (artistaConhecido != null &&
          _chave(linha) == _chave(artistaConhecido)) {
        descartar.add(i);
        continue;
      }
    }

    // O título é a primeira linha que sobrou do cabeçalho. Tirá-la do corpo
    // exige CERTEZA, porque uma música pode começar com uma linha de letra:
    // ou ela bate com o nome que a música já tem, ou o cabeçalho tinha um
    // artista — e aí é cabeçalho de site, não verso.
    var vistas = 0;
    for (var i = 0; i < linhas.length && vistas < _linhasDeCabecalho; i++) {
      if (linhas[i].trim().isEmpty) continue;
      vistas++;
      if (descartar.contains(i)) continue;
      final linha = linhas[i].trim();
      // Prefixo, e não igualdade: o corte deixa o lixo do botão do site
      // grudado no fim do título ("Sou Grato Por Seu AmorGet"). Até seis
      // letras de sobra ainda é o mesmo título.
      final chaveDaLinha = _chave(linha);
      final chaveDoNome = nomeConhecido == null ? null : _chave(nomeConhecido);
      final bateComONome = chaveDoNome != null &&
          chaveDaLinha.startsWith(chaveDoNome) &&
          chaveDaLinha.length - chaveDoNome.length <= 6;
      if (bateComONome ||
          (artista != null && !ChordTransposer.isChordLine(linha))) {
        titulo = bateComONome ? nomeConhecido : linha;
        descartar.add(i);
      }
      break;
    }

    return (tom: tom, titulo: titulo, artista: artista, descartar: descartar);
  }

  static CifraColada analisar(
    String bruto, {
    String? nomeConhecido,
    String? artistaConhecido,
  }) {
    final linhas = _desgrudarCabecalho(_normalizar(bruto)
        .split('\n')
        .map((l) => l.replaceFirst(RegExp(r'\s+$'), ''))
        .toList());

    final cab = _lerCabecalho(linhas,
        nomeConhecido: nomeConhecido, artistaConhecido: artistaConhecido);
    String? tom = cab.tom;
    final cifra = <String>[];
    final letra = <String>[];
    var acordes = 0;

    for (var i = 0; i < linhas.length; i++) {
      final linha = linhas[i];
      if (cab.descartar.contains(i)) continue;

      final mTom = _linhaTom.firstMatch(linha);
      if (mTom != null && linha.trim().length <= 60) {
        tom ??= mTom.group(1);
        continue;
      }
      if (_cabecalho.hasMatch(linha)) {
        // O Cifra Club entrega o nome do serviço e o tom na MESMA linha
        // ("… no Apple Music Tom: D"). Jogar a linha fora inteira fazia o
        // tom se perder, e o líder tinha de digitá-lo à mão sem saber por quê.
        tom ??= _tomNoCabecalho.firstMatch(linha)?.group(1);
        continue;
      }

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
      titulo: cab.titulo,
      artista: cab.artista,
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
