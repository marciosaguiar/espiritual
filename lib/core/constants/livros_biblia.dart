/// Os 66 livros, na ordem canônica, com o nome que aparece na tela.
///
/// Ficam aqui, e não dentro de cada arquivo de tradução, porque são os mesmos
/// para todas: repetir 66 nomes em cada arquivo custaria espaço por nada, e
/// faria uma tradução nova poder discordar do nome de um livro.
///
/// As siglas são as do arquivo de texto, em minúsculas e com acento — `êx`,
/// `jó` —, e é por elas que o app casa nome e conteúdo.
library;

enum Testamento { antigo, novo }

class LivroBiblia {
  final String sigla;
  final String nome;
  final Testamento testamento;

  const LivroBiblia(this.sigla, this.nome, this.testamento);

  bool get ehAntigo => testamento == Testamento.antigo;

  /// Nome sem acento e em minúsculas, para a busca não exigir acentuação.
  /// Quem procura "genesis" no teclado do celular tem de achar Gênesis.
  String get buscavel => _semAcento(nome.toLowerCase());

  static String _semAcento(String texto) {
    const de = 'áàâãäéèêëíìîïóòôõöúùûüçñ';
    const para = 'aaaaaeeeeiiiiooooouuuucn';
    final b = StringBuffer();
    for (final c in texto.split('')) {
      final i = de.indexOf(c);
      b.write(i >= 0 ? para[i] : c);
    }
    return b.toString();
  }
}

const List<LivroBiblia> livrosDaBiblia = [
  // ── Antigo Testamento ────────────────────────────────────────────────────
  LivroBiblia('gn', 'Gênesis', Testamento.antigo),
  LivroBiblia('êx', 'Êxodo', Testamento.antigo),
  LivroBiblia('lv', 'Levítico', Testamento.antigo),
  LivroBiblia('nm', 'Números', Testamento.antigo),
  LivroBiblia('dt', 'Deuteronômio', Testamento.antigo),
  LivroBiblia('js', 'Josué', Testamento.antigo),
  LivroBiblia('jz', 'Juízes', Testamento.antigo),
  LivroBiblia('rt', 'Rute', Testamento.antigo),
  LivroBiblia('1sm', '1 Samuel', Testamento.antigo),
  LivroBiblia('2sm', '2 Samuel', Testamento.antigo),
  LivroBiblia('1rs', '1 Reis', Testamento.antigo),
  LivroBiblia('2rs', '2 Reis', Testamento.antigo),
  LivroBiblia('1cr', '1 Crônicas', Testamento.antigo),
  LivroBiblia('2cr', '2 Crônicas', Testamento.antigo),
  LivroBiblia('ed', 'Esdras', Testamento.antigo),
  LivroBiblia('ne', 'Neemias', Testamento.antigo),
  LivroBiblia('et', 'Ester', Testamento.antigo),
  LivroBiblia('jó', 'Jó', Testamento.antigo),
  LivroBiblia('sl', 'Salmos', Testamento.antigo),
  LivroBiblia('pv', 'Provérbios', Testamento.antigo),
  LivroBiblia('ec', 'Eclesiastes', Testamento.antigo),
  LivroBiblia('ct', 'Cantares', Testamento.antigo),
  LivroBiblia('is', 'Isaías', Testamento.antigo),
  LivroBiblia('jr', 'Jeremias', Testamento.antigo),
  LivroBiblia('lm', 'Lamentações', Testamento.antigo),
  LivroBiblia('ez', 'Ezequiel', Testamento.antigo),
  LivroBiblia('dn', 'Daniel', Testamento.antigo),
  LivroBiblia('os', 'Oseias', Testamento.antigo),
  LivroBiblia('jl', 'Joel', Testamento.antigo),
  LivroBiblia('am', 'Amós', Testamento.antigo),
  LivroBiblia('ob', 'Obadias', Testamento.antigo),
  LivroBiblia('jn', 'Jonas', Testamento.antigo),
  LivroBiblia('mq', 'Miqueias', Testamento.antigo),
  LivroBiblia('na', 'Naum', Testamento.antigo),
  LivroBiblia('hc', 'Habacuque', Testamento.antigo),
  LivroBiblia('sf', 'Sofonias', Testamento.antigo),
  LivroBiblia('ag', 'Ageu', Testamento.antigo),
  LivroBiblia('zc', 'Zacarias', Testamento.antigo),
  LivroBiblia('ml', 'Malaquias', Testamento.antigo),

  // ── Novo Testamento ──────────────────────────────────────────────────────
  LivroBiblia('mt', 'Mateus', Testamento.novo),
  LivroBiblia('mc', 'Marcos', Testamento.novo),
  LivroBiblia('lc', 'Lucas', Testamento.novo),
  LivroBiblia('jo', 'João', Testamento.novo),
  LivroBiblia('at', 'Atos', Testamento.novo),
  LivroBiblia('rm', 'Romanos', Testamento.novo),
  LivroBiblia('1co', '1 Coríntios', Testamento.novo),
  LivroBiblia('2co', '2 Coríntios', Testamento.novo),
  LivroBiblia('gl', 'Gálatas', Testamento.novo),
  LivroBiblia('ef', 'Efésios', Testamento.novo),
  LivroBiblia('fp', 'Filipenses', Testamento.novo),
  LivroBiblia('cl', 'Colossenses', Testamento.novo),
  LivroBiblia('1ts', '1 Tessalonicenses', Testamento.novo),
  LivroBiblia('2ts', '2 Tessalonicenses', Testamento.novo),
  LivroBiblia('1tm', '1 Timóteo', Testamento.novo),
  LivroBiblia('2tm', '2 Timóteo', Testamento.novo),
  LivroBiblia('tt', 'Tito', Testamento.novo),
  LivroBiblia('fm', 'Filemom', Testamento.novo),
  LivroBiblia('hb', 'Hebreus', Testamento.novo),
  LivroBiblia('tg', 'Tiago', Testamento.novo),
  LivroBiblia('1pe', '1 Pedro', Testamento.novo),
  LivroBiblia('2pe', '2 Pedro', Testamento.novo),
  LivroBiblia('1jo', '1 João', Testamento.novo),
  LivroBiblia('2jo', '2 João', Testamento.novo),
  LivroBiblia('3jo', '3 João', Testamento.novo),
  LivroBiblia('jd', 'Judas', Testamento.novo),
  LivroBiblia('ap', 'Apocalipse', Testamento.novo),
];

/// Nome do livro pela sigla; a própria sigla, se for desconhecida — assim uma
/// tradução futura com um livro a mais aparece, em vez de sumir.
String nomeDoLivro(String sigla) {
  for (final l in livrosDaBiblia) {
    if (l.sigla == sigla) return l.nome;
  }
  return sigla;
}
