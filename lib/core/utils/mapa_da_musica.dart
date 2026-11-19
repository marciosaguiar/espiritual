import 'chord_transposer.dart';

/// Uma linha de LETRA: a âncora da sincronização.
///
/// É o único ponto que os dois modos de ler têm em comum. A cifra tem linhas
/// de acorde entre os versos; a versão de quem canta não tem nenhuma. Se o
/// que viajasse entre os aparelhos fosse "linha 12", o tecladista estaria no
/// refrão e a cantora três versos atrás.
class LinhaAncora {
  /// 0, 1, 2… na ordem da música. É ISTO que vai para o Firestore.
  final int indice;

  /// O texto da letra. Viaja junto como conferência: se um aparelho tiver uma
  /// versão diferente da música, o índice sozinho apontaria para outro verso.
  final String texto;

  /// A parte da música ("Intro", "Refrão"), ou vazio.
  final String secao;

  /// Onde esta linha está no texto da cifra e no texto da letra.
  final int naCifra;
  final int naLetra;

  const LinhaAncora({
    required this.indice,
    required this.texto,
    required this.secao,
    required this.naCifra,
    required this.naLetra,
  });
}

/// Uma parte da música, para o botão "próxima parte".
typedef ParteDaMusica = ({String nome, int ancora});

/// A mesma música vista dos dois jeitos, com as âncoras ligando os dois.
///
/// Os dois textos saem da MESMA varredura, de propósito: construir a letra
/// por um caminho e a cifra por outro é o jeito de os dois se separarem com o
/// tempo, e aí a sincronização aponta para lugares diferentes sem ninguém
/// perceber — não dá erro, só desalinha no meio do culto.
class MapaDaMusica {
  final List<String> linhasDaCifra;
  final List<String> linhasDaLetra;
  final List<LinhaAncora> ancoras;
  final List<ParteDaMusica> partes;

  const MapaDaMusica({
    required this.linhasDaCifra,
    required this.linhasDaLetra,
    required this.ancoras,
    required this.partes,
  });

  bool get vazio => ancoras.isEmpty;

  /// A âncora de um índice, limitada ao que existe. Nulo se não há nenhuma.
  LinhaAncora? ancora(int indice) {
    if (ancoras.isEmpty) return null;
    return ancoras[indice.clamp(0, ancoras.length - 1)];
  }

  /// A linha a mostrar, no texto de cada modo.
  int linhaNoTexto(int indiceDaAncora, {required bool cifra}) {
    final a = ancora(indiceDaAncora);
    if (a == null) return 0;
    return cifra ? a.naCifra : a.naLetra;
  }

  /// O começo da próxima parte, para o botão grande do condutor.
  ///
  /// Sem partes marcadas (música colada sem "[Refrão]"), anda de oito em oito
  /// âncoras — mais ou menos uma estrofe, e melhor que não fazer nada.
  int proximaParte(int indiceAtual) {
    for (final p in partes) {
      if (p.ancora > indiceAtual) return p.ancora;
    }
    if (ancoras.isEmpty) return 0;
    return (indiceAtual + 8).clamp(0, ancoras.length - 1);
  }

  int parteAnterior(int indiceAtual) {
    int alvo = 0;
    for (final p in partes) {
      if (p.ancora < indiceAtual) {
        alvo = p.ancora;
      } else {
        break;
      }
    }
    if (partes.isEmpty && ancoras.isNotEmpty) {
      return (indiceAtual - 8).clamp(0, ancoras.length - 1);
    }
    return alvo;
  }

  /// Em que parte está esta âncora, para a tela dizer "Refrão".
  String secaoDe(int indiceDaAncora) => ancora(indiceDaAncora)?.secao ?? '';

  /// Lê a cifra (ou só a letra) e devolve os dois textos com as âncoras.
  ///
  /// Classificação de cada linha, na ordem:
  ///   vazia          → fica nos dois, para o espaçamento; não é âncora
  ///   [Refrão]       → fica nos dois, marca a parte; não é âncora
  ///   linha de acorde→ só na cifra; não é âncora
  ///   tablatura      → só na cifra; não é âncora
  ///   o resto        → LETRA: fica nos dois, e é âncora
  static MapaDaMusica mapear(String texto) {
    final cifra = <String>[];
    final letra = <String>[];
    final ancoras = <LinhaAncora>[];
    final partes = <ParteDaMusica>[];

    var secaoAtual = '';
    var parteEsperandoAncora = '';

    for (final bruta in texto
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n')) {
      final linha = bruta.replaceFirst(RegExp(r'\s+$'), '');

      if (linha.trim().isEmpty) {
        cifra.add('');
        letra.add('');
        continue;
      }

      final parte = _rotuloDeParte(linha);
      if (parte != null) {
        secaoAtual = parte;
        // A parte só entra na lista quando a primeira LETRA dela aparece:
        // "[Intro] D A G" não tem verso nenhum, e pular para ela deixaria a
        // tela parada num lugar sem texto.
        parteEsperandoAncora = parte;
        cifra.add(linha);
        letra.add('[$parte]');
        continue;
      }

      if (_ehTablatura(linha) || ChordTransposer.isChordLine(linha)) {
        cifra.add(linha);
        continue;
      }

      final indice = ancoras.length;
      ancoras.add(LinhaAncora(
        indice: indice,
        texto: linha.trim(),
        secao: secaoAtual,
        naCifra: cifra.length,
        naLetra: letra.length,
      ));
      if (parteEsperandoAncora.isNotEmpty) {
        partes.add((nome: parteEsperandoAncora, ancora: indice));
        parteEsperandoAncora = '';
      }
      cifra.add(linha);
      letra.add(linha.trimLeft());
    }

    return MapaDaMusica(
      linhasDaCifra: cifra,
      linhasDaLetra: letra,
      ancoras: ancoras,
      partes: partes,
    );
  }

  /// "[Refrão]", "[Intro] D A G" → "Refrão", "Intro". Nulo se não é rótulo.
  static String? _rotuloDeParte(String linha) {
    final m = RegExp(r'^\s*\[([^\]\n]+)\]\s*(.*)$').firstMatch(linha);
    if (m == null) return null;
    final dentro = m.group(1)!.trim();
    // "[G]Eu te louvarei" é acorde no meio da letra, não rótulo de parte.
    if (dentro.isEmpty || ChordTransposer.isChordLine(dentro)) return null;
    final resto = m.group(2)!.trim();
    // "[Refrão] Eu te louvarei" tem letra na mesma linha: não é só rótulo.
    if (resto.isNotEmpty && !ChordTransposer.isChordLine(resto)) return null;
    return dentro;
  }

  static bool _ehTablatura(String linha) => ehTablatura(linha);
}

/// Esta linha é tablatura? (`e|---3---`, `B|--0--`)
///
/// Era privada do mapa. Virou pública porque a tela de leitura precisa da
/// MESMA resposta para poder esconder tablatura: duas contas diferentes para
/// "isto é tablatura" acabariam discordando, e aí o músico esconderia as
/// tablaturas e sobraria meia tablatura na tela.
bool ehTablatura(String linha) => RegExp(r'^\s*[eEBGDAb]\|').hasMatch(linha);

/// O mesmo texto sem as linhas de tablatura.
///
/// POR QUE ISTO EXISTE
///
/// Cifra do Cifra Club vem com tablatura da introdução, e ela ocupa seis
/// linhas para dizer o que o tecladista e a cantora não vão tocar. Num
/// celular, isso é meia tela de rolagem antes do primeiro verso. Quem toca
/// violão quer; os outros, não — daí ser opção, e não decisão nossa.
///
/// Linha em branco que sobra no lugar da tablatura é juntada: três linhas
/// vazias seguidas, no meio da música, parecem que falta algo.
String semTablaturas(String texto) {
  final saida = <String>[];
  for (final linha in texto.split('\n')) {
    if (ehTablatura(linha)) continue;
    final vazia = linha.trim().isEmpty;
    if (vazia && saida.isNotEmpty && saida.last.trim().isEmpty) continue;
    saida.add(linha);
  }
  // Sobra em branco no começo e no fim não serve a ninguém.
  while (saida.isNotEmpty && saida.first.trim().isEmpty) {
    saida.removeAt(0);
  }
  while (saida.isNotEmpty && saida.last.trim().isEmpty) {
    saida.removeLast();
  }
  return saida.join('\n');
}
