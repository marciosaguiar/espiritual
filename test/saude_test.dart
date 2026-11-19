import 'package:flutter_test/flutter_test.dart';
import 'package:levitasync/data/models/saude_model.dart';

/// A saúde do sistema: o que acende alarme e o que não acende.
///
/// Isto existe porque os robôs falharam em silêncio por dias. O risco agora
/// é o oposto — um alarme que mente, que a pessoa aprende a ignorar em uma
/// semana. Então o que estes testes guardam é principalmente o que NÃO deve
/// acender: celular sem internet, rotina de 20 horas, carimbo que nunca
/// existiu.

final AGORA = DateTime(2026, 11, 19, 10, 0);

CarimboDeSaude carimbo(DateTime em, {bool ok = true, String detalhe = ''}) =>
    CarimboDeSaude(em: em, ok: ok, detalhe: detalhe);

const workerBom = SaudeDoWorker(
  configurado: true,
  entra: true,
  robo: 'entra e está líder',
);

/// Três rotinas que rodaram há duas horas.
Map<String, CarimboDeSaude> tudoEmDia() => {
      'cultos': carimbo(AGORA.subtract(const Duration(hours: 2))),
      'vespera': carimbo(AGORA.subtract(const Duration(hours: 2))),
      'faxina': carimbo(AGORA.subtract(const Duration(hours: 2))),
    };

SaudeDoSistema avaliar({
  SaudeDoWorker? worker = workerBom,
  Map<String, CarimboDeSaude>? carimbos,
  DateTime? agora,
}) =>
    SaudeDoSistema.avaliar(
      worker: worker,
      carimbos: carimbos ?? tudoEmDia(),
      agora: agora ?? AGORA,
    );

ItemDeSaude item(SaudeDoSistema s, String titulo) =>
    s.itens.firstWhere((i) => i.titulo == titulo);

void main() {
  group('o que NÃO acende alarme', () {
    test('tudo em ordem', () {
      final s = avaliar();
      expect(s.temAlarme, isFalse);
      expect(s.pior, isNull);
      expect(s.itens.every((i) => i.estado == EstadoDeSaude.ok), isTrue);
      // E nenhuma instrução na tela: "o que fazer" com tudo em ordem ensina
      // a pessoa a não ler as instruções.
      expect(s.itens.every((i) => i.oQueFazer == null), isTrue);
    });

    test('celular sem internet não é sistema quebrado', () {
      // O Worker nulo significa "não consegui falar com ele". Acender
      // vermelho aqui faria o líder correr atrás de um defeito que é o wi-fi
      // da igreja — e na terceira vez ele para de olhar a tela.
      final s = avaliar(worker: null);
      expect(s.temAlarme, isFalse);
      expect(item(s, 'Servidor dos avisos').estado,
          EstadoDeSaude.desconhecido);
      // Sem o Worker não há como saber do robô, então a linha dele nem
      // aparece — melhor faltar que chutar.
      expect(s.itens.any((i) => i.titulo == 'Robô dos avisos'), isFalse);
    });

    test('rotina de 20 horas está em dia, não atrasada', () {
      final s = avaliar(carimbos: {
        ...tudoEmDia(),
        'vespera': carimbo(AGORA.subtract(const Duration(hours: 20))),
      });
      expect(item(s, 'Lembrete da véspera').estado, EstadoDeSaude.ok);
      expect(s.temAlarme, isFalse);
    });

    test('30 horas é ALERTA, não alarme', () {
      // Um job diário chega legitimamente perto das 24 h sem ter falhado.
      // Vermelho aqui seria alarme falso todo dia, pouco antes da hora dele.
      final s = avaliar(carimbos: {
        ...tudoEmDia(),
        'vespera': carimbo(AGORA.subtract(const Duration(hours: 30))),
      });
      expect(item(s, 'Lembrete da véspera').estado, EstadoDeSaude.alerta);
      expect(s.temAlarme, isFalse);
    });

    test('carimbo que nunca existiu não é falha', () {
      // No dia em que isto for publicado, nenhuma rotina tem carimbo ainda.
      // Pintar o app de vermelho na estreia seria o pior jeito de apresentar
      // uma tela de diagnóstico.
      final s = avaliar(carimbos: const {});
      expect(s.temAlarme, isFalse);
      for (final qual in ['Criação dos cultos', 'Lembrete da véspera',
        'Faxina do chat']) {
        expect(item(s, qual).estado, EstadoDeSaude.desconhecido);
      }
    });
  });

  group('o que ACENDE alarme', () {
    test('36 horas: uma execução foi perdida', () {
      final s = avaliar(carimbos: {
        ...tudoEmDia(),
        'vespera': carimbo(AGORA.subtract(const Duration(hours: 36))),
      });
      expect(item(s, 'Lembrete da véspera').estado, EstadoDeSaude.ruim);
      expect(s.temAlarme, isTrue);
      expect(s.pior!.titulo, 'Lembrete da véspera');
      expect(s.pior!.oQueFazer, isNotNull);
    });

    test('a última execução FALHOU, mesmo tendo sido agora', () {
      // É o caso que custou os dias de silêncio: a rotina rodava todo dia e
      // batia num 403. Sem o carimbo de falha, ela pareceria "rodou hoje"
      // para sempre.
      final s = avaliar(carimbos: {
        ...tudoEmDia(),
        'cultos': carimbo(AGORA.subtract(const Duration(minutes: 5)),
            ok: false, detalhe: 'o Worker respondeu 403'),
      });
      final i = item(s, 'Criação dos cultos');
      expect(i.estado, EstadoDeSaude.ruim);
      expect(i.detalhe, contains('403'));
      expect(s.temAlarme, isTrue);
    });

    test('segredo faltando na Cloudflare', () {
      final s = avaliar(
        worker: const SaudeDoWorker(
          configurado: false,
          falta: ['ROBO_SENHA'],
          entra: false,
          robo: 'não dá para conferir sem os segredos',
          conserto: 'faltam na Cloudflare: ROBO_SENHA',
        ),
      );
      final i = item(s, 'Servidor dos avisos');
      expect(i.estado, EstadoDeSaude.ruim);
      expect(i.detalhe, contains('ROBO_SENHA'));
      expect(i.oQueFazer, contains('Cloudflare'));
      expect(s.temAlarme, isTrue);
    });

    test('o robô não entra na conta dele', () {
      // Foi o defeito de verdade: FIREBASE_API_KEY digitada errada.
      final s = avaliar(
        worker: const SaudeDoWorker(
          configurado: true,
          entra: false,
          robo: 'O robô não conseguiu entrar na conta dele.',
          conserto: 'ROBO_EMAIL e ROBO_SENHA na Cloudflare',
        ),
      );
      final i = item(s, 'Robô dos avisos');
      expect(i.estado, EstadoDeSaude.ruim);
      expect(i.oQueFazer, contains('ROBO_EMAIL'));
      expect(s.temAlarme, isTrue);
    });

    test('o robô entra e não é líder', () {
      final s = avaliar(
        worker: const SaudeDoWorker(
          configurado: true,
          entra: true,
          robo: 'entra, e o cadastro dele está "levita"',
        ),
      );
      final i = item(s, 'Robô dos avisos');
      expect(i.estado, EstadoDeSaude.ruim);
      expect(i.detalhe, contains('levita'));
      // Sem conserto do Worker, a tela diz onde promover — em Membros, que é
      // onde o líder leigo consegue chegar.
      expect(i.oQueFazer, contains('Membros'));
    });

    test('"está líder" é lido da frase do Worker, e só dela', () {
      // Frase diferente não pode ser lida como "tudo bem": o padrão seguro é
      // reclamar, não calar.
      expect(workerBom.roboLider, isTrue);
      expect(
          const SaudeDoWorker(
            configurado: true,
            entra: true,
            robo: 'entra, mas NÃO TEM cadastro em users',
          ).roboLider,
          isFalse);
    });
  });

  group('quando foi, em português', () {
    test('hoje e ontem', () {
      expect(SaudeDoSistema.quandoFoi(DateTime(2026, 11, 19, 8, 5), AGORA),
          'hoje às 8h05');
      expect(SaudeDoSistema.quandoFoi(DateTime(2026, 11, 18, 17, 37), AGORA),
          'ontem às 17h37');
    });

    test('a virada do dia conta DIA, não 24 horas', () {
      // 23h de ontem para 1h de hoje é "ontem" para quem lê, e menos de 24 h
      // na conta de horas. Quem erra isto escreve "hoje" sobre ontem.
      final meiaNoitePassada = DateTime(2026, 11, 19, 1, 0);
      expect(
          SaudeDoSistema.quandoFoi(
              DateTime(2026, 11, 18, 23, 0), meiaNoitePassada),
          startsWith('ontem'));
    });

    test('mais de dois dias traz a data', () {
      expect(SaudeDoSistema.quandoFoi(DateTime(2026, 11, 16, 17, 37), AGORA),
          'há 3 dias, em 16/11 às 17h37');
    });

    test('a virada do mês não quebra', () {
      expect(
          SaudeDoSistema.quandoFoi(
              DateTime(2026, 10, 31, 9, 0), DateTime(2026, 11, 2, 9, 0)),
          'há 2 dias, em 31/10 às 9h00');
    });
  });
}
