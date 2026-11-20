// O que o aparelho guarda sobre os hinos: os últimos abertos, e a ordem que
// CADA PESSOA escolheu.
//
// TODO o texto é inventado.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:levitasync/core/constants/hinarios.dart';
import 'package:levitasync/data/services/local_storage_service.dart';

Future<void> _zerar([Map<String, Object> inicial = const {}]) async {
  SharedPreferences.setMockInitialValues(inicial);
  await LocalStorageService.init();
}

void main() {
  group('últimos hinos abertos', () {
    // A chave era escrita como '\$hinario|\$numero' — o texto LITERAL, igual
    // para todo hino —, então nada que se gravava voltava: a lista de "Últimos
    // abertos" nunca teve um hino sequer, e nenhum teste olhava.
    test('o que se abre volta, do mais recente para o mais antigo', () async {
      await _zerar();
      await LocalStorageService.salvarHinoAberto('harpa', 15);
      await LocalStorageService.salvarHinoAberto('cantor', 3);
      final r = LocalStorageService.hinosAbertos;
      expect(r.map((e) => '${e.hinario}|${e.numero}'), ['cantor|3', 'harpa|15']);
    });

    test('abrir o mesmo hino de novo o traz para a frente, sem repetir',
        () async {
      await _zerar();
      await LocalStorageService.salvarHinoAberto('harpa', 15);
      await LocalStorageService.salvarHinoAberto('harpa', 65);
      await LocalStorageService.salvarHinoAberto('harpa', 15);
      expect(LocalStorageService.hinosAbertos.map((e) => e.numero), [15, 65]);
    });

    test('guarda só os 8 mais recentes', () async {
      await _zerar();
      for (var n = 1; n <= 12; n++) {
        await LocalStorageService.salvarHinoAberto('harpa', n);
      }
      final r = LocalStorageService.hinosAbertos;
      expect(r.length, 8);
      expect(r.first.numero, 12);
    });

    test('entrada torta é descartada, não derruba', () async {
      await _zerar({
        'hinos_abertos': ['harpa|15', 'lixo', 'harpa|x', '|3', 'cantor|7'],
      });
      expect(LocalStorageService.hinosAbertos.map((e) => e.numero), [15, 7]);
    });
  });

  group('a ordem dos hinos é de cada pessoa', () {
    test('cada pessoa guarda a sua', () async {
      await _zerar();
      await LocalStorageService.salvarOrdemDosHinosDe(
          'ana', OrdemDosHinos.nome.id);
      await LocalStorageService.salvarOrdemDosHinosDe(
          'bruno', OrdemDosHinos.maisTocados.id);
      expect(LocalStorageService.ordemDosHinosDe('ana'), 'nome');
      expect(LocalStorageService.ordemDosHinosDe('bruno'), 'tocados');
    });

    test('quem nunca escolheu herda o que estava gravado antes (sem pessoa)',
        () async {
      // Senão todo mundo voltaria para "pelo número" sem ter mexido em nada.
      await _zerar({'ordem_hinos': 'nome_z_a'});
      expect(LocalStorageService.ordemDosHinosDe('ana'), 'nome_z_a');
    });

    test('a escolha de uma pessoa não vaza para a outra', () async {
      await _zerar();
      await LocalStorageService.salvarOrdemDosHinosDe(
          'ana', OrdemDosHinos.nome.id);
      expect(LocalStorageService.ordemDosHinosDe('bruno'), isNull);
    });

    test('a ordem dos hinários também é por pessoa', () async {
      await _zerar();
      await LocalStorageService.salvarOrdemDosHinariosDe(
          'ana', ['cantor', 'harpa']);
      expect(LocalStorageService.ordemDosHinariosDe('ana'), ['cantor', 'harpa']);
      expect(LocalStorageService.ordemDosHinariosDe('bruno'), isEmpty);
    });

    test('sem pessoa (ainda não logou), usa a chave de sempre', () async {
      await _zerar();
      await LocalStorageService.salvarOrdemDosHinosDe(null, 'nome');
      expect(LocalStorageService.ordemDosHinos, 'nome');
      expect(LocalStorageService.ordemDosHinosDe(null), 'nome');
    });

    test('a Z–A tem id próprio e se lê de volta', () {
      expect(ordemPorId('nome_z_a'), OrdemDosHinos.nomeDescendente);
      expect(ordemPorId('nome'), OrdemDosHinos.nome);
      expect(ordemPorId('lixo'), OrdemDosHinos.numero);
    });
  });
}
