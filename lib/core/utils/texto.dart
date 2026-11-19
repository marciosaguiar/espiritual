/// Comparar texto como gente compara.
///
/// Quem procura "coracao" quer achar "Coração", e quem procura "SENHOR" quer
/// achar "Senhor". Sem isto, a busca do repertório só encontrava a música se
/// a pessoa acertasse o acento — e ninguém digita acento no celular com
/// pressa, no meio do culto.
library;

const _comAcento = 'áàâãäéèêëíìîïóòôõöúùûüçñý';
const _semAcento = 'aaaaaeeeeiiiiooooouuuucny';

/// O mesmo texto, em minúsculas e sem acento.
String semAcento(String texto) {
  final saida = StringBuffer();
  for (final rune in texto.toLowerCase().runes) {
    final char = String.fromCharCode(rune);
    final i = _comAcento.indexOf(char);
    saida.write(i >= 0 ? _semAcento[i] : char);
  }
  return saida.toString();
}

/// Algum destes campos contém o que foi digitado?
///
/// Busca vazia casa com tudo — é o estado inicial da tela, não um filtro que
/// esconde o repertório inteiro.
bool combina(String busca, Iterable<String> campos) {
  final procurado = semAcento(busca).trim();
  if (procurado.isEmpty) return true;
  for (final campo in campos) {
    if (semAcento(campo).contains(procurado)) return true;
  }
  return false;
}

/// O mesmo texto reduzido ao que importa para comparar NOMES.
///
/// Minúsculas, sem acento, sem pontuação, sem espaço repetido. É o que faz
/// "Grande é o Senhor", "grande e o senhor" e "Grande É O SENHOR!" serem o
/// mesmo nome — e eles são, para quem está cadastrando.
String nomeComparavel(String texto) {
  final sb = StringBuffer();
  var espacoPendente = false;
  for (final rune in semAcento(texto).runes) {
    final c = String.fromCharCode(rune);
    final letra = (c.compareTo('a') >= 0 && c.compareTo('z') <= 0) ||
        (c.compareTo('0') >= 0 && c.compareTo('9') <= 0);
    if (letra) {
      if (espacoPendente && sb.isNotEmpty) sb.write(' ');
      espacoPendente = false;
      sb.write(c);
    } else {
      // Tudo o que não é letra nem número vira separador: ponto, hífen,
      // parêntese, o "·" do título dos hinos.
      espacoPendente = true;
    }
  }
  return sb.toString();
}

/// Quais dos [existentes] são, para gente, o mesmo nome que [nome].
///
/// POR QUE ISTO EXISTE
///
/// Cadastrar a mesma música duas vezes não dá erro nenhum, e o estrago só
/// aparece depois: duas "Grande é o Senhor" na lista, a cifra colada numa e
/// o culto montado com a outra, e o histórico de "tocada pela última vez"
/// partido em dois.
///
/// O que conta como parecido: nome igual depois de normalizado, ou um
/// contido no outro — é este segundo caso que pega "Sou Grato" contra
/// "HC 15 · Sou Grato", que é a MESMA música cadastrada de outro jeito.
///
/// Quatro letras é o piso para a continência valer. Sem ele, "Ele" casaria
/// com meia dúzia de títulos e o aviso perderia o crédito na primeira vez.
List<String> nomesParecidos(String nome, Iterable<String> existentes) {
  final alvo = nomeComparavel(nome);
  if (alvo.length < 3) return const [];
  final achados = <String>[];
  for (final outro in existentes) {
    final c = nomeComparavel(outro);
    if (c.isEmpty) continue;
    final igual = c == alvo;
    final contido = (alvo.length >= 4 && c.contains(alvo)) ||
        (c.length >= 4 && alvo.contains(c));
    if (igual || contido) achados.add(outro);
  }
  return achados;
}
