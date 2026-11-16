import 'package:flutter_test/flutter_test.dart';
import 'package:levitasync/core/utils/mapa_da_musica.dart';

/// O mapeamento de linhas é o que faz a rolagem sincronizada funcionar entre
/// aparelhos diferentes.
///
/// A cifra tem linhas de acorde entre os versos; a versão de quem canta não
/// tem nenhuma. Se o que viajasse fosse "linha 12", o tecladista estaria no
/// refrão e a cantora três versos atrás — e ninguém veria erro na tela, só
/// desalinho no meio do culto.
void main() {
  const cifra = '''
[Intro] D  A  G

   D              A
Sou grato por Seu amor
      G                D
Que me alcançou onde eu estava

[Refrão]
   G            D
Grato, grato sou
   A            D
Por tudo que fez em mim
''';

  group('os dois textos saem da mesma varredura', () {
    final m = MapaDaMusica.mapear(cifra);

    test('a letra não tem linha de acorde', () {
      for (final l in m.linhasDaLetra) {
        expect(l.trim(), isNot(equals('D              A')));
        expect(l.contains('G                D'), isFalse);
      }
      expect(m.linhasDaLetra.join('\n'), contains('Sou grato por Seu amor'));
    });

    test('a cifra tem tudo', () {
      final t = m.linhasDaCifra.join('\n');
      expect(t, contains('D              A'));
      expect(t, contains('Sou grato por Seu amor'));
      expect(t, contains('[Intro] D  A  G'));
    });

    test('as âncoras são só as linhas de letra', () {
      expect(m.ancoras.length, 4);
      expect(m.ancoras.map((a) => a.texto).toList(), [
        'Sou grato por Seu amor',
        'Que me alcançou onde eu estava',
        'Grato, grato sou',
        'Por tudo que fez em mim',
      ]);
    });
  });

  group('a mesma âncora aponta para a mesma letra nos dois modos', () {
    final m = MapaDaMusica.mapear(cifra);

    test('para TODAS as âncoras', () {
      // É esta a promessa da entrega: o condutor na cifra e a cantora na
      // letra, na mesma linha.
      for (final a in m.ancoras) {
        expect(m.linhasDaCifra[a.naCifra].trim(), a.texto,
            reason: 'âncora ${a.indice} na cifra');
        expect(m.linhasDaLetra[a.naLetra].trim(), a.texto,
            reason: 'âncora ${a.indice} na letra');
      }
    });

    test('e os índices nos dois textos são DIFERENTES', () {
      // Se fossem iguais, o teste acima passaria por acidente e não provaria
      // nada — é justamente a diferença que a sincronização tem de atravessar.
      final diferentes =
          m.ancoras.where((a) => a.naCifra != a.naLetra).length;
      expect(diferentes, greaterThan(0));
    });

    test('linhaNoTexto devolve o mesmo verso nos dois modos', () {
      for (var i = 0; i < m.ancoras.length; i++) {
        final naCifra = m.linhasDaCifra[m.linhaNoTexto(i, cifra: true)];
        final naLetra = m.linhasDaLetra[m.linhaNoTexto(i, cifra: false)];
        expect(naCifra.trim(), naLetra.trim());
      }
    });
  });

  group('as partes', () {
    final m = MapaDaMusica.mapear(cifra);

    test('a parte de cada âncora', () {
      expect(m.secaoDe(0), 'Intro');
      expect(m.secaoDe(2), 'Refrão');
    });

    test('"[Intro] D A G" não entra na lista de partes', () {
      // Não tem verso nenhum: pular para ela deixaria a tela num lugar sem
      // texto para acompanhar.
      expect(m.partes.map((p) => p.nome).toList(), ['Intro', 'Refrão']);
      // A "Intro" entra na âncora 0, que é a primeira letra depois dela.
      expect(m.partes.first.ancora, 0);
      expect(m.partes.last.ancora, 2);
    });

    test('próxima parte pula para o começo da próxima', () {
      expect(m.proximaParte(0), 2);
      // Na última parte, não passa do fim.
      expect(m.proximaParte(3), 3);
    });

    test('parte anterior volta para o começo da anterior', () {
      expect(m.parteAnterior(3), 2);
      expect(m.parteAnterior(2), 0);
      expect(m.parteAnterior(0), 0);
    });
  });

  group('música sem cifra nenhuma (só a letra)', () {
    final m = MapaDaMusica.mapear(
        'Eu navegarei no oceano do Espírito\nE lá adorarei ao Deus da criação');

    test('toda linha é âncora, e os dois textos são iguais', () {
      expect(m.ancoras.length, 2);
      expect(m.linhasDaCifra, m.linhasDaLetra);
      expect(m.linhaNoTexto(1, cifra: true), m.linhaNoTexto(1, cifra: false));
    });

    test('sem partes, "próxima parte" anda uma estrofe', () {
      expect(m.partes, isEmpty);
      // Com duas linhas, não passa do fim.
      expect(m.proximaParte(0), 1);
    });
  });

  group('casos que estragariam a sincronização em silêncio', () {
    test('tablatura não vira âncora', () {
      final m = MapaDaMusica.mapear('e|---0---2---\nB|---1---3---\nVerso aqui');
      expect(m.ancoras.length, 1);
      expect(m.ancoras.first.texto, 'Verso aqui');
    });

    test('acorde entre colchetes no meio da letra É letra', () {
      final m = MapaDaMusica.mapear('[G]Eu te louvarei');
      expect(m.ancoras.length, 1);
      expect(m.partes, isEmpty);
    });

    test('"[Refrão] Eu te louvarei" conta como letra, não como rótulo', () {
      final m = MapaDaMusica.mapear('[Refrão] Eu te louvarei');
      expect(m.ancoras.length, 1);
    });

    test('índice fora da lista não derruba a tela', () {
      final m = MapaDaMusica.mapear(cifra);
      expect(m.ancora(-5)!.indice, 0);
      expect(m.ancora(999)!.indice, 3);
      expect(m.linhaNoTexto(999, cifra: true), lessThan(m.linhasDaCifra.length));
    });

    test('texto vazio não explode', () {
      final m = MapaDaMusica.mapear('');
      expect(m.vazio, isTrue);
      expect(m.ancora(0), isNull);
      expect(m.secaoDe(0), '');
      expect(m.proximaParte(0), 0);
      expect(m.linhaNoTexto(0, cifra: true), 0);
    });

    test('linhas vazias ficam nos dois, para o espaçamento não mudar', () {
      final m = MapaDaMusica.mapear('Verso um\n\n\nVerso dois');
      expect(m.linhasDaCifra.where((l) => l.isEmpty).length, 2);
      expect(m.linhasDaLetra.where((l) => l.isEmpty).length, 2);
    });
  });
}
