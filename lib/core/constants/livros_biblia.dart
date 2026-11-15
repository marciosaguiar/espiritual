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

  /// Código de três letras do padrão USFM (`JHN`, `SNG`), que é o que o
  /// YouVersion usa no endereço do capítulo. É por ele que o botão "ler na
  /// NVI" abre o capítulo certo, em vez de uma busca.
  final String usfm;

  const LivroBiblia(this.sigla, this.nome, this.testamento, [this.usfm = '']);

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
  LivroBiblia('gn', 'Gênesis', Testamento.antigo, 'GEN'),
  LivroBiblia('êx', 'Êxodo', Testamento.antigo, 'EXO'),
  LivroBiblia('lv', 'Levítico', Testamento.antigo, 'LEV'),
  LivroBiblia('nm', 'Números', Testamento.antigo, 'NUM'),
  LivroBiblia('dt', 'Deuteronômio', Testamento.antigo, 'DEU'),
  LivroBiblia('js', 'Josué', Testamento.antigo, 'JOS'),
  LivroBiblia('jz', 'Juízes', Testamento.antigo, 'JDG'),
  LivroBiblia('rt', 'Rute', Testamento.antigo, 'RUT'),
  LivroBiblia('1sm', '1 Samuel', Testamento.antigo, '1SA'),
  LivroBiblia('2sm', '2 Samuel', Testamento.antigo, '2SA'),
  LivroBiblia('1rs', '1 Reis', Testamento.antigo, '1KI'),
  LivroBiblia('2rs', '2 Reis', Testamento.antigo, '2KI'),
  LivroBiblia('1cr', '1 Crônicas', Testamento.antigo, '1CH'),
  LivroBiblia('2cr', '2 Crônicas', Testamento.antigo, '2CH'),
  LivroBiblia('ed', 'Esdras', Testamento.antigo, 'EZR'),
  LivroBiblia('ne', 'Neemias', Testamento.antigo, 'NEH'),
  LivroBiblia('et', 'Ester', Testamento.antigo, 'EST'),
  LivroBiblia('jó', 'Jó', Testamento.antigo, 'JOB'),
  LivroBiblia('sl', 'Salmos', Testamento.antigo, 'PSA'),
  LivroBiblia('pv', 'Provérbios', Testamento.antigo, 'PRO'),
  LivroBiblia('ec', 'Eclesiastes', Testamento.antigo, 'ECC'),
  LivroBiblia('ct', 'Cantares', Testamento.antigo, 'SNG'),
  LivroBiblia('is', 'Isaías', Testamento.antigo, 'ISA'),
  LivroBiblia('jr', 'Jeremias', Testamento.antigo, 'JER'),
  LivroBiblia('lm', 'Lamentações', Testamento.antigo, 'LAM'),
  LivroBiblia('ez', 'Ezequiel', Testamento.antigo, 'EZK'),
  LivroBiblia('dn', 'Daniel', Testamento.antigo, 'DAN'),
  LivroBiblia('os', 'Oseias', Testamento.antigo, 'HOS'),
  LivroBiblia('jl', 'Joel', Testamento.antigo, 'JOL'),
  LivroBiblia('am', 'Amós', Testamento.antigo, 'AMO'),
  LivroBiblia('ob', 'Obadias', Testamento.antigo, 'OBA'),
  LivroBiblia('jn', 'Jonas', Testamento.antigo, 'JON'),
  LivroBiblia('mq', 'Miqueias', Testamento.antigo, 'MIC'),
  LivroBiblia('na', 'Naum', Testamento.antigo, 'NAM'),
  LivroBiblia('hc', 'Habacuque', Testamento.antigo, 'HAB'),
  LivroBiblia('sf', 'Sofonias', Testamento.antigo, 'ZEP'),
  LivroBiblia('ag', 'Ageu', Testamento.antigo, 'HAG'),
  LivroBiblia('zc', 'Zacarias', Testamento.antigo, 'ZEC'),
  LivroBiblia('ml', 'Malaquias', Testamento.antigo, 'MAL'),

  // ── Novo Testamento ──────────────────────────────────────────────────────
  LivroBiblia('mt', 'Mateus', Testamento.novo, 'MAT'),
  LivroBiblia('mc', 'Marcos', Testamento.novo, 'MRK'),
  LivroBiblia('lc', 'Lucas', Testamento.novo, 'LUK'),
  LivroBiblia('jo', 'João', Testamento.novo, 'JHN'),
  LivroBiblia('at', 'Atos', Testamento.novo, 'ACT'),
  LivroBiblia('rm', 'Romanos', Testamento.novo, 'ROM'),
  LivroBiblia('1co', '1 Coríntios', Testamento.novo, '1CO'),
  LivroBiblia('2co', '2 Coríntios', Testamento.novo, '2CO'),
  LivroBiblia('gl', 'Gálatas', Testamento.novo, 'GAL'),
  LivroBiblia('ef', 'Efésios', Testamento.novo, 'EPH'),
  LivroBiblia('fp', 'Filipenses', Testamento.novo, 'PHP'),
  LivroBiblia('cl', 'Colossenses', Testamento.novo, 'COL'),
  LivroBiblia('1ts', '1 Tessalonicenses', Testamento.novo, '1TH'),
  LivroBiblia('2ts', '2 Tessalonicenses', Testamento.novo, '2TH'),
  LivroBiblia('1tm', '1 Timóteo', Testamento.novo, '1TI'),
  LivroBiblia('2tm', '2 Timóteo', Testamento.novo, '2TI'),
  LivroBiblia('tt', 'Tito', Testamento.novo, 'TIT'),
  LivroBiblia('fm', 'Filemom', Testamento.novo, 'PHM'),
  LivroBiblia('hb', 'Hebreus', Testamento.novo, 'HEB'),
  LivroBiblia('tg', 'Tiago', Testamento.novo, 'JAS'),
  LivroBiblia('1pe', '1 Pedro', Testamento.novo, '1PE'),
  LivroBiblia('2pe', '2 Pedro', Testamento.novo, '2PE'),
  LivroBiblia('1jo', '1 João', Testamento.novo, '1JN'),
  LivroBiblia('2jo', '2 João', Testamento.novo, '2JN'),
  LivroBiblia('3jo', '3 João', Testamento.novo, '3JN'),
  LivroBiblia('jd', 'Judas', Testamento.novo, 'JUD'),
  LivroBiblia('ap', 'Apocalipse', Testamento.novo, 'REV'),
];

/// O livro pela sigla, ou null se não conhecemos.
LivroBiblia? livroPorSigla(String sigla) {
  for (final l in livrosDaBiblia) {
    if (l.sigla == sigla) return l;
  }
  return null;
}

/// Nome do livro pela sigla; a própria sigla, se for desconhecida — assim uma
/// tradução futura com um livro a mais aparece, em vez de sumir.
String nomeDoLivro(String sigla) {
  for (final l in livrosDaBiblia) {
    if (l.sigla == sigla) return l.nome;
  }
  return sigla;
}
