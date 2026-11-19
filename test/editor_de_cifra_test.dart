import 'package:flutter_test/flutter_test.dart';
import 'package:levitasync/core/utils/mapa_da_musica.dart';

/// Esconder tablatura, e as partes da música.
///
/// A tablatura da introdução ocupa seis linhas para dizer o que o tecladista
/// e a cantora não vão tocar — num celular, meia tela de rolagem antes do
/// primeiro verso. Esconder é opção de quem lê, não decisão nossa.
///
/// A conta mora num lugar só (`ehTablatura`): duas contas diferentes para
/// "isto é tablatura" acabariam discordando, e aí o músico esconderia as
/// tablaturas e sobraria meia tablatura na tela.

const cifraComTab = '''
[Intro]
e|-----3-----|
B|---0---0---|
G|-0-------0-|

G        C        D
Sou grato por seu amor

[Refrão]
G        C
Aleluia
''';

void main() {
  group('reconhecer tablatura', () {
    test('as linhas de tablatura de verdade', () {
      expect(ehTablatura('e|-----3-----|'), isTrue);
      expect(ehTablatura('B|---0---0---|'), isTrue);
      expect(ehTablatura('  G|-0-------0-|'), isTrue);
      expect(ehTablatura('D|--2--'), isTrue);
    });

    test('e o que NÃO é', () {
      // Acorde, letra e rótulo de parte não podem ser confundidos com
      // tablatura: esconder tablatura apagaria a música.
      expect(ehTablatura('G        C        D'), isFalse);
      expect(ehTablatura('Sou grato por seu amor'), isFalse);
      expect(ehTablatura('[Refrão]'), isFalse);
      expect(ehTablatura(''), isFalse);
      expect(ehTablatura('Em casa de meu Pai'), isFalse);
    });
  });

  group('esconder tablatura', () {
    test('tira as linhas de tablatura e mantém o resto', () {
      final r = semTablaturas(cifraComTab);
      expect(r, isNot(contains('e|')));
      expect(r, isNot(contains('B|')));
      expect(r, contains('Sou grato por seu amor'));
      expect(r, contains('[Intro]'));
      expect(r, contains('[Refrão]'));
      expect(r, contains('G        C        D'));
    });

    test('não deixa buraco de linhas vazias onde ela estava', () {
      // Três linhas em branco seguidas, no meio da música, parecem que falta
      // algo — e quem está tocando olha a tela procurando o que sumiu.
      final r = semTablaturas(cifraComTab);
      expect(r.contains('\n\n\n'), isFalse);
    });

    test('começa e termina no texto, não em branco', () {
      expect(semTablaturas(cifraComTab).startsWith('[Intro]'), isTrue);
      expect(semTablaturas(cifraComTab).trimRight(),
          semTablaturas(cifraComTab));
    });

    test('música sem tablatura nenhuma não é mexida', () {
      const simples = 'G        C\nAleluia\n\nD        Em\nAmém';
      expect(semTablaturas(simples), simples);
    });

    test('música que é SÓ tablatura não vira vazio sem aviso', () {
      // Caso de borda real: cifra de solo. O resultado é vazio, e é a tela
      // que precisa decidir o que dizer — mas a função não pode lançar.
      const soTab = 'e|---3---|\nB|---0---|';
      expect(semTablaturas(soTab), '');
    });
  });

  group('as partes da música', () {
    test('são reconhecidas e nomeadas', () {
      final partes = MapaDaMusica.mapear(cifraComTab)
          .partes
          .map((p) => p.nome)
          .toList();
      // "[Intro]" não tem verso embaixo, então não vira parte navegável — é
      // a mesma regra que impede "pular para a introdução" e cair no refrão.
      expect(partes, contains('Refrão'));
    });

    test('acorde entre colchetes no meio da letra NÃO é parte', () {
      // "[G]Eu te louvarei" é jeito de escrever cifra, não rótulo de seção.
      final partes = MapaDaMusica.mapear(
              '[G]Eu te louvarei\n[C]Com todo o meu ser')
          .partes;
      expect(partes, isEmpty);
    });
  });
}
