// O provider da biblioteca, contando chamadas ao banco.
//
// Leitura é a cota que aperta neste projeto: 50 mil por dia no plano grátis.
// Os comentários do provider prometem coisas sobre custo — "número fora do
// índice custa zero leituras de letra", "o índice é lido uma vez" —, e promessa
// de custo que ninguém conta é palpite. Aqui as funções do banco são trocadas
// por contadores.
//
// TODO o texto é inventado.

import 'package:flutter_test/flutter_test.dart';
import 'package:levitasync/core/platform/armazem.dart';
import 'package:levitasync/core/constants/hinarios.dart';
import 'package:levitasync/core/utils/importar_hinario.dart';
import 'package:levitasync/data/models/hino_da_biblioteca.dart';
import 'package:levitasync/data/models/song_model.dart';
import 'package:levitasync/presentation/providers/biblioteca_provider.dart';

/// Um banco de mentira que conta quantas vezes foi perguntado.
class _Banco {
  int leiturasDeIndice = 0;
  int leiturasDeHino = 0;
  int importacoes = 0;
  String? erroDoIndice;
  final List<SongModel> gravadas = [];
  String? erroAoGravarMusica;

  Map<int, String> titulos = {15: 'Título 15', 16: 'Título 16', 150: 'Título 150'};

  Future<({IndiceDoHinario? indice, String? error})> lerIndice(String id) async {
    leiturasDeIndice++;
    if (erroDoIndice != null) return (indice: null, error: erroDoIndice);
    return (
      indice: IndiceDoHinario(hinario: id, titulos: Map.of(titulos)),
      error: null
    );
  }

  Future<({HinoDaBiblioteca? hino, String? error})> lerHino(
      String id, int numero) async {
    leiturasDeHino++;
    final t = titulos[numero];
    if (t == null) return (hino: null, error: null);
    return (
      hino: HinoDaBiblioteca(
          hinario: id, numero: numero, titulo: t, letra: 'Letra do $numero'),
      error: null
    );
  }

  Future<({bool success, String? error})> gravarMusica(SongModel m) async {
    if (erroAoGravarMusica != null) {
      return (success: false, error: erroAoGravarMusica);
    }
    gravadas.add(m);
    return (success: true, error: null);
  }
}

BibliotecaProvider _provider(_Banco b, {DateTime Function()? agora}) =>
    BibliotecaProvider(
      lerIndice: b.lerIndice,
      lerHino: b.lerHino,
      gravarMusica: b.gravarMusica,
      gravarHinos: ({
        required Hinario hinario,
        required List<HinoLido> hinos,
        required String porQuemId,
        void Function(int, int)? aoAvancar,
      }) async {
        b.importacoes++;
        return (gravados: hinos.length, error: null);
      },
      agora: agora,
    );

void main() {
  // O aparelho agora guarda o índice e as letras (armazém local): sem limpar,
  // o que um teste leu sobraria para o seguinte.
  setUp(Armazem.esvaziar);

  group('o custo de abrir um hino', () {
    test('número que NÃO está no índice custa zero leituras de letra', () async {
      final b = _Banco();
      final p = _provider(b);
      final r = await p.buscarHino(harpaCrista, 99);
      expect(r.hino, isNull);
      expect(r.error, isNull);
      expect(b.leiturasDeHino, 0);
      expect(b.leiturasDeIndice, 1, reason: 'só o índice, uma vez');
    });

    test('hino que está no índice: UMA leitura de letra', () async {
      final b = _Banco();
      final p = _provider(b);
      final r = await p.buscarHino(harpaCrista, 15);
      expect(r.hino?.titulo, 'Título 15');
      expect(r.hino?.letra, 'Letra do 15');
      expect(b.leiturasDeHino, 1);
    });

    test('abrir o mesmo hino de novo vem da memória: zero leituras', () async {
      final b = _Banco();
      final p = _provider(b);
      await p.buscarHino(harpaCrista, 15);
      await p.buscarHino(harpaCrista, 15);
      await p.buscarHino(harpaCrista, 15);
      expect(b.leiturasDeHino, 1);
      expect(b.leiturasDeIndice, 1);
    });

    test('o índice é lido UMA vez, por mais hinos que se abram', () async {
      final b = _Banco();
      final p = _provider(b);
      await p.buscarHino(harpaCrista, 15);
      await p.buscarHino(harpaCrista, 16);
      await p.buscarHino(harpaCrista, 150);
      await p.buscarHino(harpaCrista, 99);
      expect(b.leiturasDeIndice, 1);
      expect(b.leiturasDeHino, 3);
    });

    test('duas chamadas ao mesmo tempo esperam a MESMA leitura do índice',
        () async {
      // O teclado e a tela de importar pedem juntos ao abrir: duas leituras
      // do mesmo documento seria cota jogada fora.
      final b = _Banco();
      final p = _provider(b);
      await Future.wait([
        p.carregarIndice('harpa'),
        p.carregarIndice('harpa'),
        p.carregarIndice('harpa'),
      ]);
      expect(b.leiturasDeIndice, 1);
    });

    test('cada hinário tem o seu índice, lido uma vez', () async {
      final b = _Banco();
      final p = _provider(b);
      await p.carregarIndice('harpa');
      await p.carregarIndice('cantor');
      await p.carregarIndice('harpa');
      await p.carregarIndice('cantor');
      expect(b.leiturasDeIndice, 2);
    });

    test('o mesmo número em outro hinário não vem da memória do primeiro',
        () async {
      final b = _Banco();
      final p = _provider(b);
      await p.buscarHino(harpaCrista, 15);
      await p.buscarHino(cantorCristao, 15);
      expect(b.leiturasDeHino, 2, reason: 'harpa:15 e cantor:15 são hinos');
    });
  });

  group('a validade do índice', () {
    test('antes de 20 minutos, não lê de novo', () async {
      var agora = DateTime(2026, 11, 19, 10);
      final b = _Banco();
      final p = _provider(b, agora: () => agora);
      await p.carregarIndice('harpa');
      agora = agora.add(const Duration(minutes: 19));
      await p.carregarIndice('harpa');
      expect(b.leiturasDeIndice, 1);
    });

    test('passados 20 minutos, lê de novo — e vê o hino que entrou', () async {
      // Sem isto, um celular com o app aberto desde antes da importação nunca
      // saberia dos hinos novos.
      var agora = DateTime(2026, 11, 19, 10);
      final b = _Banco();
      final p = _provider(b, agora: () => agora);
      await p.carregarIndice('harpa');
      expect(p.indiceDe('harpa').tem(300), isFalse);

      b.titulos[300] = 'Título 300';
      agora = agora.add(const Duration(minutes: 21));
      await p.carregarIndice('harpa');
      expect(b.leiturasDeIndice, 2);
      expect(p.indiceDe('harpa').tem(300), isTrue);
    });

    test('forçar lê de novo na hora', () async {
      final b = _Banco();
      final p = _provider(b);
      await p.carregarIndice('harpa');
      await p.carregarIndice('harpa', forcar: true);
      expect(b.leiturasDeIndice, 2);
    });
  });

  group('quando o banco não responde', () {
    test('erro de leitura vira o MOTIVO, não "não está na biblioteca"',
        () async {
      // São consertos diferentes: um é "sem internet", o outro é "o líder
      // ainda não importou". Confundi-los manda a pessoa para o lugar errado.
      final b = _Banco()..erroDoIndice = 'Sem conexão. Não foi possível ler a lista de hinos.';
      final p = _provider(b);
      final r = await p.buscarHino(harpaCrista, 15);
      expect(r.hino, isNull);
      expect(r.error, contains('Sem conexão'));
      expect(b.leiturasDeHino, 0);
    });

    test('a leitura que falhou não fica presa: tentar de novo funciona',
        () async {
      final b = _Banco()..erroDoIndice = 'Sem conexão.';
      final p = _provider(b);
      await p.buscarHino(harpaCrista, 15);

      b.erroDoIndice = null;
      final r = await p.buscarHino(harpaCrista, 15);
      expect(r.error, isNull);
      expect(r.hino?.numero, 15);
    });

    test('erro não marca o índice como carregado', () async {
      final b = _Banco()..erroDoIndice = 'Sem conexão.';
      final p = _provider(b);
      await p.carregarIndice('harpa');
      expect(p.indiceCarregado('harpa'), isFalse);
    });
  });

  group('importar', () {
    final tres = [
      for (final n in [1, 2, 3])
        HinoLido(numero: n, titulo: 'Título $n', letra: 'Letra $n'),
    ];

    test('depois de importar, a letra guardada é esquecida e o índice relido',
        () async {
      final b = _Banco();
      final p = _provider(b);
      await p.buscarHino(harpaCrista, 15);
      expect(b.leiturasDeHino, 1);

      await p.importar(hinario: harpaCrista, hinos: tres, porQuemId: 'uid');
      // Re-importar serve para CORRIGIR texto: mostrar a letra velha depois
      // seria dizer que a correção não funcionou.
      await p.buscarHino(harpaCrista, 15);
      expect(b.leiturasDeHino, 2);
      expect(b.leiturasDeIndice, 2, reason: 'o índice foi relido');
    });

    test('importar um hinário não esquece o outro', () async {
      final b = _Banco();
      final p = _provider(b);
      await p.buscarHino(cantorCristao, 15);
      await p.importar(hinario: harpaCrista, hinos: tres, porQuemId: 'uid');
      await p.buscarHino(cantorCristao, 15);
      expect(b.leiturasDeHino, 1, reason: 'o do Cantor continua guardado');
    });

    test('importar que não gravou nada não mexe no que está guardado',
        () async {
      final b = _Banco();
      final p = BibliotecaProvider(
        lerIndice: b.lerIndice,
        lerHino: b.lerHino,
        gravarHinos: ({
          required Hinario hinario,
          required List<HinoLido> hinos,
          required String porQuemId,
          void Function(int, int)? aoAvancar,
        }) async =>
            (gravados: 0, error: 'Você não tem permissão.'),
      );
      await p.buscarHino(harpaCrista, 15);
      final r =
          await p.importar(hinario: harpaCrista, hinos: tres, porQuemId: 'uid');
      expect(r.error, 'Você não tem permissão.');
      await p.buscarHino(harpaCrista, 15);
      expect(b.leiturasDeHino, 1);
      expect(b.leiturasDeIndice, 1);
    });

    test('importar que gravou parte e falhou AINDA relê o índice', () async {
      // Parte entrou: o índice tem de mostrar o que entrou.
      final b = _Banco();
      final p = BibliotecaProvider(
        lerIndice: b.lerIndice,
        lerHino: b.lerHino,
        gravarHinos: ({
          required Hinario hinario,
          required List<HinoLido> hinos,
          required String porQuemId,
          void Function(int, int)? aoAvancar,
        }) async =>
            (gravados: 400, error: 'A internet demorou demais.'),
      );
      await p.carregarIndice('harpa');
      await p.importar(hinario: harpaCrista, hinos: tres, porQuemId: 'uid');
      expect(b.leiturasDeIndice, 2);
    });
  });

  group('pôr no repertório', () {
    const hino = HinoDaBiblioteca(
        hinario: 'harpa', numero: 15, titulo: 'Título 15', letra: 'Letra do 15');

    test('grava a música com sigla, hinário e número', () async {
      final b = _Banco();
      final p = _provider(b, agora: () => DateTime(2026, 11, 19));
      final r = await p.porNoRepertorio(harpaCrista, hino, porQuemId: 'uid-lider');
      expect(r.error, isNull);
      expect(b.gravadas.length, 1);
      final m = b.gravadas.single;
      expect(m.name, 'HC 15 · Título 15');
      expect(m.hinario, 'harpa');
      expect(m.numero, 15);
      expect(m.lyrics, 'Letra do 15');
      expect(m.addedBy, 'uid-lider');
      expect(m.createdAt, DateTime(2026, 11, 19));
    });

    test('a música devolvida é a que foi gravada', () async {
      final b = _Banco();
      final p = _provider(b);
      final r = await p.porNoRepertorio(harpaCrista, hino, porQuemId: 'uid');
      expect(r.musica?.id, b.gravadas.single.id);
    });

    test('cada chamada cria um id novo (não há dois hinos com o mesmo id)',
        () async {
      final b = _Banco();
      final p = _provider(b);
      await p.porNoRepertorio(harpaCrista, hino, porQuemId: 'uid');
      await p.porNoRepertorio(harpaCrista, hino, porQuemId: 'uid');
      expect(b.gravadas[0].id, isNot(b.gravadas[1].id));
    });

    test('erro ao gravar volta como motivo, e sem música', () async {
      final b = _Banco()..erroAoGravarMusica = 'Você não tem permissão para salvar a música.';
      final p = _provider(b);
      final r = await p.porNoRepertorio(harpaCrista, hino, porQuemId: 'uid');
      expect(r.musica, isNull);
      expect(r.error, contains('permissão'));
    });
  });
}
