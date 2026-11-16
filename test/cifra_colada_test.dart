import 'package:flutter_test/flutter_test.dart';
import 'package:levitasync/core/utils/cifra_colada.dart';

/// Colado do Cifra Club como chega no celular (a música do print do Márcio).
const coladoDoCifraClub = '''
"Sou Grato Por Seu Am…" no Apple Music
Tom: D

[Intro] Bm  G6  D

[Primeira Parte]

Bm
   Um caminho
G6            D
   Ele abriu no mar
Bm
   Eu dou graças
G6       D
   Aleluia

[Refrão]

      D
Quem sou eu
              D7M
Pra me amar tanto assim?
A     G
   Sou grato por Seu amor
''';

void main() {
  _cabecalhoGrudado();
  group('CifraColada.analisar', () {
    final r = CifraColada.analisar(coladoDoCifraClub);

    test('preserva as quebras de linha e os espaços da cifra', () {
      expect(r.cifra.split('\n'), contains('G6            D'));
      expect(r.cifra.split('\n'), contains('   Ele abriu no mar'));
      expect(r.cifra, contains('Bm\n   Um caminho'));
    });

    test('tira cabeçalho de site e lê o tom', () {
      expect(r.cifra, isNot(contains('Apple Music')));
      expect(r.cifra, isNot(contains('Tom:')));
      expect(r.tom, 'D');
    });

    test('conta as linhas de acordes (inclusive a intro)', () {
      expect(r.temAcordes, isTrue);
      expect(r.linhasDeAcordes, 8); // 4 na 1ª parte + 3 no refrão + intro
    });

    test('letra pura: sem acordes, com rótulos de parte e sem buracos', () {
      expect(r.letra, '''
[Intro]

[Primeira Parte]

Um caminho
Ele abriu no mar
Eu dou graças
Aleluia

[Refrão]

Quem sou eu
Pra me amar tanto assim?
Sou grato por Seu amor'''.trim());
    });

    test('"A", "E" e "Em" no meio da frase não viram acorde', () {
      final s = CifraColada.analisar('E a glória é Tua\nEm Ti eu confio');
      expect(s.linhasDeAcordes, 0);
      expect(s.letra, 'E a glória é Tua\nEm Ti eu confio');
    });

    test('acordes entre colchetes saem da letra; rótulo não-acorde fica', () {
      final s = CifraColada.analisar('[G]Eu te lou[D]varei\n[Ponte]');
      expect(s.letra, 'Eu te louvarei\n[Ponte]');
      expect(s.linhasDeAcordes, 1);
    });

    test('tablatura fica na cifra e sai da letra', () {
      final s = CifraColada.analisar('E|---0---|\nB|---1---|\nSanto, Santo');
      expect(s.cifra, contains('E|---0---|'));
      expect(s.letra, 'Santo, Santo');
    });

    test('Windows (\\r\\n), espaço duro e tab viram texto comum', () {
      final s = CifraColada.analisar('G  D\r\nLetra\tboa\r\n');
      expect(s.cifra, 'G  D\nLetra    boa');
    });

    test('letra sem acorde passa intacta', () {
      final s = CifraColada.analisar('Santo, Santo\nIgual não há');
      expect(s.temAcordes, isFalse);
      expect(s.letra, 'Santo, Santo\nIgual não há');
      expect(s.tom, isNull);
    });
  });

  group('CifraColada.pareceCifra / letraDe', () {
    test('reconhece cifra com 2+ linhas de acordes', () {
      expect(CifraColada.pareceCifra(coladoDoCifraClub), isTrue);
      expect(CifraColada.pareceCifra('Santo, Santo\nIgual não há'), isFalse);
      expect(CifraColada.pareceCifra(''), isFalse);
    });

    test('letraDe devolve a letra pura só quando é cifra', () {
      expect(CifraColada.letraDe(coladoDoCifraClub), startsWith('[Intro]'));
      expect(CifraColada.letraDe('Só letra'), 'Só letra');
    });
  });

  group('busca no Cifra Club', () {
    test('abre a busca do site com música e artista, sem raspar nada', () {
      final u = CifraColada.buscaNoCifraClub('Sou Grato Pelo Seu Amor', 'Morada');
      expect(u.scheme, 'https');
      expect(u.host, 'www.cifraclub.com.br');
      expect(u.queryParameters['q'], 'Sou Grato Pelo Seu Amor Morada');
    });
    test('sem artista, só a música', () {
      expect(CifraColada.buscaNoCifraClub(' Santo ').queryParameters['q'], 'Santo');
    });

    test('tom na mesma linha do cabeçalho do site', () {
      // Como o Cifra Club entrega de verdade: nome do serviço e tom juntos.
      final r = CifraColada.analisar(
        '"Sou Grato Por Seu Amor" no Apple Music Tom: D\n'
        'Bm   G6\n'
        'Um caminho\n',
      );
      expect(r.tom, 'D');
      expect(r.cifra, isNot(contains('Apple Music')));
      expect(r.letra, 'Um caminho');
    });

    test('cabeçalho sem tom continua sem tom', () {
      final r = CifraColada.analisar('Cifra Club\nBm  G6\nUm caminho\n');
      expect(r.tom, isNull);
    });

  });
}

/// O cabeçalho do Cifra Club colado SEM as quebras de linha que a página
/// mostrava. Os dois casos abaixo são texto real, do jeito que chegou:
/// "Sou Grato Por Seu AmorGet de: Joshua Coleman" e
/// "Tom: DAfinação: E A D G B E".
///
/// O que estava em jogo não era estética: grudado, o "Tom:" não era
/// reconhecido, a música ficava com o tom antigo (G) e a cifra em D — e o
/// levita toca no tom errado no domingo.
void _cabecalhoGrudado() {
  group('cabeçalho grudado do Cifra Club', () {
    const real = '''
Sou Grato Por Seu AmorGet de: Joshua Coleman
Tom: DAfinação: E A D G B E

[Intro] D  A  G

   D              A
Sou grato por Seu amor
      G                D
Que me alcançou onde eu estava
''';

    test('o tom sai do "Tom:" grudado no "Afinação:"', () {
      expect(CifraColada.analisar(real).tom, 'D');
    });

    test('título e artista são reconhecidos', () {
      final r = CifraColada.analisar(real);
      expect(r.titulo, 'Sou Grato Por Seu Amor');
      expect(r.artista, 'Joshua Coleman');
    });

    test('e saem do corpo: a cifra começa na música', () {
      final r = CifraColada.analisar(real);
      expect(r.cifra.split('\n').first.trim(), '[Intro] D  A  G');
      expect(r.cifra, isNot(contains('Joshua')));
      expect(r.cifra, isNot(contains('Afinação')));
      expect(r.cifra, isNot(contains('Tom:')));
    });

    test('a letra também fica limpa', () {
      final r = CifraColada.analisar(real);
      expect(r.letra, isNot(contains('Joshua')));
      expect(r.letra, isNot(contains('Afinação')));
      expect(r.letra, contains('Sou grato por Seu amor'));
    });

    test('"Afinação: E A D G B E" NÃO conta como linha de acordes', () {
      // É a pior de todas para deixar passar: a linha é feita de nomes de
      // acorde, então entrava na cifra como se fosse acorde de verdade.
      final r = CifraColada.analisar(real);
      expect(r.linhasDeAcordes, 3);
    });

    test('sabendo o nome da música, o título volta inteiro', () {
      // O "Get" do botão do site fica grudado no fim do título; comparar por
      // prefixo é o que o reconhece como o mesmo título.
      final r = CifraColada.analisar(real,
          nomeConhecido: 'Sou Grato Por Seu Amor');
      expect(r.titulo, 'Sou Grato Por Seu Amor');
      expect(r.cifra, isNot(contains('Get')));
    });

    test('o nome conhecido pode vir com acento e caixa diferentes', () {
      const colado = 'Grandes Coisasde: Fernandinho\nTom: G\n\nG  D\nAleluia';
      final r = CifraColada.analisar(colado, nomeConhecido: 'GRANDES COISAS');
      expect(r.tom, 'G');
      expect(r.artista, 'Fernandinho');
      expect(r.cifra, isNot(contains('Fernandinho')));
    });

    test('cabeçalho com todos os rótulos do site sai inteiro', () {
      const colado = '''
Bondade de Deus
de: Isaias Saad
Tom: G
Afinação: E A D G B E
Capotraste: 2ª casa
Instrumento: Violão
Dificuldade: Fácil

[Intro] G  D

G
Eu te agradeço
''';
      final r = CifraColada.analisar(colado);
      expect(r.tom, 'G');
      expect(r.artista, 'Isaias Saad');
      expect(r.cifra.split('\n').first.trim(), '[Intro] G  D');
      for (final rotulo in ['Afinação', 'Capotraste', 'Instrumento',
        'Dificuldade', 'Isaias']) {
        expect(r.cifra, isNot(contains(rotulo)), reason: rotulo);
      }
    });

    test('sem artista no cabeçalho, a primeira linha NÃO é descartada', () {
      // A trava contra comer um verso: sem o sinal de cabeçalho de site,
      // a linha de letra fica. Perder um verso é pior que deixar um título.
      const colado = 'Eu navegarei no oceano do Espírito\n\nG  D\nE lá entrarei';
      final r = CifraColada.analisar(colado);
      expect(r.titulo, isNull);
      expect(r.letra, contains('Eu navegarei no oceano'));
    });

    test('"de:" no meio da letra, longe do cabeçalho, não vira artista', () {
      final linhas = List.filled(10, 'Linha qualquer da música').join('\n');
      final r = CifraColada.analisar('$linhas\nFala de: amor e perdão');
      expect(r.artista, isNull);
      expect(r.letra, contains('Fala de: amor e perdão'));
    });

    test('linha de acordes com ":" não é confundida com artista', () {
      const colado = 'Tom: C\n\nC  G  Am  F\nQuem é como Tu';
      final r = CifraColada.analisar(colado);
      expect(r.artista, isNull);
      expect(r.cifra, contains('C  G  Am  F'));
    });
  });
}
