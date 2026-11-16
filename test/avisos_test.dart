import 'package:flutter_test/flutter_test.dart';
import 'package:levitasync/core/constants/avisos_config.dart';
import 'package:levitasync/data/services/avisos_service.dart';

/// "Silenciar até amanhã" é uma conta de calendário, e conta de calendário
/// quebra na virada do dia e na virada do mês. Por isso ela é pura e recebe
/// `agora`: aqui o teste fica exatamente nessas viradas.
void main() {
  group('silenciar até amanhã', () {
    test('à noite, silencia até as 7h da manhã seguinte', () {
      final r = AvisosService.silenciarAte(DateTime(2026, 11, 16, 22, 30));
      expect(r, DateTime(2026, 11, 17, 7));
    });

    test('às 23h50 NÃO silencia por dez minutos', () {
      // O caso que faria a pessoa achar que o botão não funciona: o silêncio
      // acabaria antes de ela deitar. É o motivo de não ser meia-noite.
      final agora = DateTime(2026, 11, 16, 23, 50);
      final r = AvisosService.silenciarAte(agora);
      expect(r.difference(agora).inMinutes, greaterThan(60));
      expect(r, DateTime(2026, 11, 17, 7));
    });

    test('de madrugada, vale o 7h de hoje', () {
      // Quem silencia às 2h quer dormir, não ficar mudo o dia inteiro.
      final r = AvisosService.silenciarAte(DateTime(2026, 11, 16, 2));
      expect(r, DateTime(2026, 11, 16, 7));
    });

    test('às 6h30 pula para amanhã, porque 7h está perto demais', () {
      final r = AvisosService.silenciarAte(DateTime(2026, 11, 16, 6, 30));
      expect(r, DateTime(2026, 11, 17, 7));
    });

    test('às 5h30 ainda vale o 7h de hoje', () {
      final r = AvisosService.silenciarAte(DateTime(2026, 11, 16, 5, 30));
      expect(r, DateTime(2026, 11, 16, 7));
    });

    test('na virada do mês não cai no dia 32', () {
      final r = AvisosService.silenciarAte(DateTime(2026, 11, 30, 23));
      expect(r, DateTime(2026, 12, 1, 7));
    });

    test('na virada do ano não cai no mês 13', () {
      final r = AvisosService.silenciarAte(DateTime(2026, 12, 31, 23));
      expect(r, DateTime(2027, 1, 1, 7));
    });

    test('nunca devolve uma hora que já passou', () {
      // Varre o dia de meia em meia hora: o silêncio tem de ficar sempre no
      // futuro, e sempre a mais de uma hora de distância.
      for (var minuto = 0; minuto < 24 * 60; minuto += 30) {
        final agora = DateTime(2026, 11, 16).add(Duration(minutes: minuto));
        final r = AvisosService.silenciarAte(agora);
        expect(r.isAfter(agora), isTrue, reason: 'em $agora');
        expect(r.difference(agora).inMinutes, greaterThanOrEqualTo(60),
            reason: 'em $agora');
        expect(r.hour, 7, reason: 'em $agora');
      }
    });
  });

  group('configuração dos avisos', () {
    const chaveDeVerdade =
        'BK8kod6yy9DIw1N0tJPdeg7-WRYVmQwUVUG9YOhcAPt9JANI6b8Z2iTzrfEUWx5i'
        'KSXWodTzIlu-LOh8PF6szBk';
    const workerDeVerdade = 'https://levitasync-avisos.exemplo.workers.dev';

    test('valores de exemplo contam como NÃO configurado', () {
      // É a trava que faz a tela EXPLICAR o que falta em vez de dar erro de
      // rede quando ninguém publicou o Worker ainda.
      expect(
          AvisosConfig.pareceConfigurado(
              'https://COLE-AQUI.workers.dev', 'COLE-AQUI-A-CHAVE-PUBLICA'),
          isFalse);
    });

    test('endereço e chave de verdade contam como configurado', () {
      expect(AvisosConfig.pareceConfigurado(workerDeVerdade, chaveDeVerdade),
          isTrue);
    });

    test('chave colada pela metade é recusada', () {
      // O erro mais provável: ela tem 87 caracteres e não tem onde quebrar.
      expect(
          AvisosConfig.pareceConfigurado(
              workerDeVerdade, chaveDeVerdade.substring(0, 60)),
          isFalse);
    });

    test('endereço sem https é recusado', () {
      expect(
          AvisosConfig.pareceConfigurado(
              'levitasync-avisos.exemplo.workers.dev', chaveDeVerdade),
          isFalse);
    });

    test('os dois valores do app andam juntos', () {
      // O que realmente importa checar nas constantes de hoje: ou as duas
      // estão preenchidas, ou as duas são de exemplo. Meio preenchido é o
      // estado em que o app tenta falar com um Worker que não existe.
      final temWorker = !AvisosConfig.worker.contains('COLE-AQUI');
      final temChave = !AvisosConfig.chavePublica.contains('COLE-AQUI');
      expect(temWorker, temChave,
          reason: 'preencha os dois em avisos_config.dart, ou nenhum');
    });
  });
}
