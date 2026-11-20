// As letras dos hinários no aparelho: o que a busca por trecho lê.
//
// Custam uma leitura por hino (640 na Harpa) para trazer, e por isso o
// aparelho guarda — e precisa saber quando o que guardou ficou velho.
//
// TODO o texto é inventado.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:levitasync/core/constants/hinarios.dart';
import 'package:levitasync/core/utils/importar_hinario.dart';
import 'package:levitasync/data/models/hino_da_biblioteca.dart';
import 'package:levitasync/data/services/local_storage_service.dart';
import 'package:levitasync/presentation/providers/biblioteca_provider.dart';

class _Banco {
  int leituras = 0;
  DateTime importadoEm = DateTime.utc(2026, 11, 1);
  Map<int, String> letras = {1: 'primeira letra', 2: 'segunda letra'};

  BibliotecaProvider provider() => BibliotecaProvider(
        lerIndice: (id) async => (
          indice: IndiceDoHinario(
            hinario: id,
            titulos: {for (final n in letras.keys) n: 'Título $n'},
            atualizadoEm: importadoEm,
          ),
          error: null
        ),
        lerLetras: (id) async {
          leituras++;
          return (letras: Map.of(letras), error: null);
        },
        gravarHinos: ({
          required hinario,
          required hinos,
          required porQuemId,
          aoAvancar,
        }) async =>
            (gravados: hinos.length, error: null),
      );
}

Future<void> _zerar() async {
  SharedPreferences.setMockInitialValues({});
  await LocalStorageService.init();
}

void main() {
  test('trazer guarda no aparelho, e outro provider as lê sem ir ao banco',
      () async {
    await _zerar();
    final b = _Banco();
    final um = b.provider();
    expect(um.letrasProntas('harpa'), isFalse);

    expect(await um.baixarLetras(harpaCrista), isNull);
    expect(um.letrasProntas('harpa'), isTrue);
    expect(um.letrasDe('harpa')[2], 'segunda letra');
    expect(b.leituras, 1);

    // Outra abertura do app: provider novo, mesma memória do aparelho.
    final dois = b.provider();
    await dois.carregarIndice('harpa');
    expect(dois.letrasDe('harpa')[1], 'primeira letra');
    expect(b.leituras, 1, reason: 'não baixou de novo');
  });

  test('o líder importou de novo: o que o aparelho guardou ficou VELHO',
      () async {
    await _zerar();
    final b = _Banco();
    final um = b.provider();
    await um.baixarLetras(harpaCrista);

    b.importadoEm = DateTime.utc(2026, 11, 15); // corrigiu um texto
    final dois = b.provider();
    await dois.carregarIndice('harpa');
    expect(dois.letrasProntas('harpa'), isFalse,
        reason: 'letra corrigida pela metade é pior que oferecer baixar');
  });

  test('importar neste aparelho esquece as letras guardadas', () async {
    await _zerar();
    final b = _Banco();
    final p = b.provider();
    await p.baixarLetras(harpaCrista);
    expect(p.letrasProntas('harpa'), isTrue);

    await p.importar(
      hinario: harpaCrista,
      hinos: const [],
      porQuemId: 'u1',
    );
    // sem hinos gravados nada é esquecido; com um, sim.
    b.letras = {1: 'nova'};
    await p.importar(
      hinario: harpaCrista,
      hinos: const [HinoLido(numero: 1, titulo: 'Um', letra: 'letra nova aqui')],
      porQuemId: 'u1',
    );
    expect(LocalStorageService.letrasDoHinario('harpa'), isNull);
  });

  test('duas chamadas ao mesmo tempo não duplicam a conta', () async {
    await _zerar();
    final b = _Banco();
    final p = b.provider();
    await Future.wait([
      p.baixarLetras(harpaCrista),
      p.baixarLetras(harpaCrista),
    ]);
    expect(b.leituras, 1);
  });

  test('guardado estragado conta como "nunca baixou", e não derruba', () async {
    SharedPreferences.setMockInitialValues({'letras_hinario_harpa': '{lixo'});
    await LocalStorageService.init();
    expect(LocalStorageService.letrasDoHinario('harpa'), isNull);
    expect(_Banco().provider().letrasProntas('harpa'), isFalse);
  });

  test('o hinário NÃO guarda as letras do outro', () async {
    await _zerar();
    final b = _Banco();
    final p = b.provider();
    await p.baixarLetras(harpaCrista);
    expect(p.letrasProntas('cantor'), isFalse);
  });
}
