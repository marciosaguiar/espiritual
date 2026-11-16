import 'package:flutter_test/flutter_test.dart';
import 'package:levitasync/data/models/ao_vivo_model.dart';

/// O estado ao vivo e o limite de escritas.
///
/// Duas coisas que erram em silêncio: o comando ficar preso num condutor que
/// já saiu do culto, e a rolagem do condutor virar centenas de escritas por
/// minuto no Firestore.
void main() {
  final agora = DateTime(2026, 11, 16, 19, 30);

  EstadoAoVivo estado({
    String condutor = 'u-lider',
    int musica = 0,
    int ancora = 3,
    Duration idade = Duration.zero,
  }) =>
      EstadoAoVivo(
        condutorId: condutor,
        condutorNome: 'Marcio',
        musica: musica,
        ancora: ancora,
        secao: 'Refrão',
        texto: 'Grato, grato sou',
        atualizadoEm: agora.subtract(idade),
      );

  group('quem pode assumir o comando', () {
    test('o condutor ativo manda, e ninguém tira dele', () {
      final e = estado(idade: const Duration(seconds: 3));
      expect(e.vivo(agora), isTrue);
      expect(e.souOCondutor('u-lider'), isTrue);
      expect(e.podeAssumir('u-ana', agora), isFalse);
    });

    test('sem condutor, qualquer um assume', () {
      final e = estado(condutor: '');
      expect(e.temCondutor, isFalse);
      expect(e.podeAssumir('u-ana', agora), isTrue);
    });

    test('condutor que calou há mais de 45 s libera o comando', () {
      // Celular travado, bateria no fim, app fechado no meio do culto. Sem
      // isto o culto ficaria preso esperando alguém que já não está ali.
      final e = estado(idade: const Duration(seconds: 60));
      expect(e.vivo(agora), isFalse);
      expect(e.podeAssumir('u-ana', agora), isTrue);
    });

    test('na fronteira dos 45 s', () {
      expect(estado(idade: const Duration(seconds: 44)).vivo(agora), isTrue);
      expect(estado(idade: const Duration(seconds: 46)).vivo(agora), isFalse);
    });

    test('o próprio condutor sempre pode reassumir', () {
      final e = estado(idade: const Duration(seconds: 2));
      expect(e.podeAssumir('u-lider', agora), isTrue);
    });
  });

  group('o que conta como posição nova', () {
    test('a hora sozinha NÃO conta', () {
      // Se contasse, a tela parada geraria escrita a cada batida do relógio.
      final a = estado();
      final b = a.copyWith(atualizadoEm: agora.add(const Duration(seconds: 9)));
      expect(a.mesmaPosicaoQue(b), isTrue);
    });

    test('linha, música e condutor contam', () {
      final a = estado();
      expect(a.mesmaPosicaoQue(a.copyWith(ancora: 4)), isFalse);
      expect(a.mesmaPosicaoQue(a.copyWith(musica: 1)), isFalse);
      expect(a.mesmaPosicaoQue(a.copyWith(condutorId: 'u-ana')), isFalse);
    });
  });

  group('ida e volta no banco', () {
    test('os campos sobrevivem', () {
      final lido = EstadoAoVivo.fromFirestore({
        'condutorId': 'u-ana',
        'condutorNome': 'Ana',
        'musica': 2,
        'ancora': 11,
        'secao': 'Ponte',
        'texto': 'E lá adorarei',
      });
      expect(lido.condutorId, 'u-ana');
      expect(lido.musica, 2);
      expect(lido.ancora, 11);
      expect(lido.secao, 'Ponte');
    });

    test('documento vazio ou torto não derruba a tela', () {
      final lido = EstadoAoVivo.fromFirestore({});
      expect(lido.condutorId, '');
      expect(lido.musica, 0);
      expect(lido.ancora, 0);
      expect(lido.temCondutor, isFalse);
    });

    test('sem a hora do servidor, o estado nasce "agora" e não velho', () {
      // `serverTimestamp` chega NULO na primeira notificação local, antes de
      // o servidor responder. Tratar como velho faria o comando ficar livre
      // no primeiro instante, e dois aparelhos assumiriam ao mesmo tempo.
      final lido = EstadoAoVivo.fromFirestore({'condutorId': 'u-ana'});
      expect(lido.vivo(DateTime.now()), isTrue);
    });

    test('a hora gravada é a do SERVIDOR, não a do aparelho', () {
      // Com o relógio do celular, um aparelho adiantado deixaria o estado
      // "vivo" para sempre e ninguém mais assumiria.
      final mapa = estado().toFirestore();
      expect(mapa['atualizadoEm'].toString(), contains('FieldValue'));
      expect(mapa['ancora'], 3);
    });
  });

  group('o limite de escritas', () {
    test('a primeira sai na hora', () {
      final l = LimiteDeEscrita();
      expect(l.podeAgora(agora), isTrue);
      expect(l.espera(agora), Duration.zero);
    });

    test('duas por segundo, no máximo', () {
      final l = LimiteDeEscrita();
      l.registrou(agora);
      expect(l.podeAgora(agora.add(const Duration(milliseconds: 100))), isFalse);
      expect(l.espera(agora.add(const Duration(milliseconds: 100))),
          const Duration(milliseconds: 400));
      expect(l.podeAgora(agora.add(const Duration(milliseconds: 500))), isTrue);
      expect(l.podeAgora(agora.add(const Duration(seconds: 2))), isTrue);
    });

    test('uma rajada de rolagem vira UMA espera, não uma fila', () {
      // O condutor rolando gera dezenas de mudanças por segundo; o que
      // importa é que a espera não cresça a cada uma.
      final l = LimiteDeEscrita();
      l.registrou(agora);
      for (var ms = 10; ms <= 400; ms += 10) {
        final e = l.espera(agora.add(Duration(milliseconds: ms)));
        expect(e.inMilliseconds, lessThanOrEqualTo(500 - ms + 10));
        expect(e.isNegative, isFalse);
      }
    });

    test('relógio que anda para trás não vira espera gigante', () {
      // Fuso, sincronização de hora: sem isto o condutor pararia de
      // atualizar e ninguém entenderia por quê.
      final l = LimiteDeEscrita();
      l.registrou(agora);
      expect(l.espera(agora.subtract(const Duration(hours: 1))),
          Duration.zero);
    });

    test('intervalo próprio é respeitado', () {
      final l = LimiteDeEscrita(intervalo: const Duration(seconds: 2));
      l.registrou(agora);
      expect(l.podeAgora(agora.add(const Duration(seconds: 1))), isFalse);
      expect(l.podeAgora(agora.add(const Duration(seconds: 2))), isTrue);
    });

    test('esquecer libera na hora — é o soltar o comando', () {
      final l = LimiteDeEscrita();
      l.registrou(agora);
      l.esquecer();
      expect(l.podeAgora(agora), isTrue);
    });

    test('a cota que aperta é a de LEITURAS, não a de escritas', () {
      // A conta que eu errei na primeira vez. Cada mudança de posição é uma
      // leitura cobrada para CADA aparelho que escuta.
      //
      // No teto de 2 escritas por segundo, uma hora de culto dá 7.200
      // mudanças — dentro das 20.000 escritas por dia do Spark. Mas com 12
      // aparelhos escutando são 86.400 LEITURAS, e a cota é 50.000 por dia:
      // um culto só estouraria a conta.
      const teto = 2 * 60 * 60;
      expect(teto, 7200);
      expect(teto, lessThan(20000), reason: 'escritas: cabe');
      expect(teto * 12, greaterThan(50000), reason: 'leituras: NÃO cabe');

      // Por isso a rolagem do condutor só publica quando PARA, e posição
      // igual não vira escrita. O que sobra é mudança de linha de verdade:
      // ~5 músicas de 40 linhas, mais os ajustes, dá algumas centenas.
      const real = 5 * 40 + 100;
      expect(real * 12, lessThan(50000), reason: 'com 12 aparelhos, cabe');
    });
  });
}
