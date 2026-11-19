import 'package:flutter_test/flutter_test.dart';
import 'package:levitasync/core/utils/compartilhado.dart';
import 'package:levitasync/core/utils/texto.dart';

/// Cadastrar música com menos esforço.
///
/// Duas contas puras aqui, e as duas erram em silêncio: a que decide se uma
/// música já existe com outro nome, e a que decide o que fazer com o que o
/// Android compartilhou. Nenhuma das duas dá erro quando acerta pelo motivo
/// errado — a primeira deixaria criar a música duplicada, a segunda abriria
/// um cadastro vazio depois de a pessoa tocar em "compartilhar".

void main() {
  group('nome parecido', () {
    final repertorio = [
      'Grande é o Senhor',
      'HC 15 · Sou Grato',
      'Digno És',
      'Tu és Santo',
    ];

    test('acento e maiúscula não fazem música nova', () {
      // Quem digita no celular com pressa não põe acento, e a música
      // apareceria duas vezes na lista sem ninguém entender por quê.
      expect(nomesParecidos('grande e o senhor', repertorio),
          ['Grande é o Senhor']);
      expect(nomesParecidos('GRANDE É O SENHOR!', repertorio),
          ['Grande é o Senhor']);
    });

    test('pontuação diferente é o mesmo nome', () {
      expect(nomesParecidos('Digno es...', repertorio), ['Digno És']);
    });

    test('o hino cadastrado com a sigla é achado pelo nome', () {
      // "HC 15 · Sou Grato" e "Sou Grato" são a MESMA música. Sem isto, o
      // líder criaria a segunda e a cifra ficaria na primeira.
      expect(nomesParecidos('Sou Grato', repertorio), ['HC 15 · Sou Grato']);
    });

    test('música diferente não vira aviso falso', () {
      // Aviso que aparece quando não devia é o jeito de a pessoa aprender a
      // tocar em "cadastrar assim mesmo" sem ler.
      expect(nomesParecidos('Oceanos', repertorio), isEmpty);
      expect(nomesParecidos('Nada além do sangue', repertorio), isEmpty);
    });

    test('palavra curta não casa com meio repertório', () {
      // "Ele" está dentro de vários títulos; sem o piso de letras, o aviso
      // apareceria em quase todo cadastro.
      expect(nomesParecidos('Ele', repertorio), isEmpty);
      expect(nomesParecidos('é', repertorio), isEmpty);
      expect(nomesParecidos('', repertorio), isEmpty);
    });

    test('nome comparável tira o que não é letra nem número', () {
      expect(nomeComparavel('Grande É o Senhor!'), 'grande e o senhor');
      expect(nomeComparavel('HC 15 · Sou Grato'), 'hc 15 sou grato');
      expect(nomeComparavel('  Tu   és   Santo  '), 'tu es santo');
      expect(nomeComparavel('!!!'), '');
    });
  });

  group('o que o Android compartilhou', () {
    test('só o endereço vira LINK, nunca cifra inventada', () {
      // É o caso do botão "compartilhar" do site: chega o endereço, e nada
      // mais. O app não baixa a página — nem por decisão do dono, nem porque
      // copiar a cifra de lá é o que a licença não permite.
      final r = comoUsarCompartilhado(
        titulo: 'Sou Grato - Joshua Coleman | Cifra Club',
        texto: 'https://www.cifraclub.com.br/joshua-coleman/sou-grato/',
      );
      expect(r.cifra, isNull);
      expect(r.link, 'https://www.cifraclub.com.br/joshua-coleman/sou-grato/');
      expect(r.titulo, 'Sou Grato');
      expect(r.temAlgo, isTrue);
    });

    test('o texto da cifra vira CIFRA', () {
      final cifra = '''
Tom: G
G        C        D
Sou grato por seu amor
G        C        D
E pelo que fez por mim
G        C        D
Minha vida entrego a ti
''';
      final r = comoUsarCompartilhado(titulo: 'Sou Grato', texto: cifra);
      expect(r.cifra, isNotNull);
      expect(r.cifra, contains('Sou grato'));
      expect(r.titulo, 'Sou Grato');
    });

    test('letra sem acordes também serve', () {
      // Quem compartilha de um site de letras manda texto sem cifra, e isso
      // ainda é melhor que um cadastro vazio.
      final r = comoUsarCompartilhado(
        texto: 'Sou grato por seu amor, e pelo que fez por mim, minha vida '
            'eu entrego a ti, para sempre te louvar.',
      );
      expect(r.cifra, isNotNull);
    });

    test('texto curto não vira cifra', () {
      final r = comoUsarCompartilhado(texto: 'olha isso');
      expect(r.cifra, isNull);
      expect(r.temAlgo, isFalse);
    });

    test('o endereço no campo próprio e o texto junto: os dois valem', () {
      final r = comoUsarCompartilhado(
        titulo: 'Sou Grato',
        texto: 'G C D\nSou grato por seu amor\nG C D\nE pelo que fez',
        endereco: 'https://www.cifraclub.com.br/x/',
      );
      expect(r.cifra, isNotNull);
      expect(r.link, 'https://www.cifraclub.com.br/x/');
    });

    test('nada compartilhado não abre cadastro nenhum', () {
      expect(comoUsarCompartilhado().temAlgo, isFalse);
      expect(comoUsarCompartilhado(texto: '   ').temAlgo, isFalse);
    });

    test('o nome do site sai do título', () {
      // Sem isto, o repertório encheria de "Sou Grato | Cifra Club".
      expect(tituloLimpo('Sou Grato | Cifra Club'), 'Sou Grato');
      expect(tituloLimpo('Sou Grato - Joshua Coleman'), 'Sou Grato');
      expect(tituloLimpo('Sou Grato - Joshua Coleman | Cifra Club'),
          'Sou Grato');
      expect(tituloLimpo('  Oceanos  '), 'Oceanos');
      expect(tituloLimpo(''), '');
    });

    test('título com hífen sem espaços fica inteiro', () {
      // "Deus-Conosco" é nome, não "nome - artista". O corte é só no " - ".
      expect(tituloLimpo('Deus-Conosco'), 'Deus-Conosco');
    });
  });
}
