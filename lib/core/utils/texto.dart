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
