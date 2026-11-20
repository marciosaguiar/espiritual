// "Offline primeiro", a parte da LEITURA e da PREPARAÇÃO: a cópia no aparelho,
// o orçamento de leituras, o cache de áudio com limite, a recuperação de dados
// apagados e os providers que passam pela fila.
//
// TODO o texto é inventado (a regra do projeto: nada com direito autoral).

import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:levitasync/core/constants/hinarios.dart';
import 'package:levitasync/core/platform/armazem.dart';
import 'package:levitasync/core/platform/rede.dart';
import 'package:levitasync/core/utils/fila_de_envio.dart';
import 'package:levitasync/core/utils/fusao_de_edicao.dart';
import 'package:levitasync/core/utils/memoria_do_aparelho.dart';
import 'package:levitasync/core/utils/plano_do_cache.dart';
import 'package:levitasync/core/utils/snapshot_local.dart';
import 'package:levitasync/data/models/arrangement_model.dart';
import 'package:levitasync/data/models/aviso_de_sincronia.dart';
import 'package:levitasync/data/models/hino_da_biblioteca.dart';
import 'package:levitasync/data/models/scale_model.dart';
import 'package:levitasync/data/models/song_model.dart';
import 'package:levitasync/data/services/arranjos_locais.dart';
import 'package:levitasync/data/services/audios_locais.dart';
import 'package:levitasync/data/services/avisos_de_sincronia.dart';
import 'package:levitasync/data/services/hinos_locais.dart';
import 'package:levitasync/data/services/local_storage_service.dart';
import 'package:levitasync/data/services/preparo_offline.dart';
import 'package:levitasync/presentation/providers/biblioteca_provider.dart';
import 'package:levitasync/presentation/providers/scale_provider.dart';
import 'package:levitasync/presentation/providers/songs_provider.dart';
import 'package:levitasync/presentation/widgets/common/faixa_de_rede.dart';
import 'package:levitasync/presentation/widgets/home/avisos_de_sincronia.dart';
import 'package:levitasync/data/services/estado_da_rede.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'utilitarios/dados_inventados.dart';

/// Uma fila de teste: sem rede de verdade, com o executor na mão do teste.
FilaDeEnvio _fila({
  required bool Function() online,
  Map<TipoDeAcao, Executor>? executores,
}) =>
    FilaDeEnvio(
      estaOnline: online,
      executores: executores ??
          {
            for (final t in TipoDeAcao.values)
              t: (_) async => const ResultadoDoEnvio.enviado(),
          },
    );

void main() {
  setUp(() async {
    Armazem.esvaziar();
    SharedPreferences.setMockInitialValues({});
    await LocalStorageService.init();
  });

  // ── a cópia que o aparelho guarda ────────────────────────────────────────
  group('a cópia no aparelho', () {
    test('Timestamp vai e volta como Timestamp (jsonEncode puro lançaria)',
        () async {
      final quando = Timestamp.fromDate(DateTime.utc(2026, 11, 15, 19, 30));
      final ok = await SnapshotLocal.guardar('x', [
        {
          'id': 'a',
          'quando': quando,
          'lista': [1, 'dois', true, null],
          'mapa': {'dentro': quando},
        }
      ]);
      expect(ok, isTrue);
      final volta = (await SnapshotLocal.ler('x'))!.single;
      expect(volta['quando'], quando);
      expect((volta['mapa'] as Map)['dentro'], quando);
      expect(volta['lista'], [1, 'dois', true, null]);
    });

    test('cópia ilegível é ignorada, não derruba nada', () async {
      await Armazem.gravar('snap:x', '{isso não é json');
      expect(await SnapshotLocal.ler('x'), isNull);
      await Armazem.gravar('snap:y', '{"v":999,"em":"2026-01-01","docs":[]}');
      expect(await SnapshotLocal.ler('y'), isNull,
          reason: 'cópia de outra versão não se lê');
    });

    test('tipo que não sabemos guardar: devolve falso e NÃO grava pela metade',
        () async {
      final ok = await SnapshotLocal.guardar('z', [
        {'id': 'a', 'estranho': Object()}
      ]);
      expect(ok, isFalse);
      expect(await SnapshotLocal.ler('z'), isNull);
    });

    test('o ScaleProvider abre com os cultos guardados, ANTES do banco',
        () async {
      final cultos = cultosInventados();
      await SnapshotLocal.guardar(
          'scales', cultos.map((c) => c.toFirestore()).toList());

      final p = ScaleProvider(fila: _fila(online: () => false));
      expect(p.scales, isEmpty);
      final n = await p.restaurarDoAparelho();
      expect(n, cultos.length);
      expect(p.scales.map((s) => s.id), cultos.map((s) => s.id));
      // Os dados voltam inteiros: quem está escalado e quem confirmou.
      expect(p.scales.first.levitas.length, cultos.first.levitas.length);
      expect(p.scales.first.levitas.first.confirmed,
          cultos.first.levitas.first.confirmed);
    });

    test('o SongsProvider abre com o repertório guardado', () async {
      final musicas = repertorioInventado();
      await SnapshotLocal.guardar(
          'songs', musicas.map((m) => m.toFirestore()).toList());
      final p = SongsProvider(fila: _fila(online: () => false));
      expect(await p.restaurarDoAparelho(), musicas.length);
      expect(p.allSongs.map((m) => m.id), musicas.map((m) => m.id));
      expect(p.allSongs.last.numero, musicas.last.numero);
    });
  });

  // ── confirmar presença sem internet ──────────────────────────────────────
  group('presença sem internet', () {
    test('aparece confirmada na hora, fica pendente, e a resposta do banco '
        'NÃO desfaz', () async {
      var online = false;
      final fila = _fila(online: () => online);
      final p = ScaleProvider(fila: fila);
      final cultos = cultosInventados();
      p.carregarParaTeste(cultos);

      final culto = cultos.first; // Carla (u3) ainda não confirmou
      expect(
          culto.levitas.firstWhere((l) => l.userId == 'u3').confirmed, isFalse);

      final erro = await p.confirmPresence(culto.id, 'u3', true);
      expect(erro, isNull, reason: 'ficar na fila não é erro');
      expect(p.presencaPendente(culto.id, 'u3'), isTrue);
      final naTela = p.scales.firstWhere((s) => s.id == culto.id);
      expect(naTela.levitas.firstWhere((l) => l.userId == 'u3').confirmed,
          isTrue);

      // O banco responde com o culto como estava (a confirmação ainda não
      // chegou lá): a tela NÃO pode voltar atrás.
      p.carregarParaTeste(cultos);
      expect(
          p
              .scales
              .firstWhere((s) => s.id == culto.id)
              .levitas
              .firstWhere((l) => l.userId == 'u3')
              .confirmed,
          isTrue);

      // A rede volta: a fila esvazia e o "pendente" some.
      online = true;
      await fila.acordar();
      expect(fila.pendentes, 0);
      expect(p.presencaPendente(culto.id, 'u3'), isFalse);
    });

    test('confirmar e desmarcar offline: UM envio, com o último desejo',
        () async {
      final enviados = <bool>[];
      var online = false;
      final fila = _fila(online: () => online, executores: {
        TipoDeAcao.presenca: (i) async {
          enviados.add(i.dados['confirmado'] as bool);
          return const ResultadoDoEnvio.enviado();
        },
        TipoDeAcao.musica: (_) async => const ResultadoDoEnvio.enviado(),
        TipoDeAcao.arranjo: (_) async => const ResultadoDoEnvio.enviado(),
      });
      final p = ScaleProvider(fila: fila)..carregarParaTeste(cultosInventados());
      final id = cultosInventados().first.id;
      await p.confirmPresence(id, 'u3', true);
      await p.confirmPresence(id, 'u3', false);
      await p.confirmPresence(id, 'u3', true);
      online = true;
      await fila.acordar();
      expect(enviados, [true]);
    });

    test('o banco recusou de vez (não está escalado): a pessoa recebe o '
        'recado, e a presença volta ao que o banco diz', () async {
      final fila = FilaDeEnvio(
        estaOnline: () => true,
        aoAvisar: (a) => AvisosDeSincronia.instancia.adicionar(a),
        executores: {
          TipoDeAcao.presenca: (i) async => ResultadoDoEnvio.descartado(
                'Você não está escalado neste culto.',
                avisos: [
                  AvisoDeSincronia(
                    id: 'a1',
                    tipo: TipoDeRecado.acaoNaoEnviada,
                    criadoEm: DateTime(2026, 11, 20),
                    titulo: 'Sua confirmação não foi enviada',
                    texto: 'Você não está escalado neste culto.',
                  )
                ],
              ),
          TipoDeAcao.musica: (_) async => const ResultadoDoEnvio.enviado(),
          TipoDeAcao.arranjo: (_) async => const ResultadoDoEnvio.enviado(),
        },
      );
      AvisosDeSincronia.instancia.esvaziarParaTeste();
      final p = ScaleProvider(fila: fila)..carregarParaTeste(cultosInventados());
      final id = cultosInventados().first.id;
      final erro = await p.confirmPresence(id, 'u3', true);
      expect(erro, 'Você não está escalado neste culto.');
      expect(fila.pendentes, 0);
      expect(p.presencaPendente(id, 'u3'), isFalse);
      // E a tela volta ao que o banco diz: não confirmada.
      expect(
          p
              .scales
              .firstWhere((s) => s.id == id)
              .levitas
              .firstWhere((l) => l.userId == 'u3')
              .confirmed,
          isFalse);
    });
  });

  // ── editar música sem internet ───────────────────────────────────────────
  group('editar música sem internet', () {
    test('camposQueMudaram: só o que mudou, com a base de antes', () {
      final base = repertorioInventado().first;
      final novo = base.copyWith(name: 'Grande é a fidelidade', originalKey: 'A');
      final c = SongsProvider.camposQueMudaram(base, novo);
      expect(c.keys.toSet(), {'name', 'originalKey'});
      expect(c['name']!.base, 'Grande é a tua fidelidade');
      expect(c['originalKey']!.novo, 'A');
    });

    test('a música aparece alterada, pendente, e sobrevive a uma resposta '
        'velha do banco', () async {
      final fila = _fila(online: () => false);
      final p = SongsProvider(fila: fila);
      final musicas = repertorioInventado();
      p.carregarParaTeste(musicas);
      final m = musicas.first;

      final erro = await p.updateSong(m.copyWith(name: 'Nome corrigido'));
      expect(erro, isNull);
      expect(p.musicaPendente(m.id), isTrue);
      expect(p.allSongs.firstWhere((s) => s.id == m.id).name, 'Nome corrigido');

      // O banco ainda tem o nome velho.
      p.carregarParaTeste(musicas);
      expect(p.allSongs.firstWhere((s) => s.id == m.id).name, 'Nome corrigido');
    });

    test('duas edições seguidas da mesma música viram UM envio, com a base da '
        'PRIMEIRA (é ela que prova se alguém mexeu antes)', () async {
      final fila = _fila(online: () => false);
      final p = SongsProvider(fila: fila)..carregarParaTeste(repertorioInventado());
      final m = repertorioInventado().first;
      await p.updateSong(m.copyWith(name: 'Primeira'));
      final atual = p.allSongs.firstWhere((s) => s.id == m.id);
      await p.updateSong(atual.copyWith(name: 'Segunda'));
      expect(fila.pendentes, 1);
      final c = fila.itens.single.campos['name']!;
      expect(c.base, 'Grande é a tua fidelidade');
      expect(c.novo, 'Segunda');
    });

    test('não mudou nada: nada na fila', () async {
      final fila = _fila(online: () => false);
      final p = SongsProvider(fila: fila)..carregarParaTeste(repertorioInventado());
      expect(await p.updateSong(repertorioInventado().first), isNull);
      expect(fila.pendentes, 0);
    });

    test('a cifra nova (arranjo) fica por cima do que veio do banco', () async {
      final fila = _fila(online: () => false);
      final p = SongsProvider(fila: fila);
      final seNao = ArrangementModel(
        id: 'ar1',
        songId: 'm0',
        name: 'Padrão',
        churchKey: 'G',
        updatedAt: DateTime(2026, 1, 1),
      );
      final r = await p.salvarArranjo(
        songId: 'm0',
        atual: null,
        seNaoExistir: seNao,
        novos: {'chords': 'G  C\nLetra inventada'},
        rotulo: 'Grande é a tua fidelidade',
      );
      expect(r.erro, isNull);
      expect(r.pendente, isTrue);
      expect(r.arranjo!.chords, 'G  C\nLetra inventada');
      expect(p.arranjoPendente('m0'), isTrue);
      // Reabrindo a música, a cifra pendente aparece mesmo sem o banco.
      expect(p.arranjoComPendencias('m0', null)!.chords, 'G  C\nLetra inventada');
    });

    test('quem chegou primeiro ao banco vence, e o atrasado é avisado '
        '(política de conflito de ponta a ponta)', () async {
      // O servidor já tem outro nome, posto por outra pessoa.
      final servidor = {'name': 'Nome da outra pessoa', 'originalKey': 'G'};
      final f = fundirEdicao(meus: {
        'name': CampoEditado(base: 'Nome antigo', novo: 'Meu nome'),
      }, servidor: servidor);
      expect(f.aplicar, isEmpty);
      expect(f.perdas.single.atual, 'Nome da outra pessoa');
    });
  });

  // ── a preparação, e o orçamento de leituras ──────────────────────────────
  group('a preparação respeita o orçamento de leituras', () {
    HinoDaBiblioteca hino(String h, int n) => HinoDaBiblioteca(
        hinario: h,
        numero: n,
        titulo: tituloInventado(n),
        letra: letraInventada(n));

    PreparoOffline preparo({
      required List<int> contadorDeCifras,
      required List<int> contadorDePaginas,
      DateTime Function()? agora,
      int limite = 20,
      bool Function()? online,
      int totalDeHinos = 120,
      DateTime? importadoEm,
    }) {
      return PreparoOffline(
        agora: agora ?? () => DateTime(2026, 11, 20, 10),
        online: online ?? () => true,
        limiteDiario: limite,
        lerCifra: (id) async {
          contadorDeCifras.add(1);
          return (arranjo: null, ok: true);
        },
        lerIndice: (h) async => (
          indice: IndiceDoHinario(
            hinario: h,
            titulos: {for (var n = 1; n <= totalDeHinos; n++) n: tituloInventado(n)},
            atualizadoEm: importadoEm ?? DateTime.utc(2026, 11, 1),
          ),
          error: null
        ),
        lerPagina: (h, {required depoisDe, required limite}) async {
          final lista = [
            for (var n = depoisDe + 1;
                n <= totalDeHinos && n <= depoisDe + limite;
                n++)
              hino(h, n),
          ];
          contadorDePaginas.add(lista.length);
          return (hinos: lista, error: null);
        },
        baixarBiblia: (_) async {},
      );
    }

    test('NUNCA passa do orçamento do dia, e o que sobra espera amanhã',
        () async {
      final cifras = <int>[];
      final paginas = <int>[];
      final p = preparo(contadorDeCifras: cifras, contadorDePaginas: paginas);
      final r = await p.executar(
        idsDeMusicas: [for (var i = 0; i < 5; i++) 'm$i'],
        hinarios: ['harpa'],
      );
      // 5 cifras + 1 índice + 14 hinos = 20. Nem uma a mais.
      expect(r.leiturasGastas, 20);
      expect(cifras.length, 5);
      expect(paginas.fold<int>(0, (a, b) => a + b), 14);
      expect(r.parouPor, 'orçamento do dia');
      expect(await p.restanteHoje(), 0);

      // Rodar de novo no MESMO dia não gasta nada.
      final de_novo = await p.executar(
          idsDeMusicas: [for (var i = 0; i < 5; i++) 'm$i'], hinarios: ['harpa']);
      expect(de_novo.leiturasGastas, 0);
    });

    test('no dia seguinte continua de onde parou, sem pedir de novo o que já '
        'tem', () async {
      var agora = DateTime(2026, 11, 20, 10);
      final cifras = <int>[];
      final paginas = <int>[];
      final p = preparo(
          contadorDeCifras: cifras,
          contadorDePaginas: paginas,
          agora: () => agora,
          limite: 60);
      await p.executar(idsDeMusicas: ['m0', 'm1'], hinarios: ['harpa']);
      final dia1 = paginas.fold<int>(0, (a, b) => a + b);
      expect(dia1, 57, reason: '60 - 2 cifras - 1 índice');
      expect((await HinosLocais.lerHino('harpa', 57))!.titulo, tituloInventado(57));
      expect(await HinosLocais.lerHino('harpa', 58), isNull);

      agora = DateTime(2026, 11, 21, 9);
      final r2 = await p.executar(
          idsDeMusicas: ['m0', 'm1'], hinarios: ['harpa']);
      // As 2 cifras e o índice já são conhecidos: nada disso é lido de novo.
      expect(cifras.length, 2);
      expect(r2.hinos, 60);
      expect((await HinosLocais.lerHino('harpa', 58))!.titulo, tituloInventado(58));
      expect((await HinosLocais.lerHino('harpa', 117))!.titulo, tituloInventado(117));

      // Dia 3: termina o hinário (120) e para — não fica perguntando.
      agora = DateTime(2026, 11, 22, 9);
      final r3 = await p.executar(
          idsDeMusicas: ['m0', 'm1'], hinarios: ['harpa']);
      expect(r3.hinos, 3);
      expect(r3.parouPor, isNull);
      final r4 = await p.executar(
          idsDeMusicas: ['m0', 'm1'], hinarios: ['harpa']);
      expect(r4.leiturasGastas, 0);
    });

    test('música sem cifra é lembrada: não se pergunta de novo amanhã',
        () async {
      var agora = DateTime(2026, 11, 20, 10);
      final cifras = <int>[];
      final p = preparo(
          contadorDeCifras: cifras,
          contadorDePaginas: [],
          agora: () => agora);
      await p.executar(idsDeMusicas: ['m0'], hinarios: []);
      agora = DateTime(2026, 11, 21, 10);
      await p.executar(idsDeMusicas: ['m0'], hinarios: []);
      expect(cifras.length, 1);
      expect(await ArranjosLocais.jaSabe('m0'), isTrue);
      expect(await ArranjosLocais.ler('m0'), isNull);
    });

    test('o líder importou de novo (marca mudou): o hinário recomeça, e a '
        'letra velha não é servida', () async {
      var agora = DateTime(2026, 11, 20, 10);
      final paginas = <int>[];
      var importadoEm = DateTime.utc(2026, 11, 1);
      PreparoOffline novo() => preparo(
          contadorDeCifras: [],
          contadorDePaginas: paginas,
          agora: () => agora,
          limite: 200,
          totalDeHinos: 30,
          importadoEm: importadoEm);

      await novo().executar(idsDeMusicas: [], hinarios: ['harpa']);
      expect(await HinosLocais.quantosGuardados('harpa', '${DateTime.utc(2026, 11, 1).millisecondsSinceEpoch}'), 30);

      // O aparelho guardou o índice velho; o servidor agora tem outro.
      await HinosLocais.esquecerHinario('harpa'); // o que o provider faz ao importar
      importadoEm = DateTime.utc(2026, 11, 18);
      agora = DateTime(2026, 11, 21, 10);
      paginas.clear();
      final r = await novo().executar(idsDeMusicas: [], hinarios: ['harpa']);
      expect(r.hinos, 30, reason: 'recomeçou do 1');
      final marcaNova = '${DateTime.utc(2026, 11, 18).millisecondsSinceEpoch}';
      expect(await HinosLocais.lerHino('harpa', 5, marcaAtual: marcaNova), isNotNull);
      expect(
          await HinosLocais.lerHino('harpa', 5, marcaAtual: 'marca-velha'), isNull,
          reason: 'letra de outra importação não vale');
    });

    test('sem internet: não faz nada (e não gasta nada)', () async {
      final p = preparo(
          contadorDeCifras: [], contadorDePaginas: [], online: () => false);
      final r = await p.executar(idsDeMusicas: ['m0'], hinarios: ['harpa']);
      expect(r.leiturasGastas, 0);
      expect(r.parouPor, 'sem internet');
    });

    test('falha de rede no meio: para, e o que já veio fica guardado', () async {
      var chamadas = 0;
      final p = PreparoOffline(
        agora: () => DateTime(2026, 11, 20, 10),
        online: () => true,
        lerCifra: (id) async {
          chamadas++;
          return chamadas == 3
              ? (arranjo: null, ok: false)
              : (arranjo: null, ok: true);
        },
        lerIndice: (_) async => (indice: null, error: 'sem rede'),
        lerPagina: (h, {required depoisDe, required limite}) async =>
            (hinos: null, error: 'sem rede'),
        baixarBiblia: (_) async {},
      );
      final r =
          await p.executar(idsDeMusicas: ['a', 'b', 'c', 'd'], hinarios: []);
      expect(r.parouPor, 'falha de rede');
      expect(await ArranjosLocais.jaSabe('a'), isTrue);
      expect(await ArranjosLocais.jaSabe('b'), isTrue);
      expect(await ArranjosLocais.jaSabe('c'), isFalse);
      expect(await ArranjosLocais.jaSabe('d'), isFalse);
    });

    test('a Bíblia é uma baixada só, não gasta leitura do banco e não se '
        'repete', () async {
      var baixadas = 0;
      final p = PreparoOffline(
        agora: () => DateTime(2026, 11, 20, 10),
        online: () => true,
        lerCifra: (_) async => (arranjo: null, ok: true),
        baixarBiblia: (_) async => baixadas++,
      );
      final r1 = await p.executar(
          idsDeMusicas: [], hinarios: [], traducaoDaBiblia: 'blivre');
      final r2 = await p.executar(
          idsDeMusicas: [], hinarios: [], traducaoDaBiblia: 'blivre');
      expect(baixadas, 1);
      expect(r1.biblia, isTrue);
      expect(r1.leiturasGastas, 0);
      expect(r2.biblia, isFalse);
    });
  });

  // ── o iPhone apagou os dados ─────────────────────────────────────────────
  group('o aparelho apagou os dados do site', () {
    Future<void> arrumarTudoComo() async {
      await PreparoOffline.conferirAparelho(); // primeira vez: deixa as marcas
      await ArranjosLocais.guardar(ArrangementModel(
          id: 'a', songId: 'm0', name: 'x', churchKey: 'G', updatedAt: DateTime(2026)));
      await SnapshotLocal.guardar('songs', [{'id': 'm0'}]);
      await Armazem.gravar(PreparoOffline.chaveDoOrcamento, '{"dia":"2026-11-20","gasto":200}');
      await Armazem.gravar(PreparoOffline.chaveDoProgresso, '{"harpa":{"ate":300}}');
    }

    test('primeira vez: deixa as duas marcas e não apaga nada', () async {
      expect(await PreparoOffline.conferirAparelho(), VereditoDoAparelho.primeiraVez);
      expect(await PreparoOffline.conferirAparelho(), VereditoDoAparelho.tudoCerto);
    });

    test('o navegador apagou o IndexedDB e deixou o localStorage: percebe, '
        'esquece o derivado e recomeça — SEM tocar na fila de envio', () async {
      await arrumarTudoComo();
      await Armazem.gravar(FilaDeEnvio.chaveNoArmazem, '["pendente"]');
      await Armazem.gravar('avisos-sync:v1', '[]');

      // O iPhone levou o IndexedDB (tudo, inclusive a marca do armazém)...
      Armazem.esvaziar();
      // ...mas a fila é da pessoa: simulamos o que o app faria — ela estava no
      // IndexedDB também, então a única proteção possível é NÃO apagá-la
      // quando só sobra uma das marcas. Reposta aqui para provar que a rotina
      // de recuperação não a toca.
      await Armazem.gravar(FilaDeEnvio.chaveNoArmazem, '["pendente"]');

      expect(await PreparoOffline.conferirAparelho(),
          VereditoDoAparelho.dadosApagados);
      expect(await Armazem.ler(PreparoOffline.chaveDoOrcamento), isNull);
      expect(await Armazem.ler(FilaDeEnvio.chaveNoArmazem), '["pendente"]',
          reason: 'o que a pessoa fez e não chegou ao banco não se perde');
      // As marcas voltaram: da próxima vez está tudo certo.
      expect(await PreparoOffline.conferirAparelho(), VereditoDoAparelho.tudoCerto);
    });

    test('esquecer o derivado zera cota, progresso, cifras, hinos e áudios, '
        'mas guarda fila e recados', () async {
      await arrumarTudoComo();
      await HinosLocais.guardarHino(
          HinoDaBiblioteca(hinario: 'harpa', numero: 1, titulo: 't', letra: 'l'), 'm');
      await AudiosLocais.guardar('au1', Uint8List.fromList([1, 2, 3]), 'audio/mp4');
      await Armazem.gravar(FilaDeEnvio.chaveNoArmazem, '["x"]');
      await Armazem.gravar('avisos-sync:v1', '["y"]');

      await PreparoOffline.esquecerOQueEDerivado();

      expect(await Armazem.ler(PreparoOffline.chaveDoOrcamento), isNull);
      expect(await Armazem.ler(PreparoOffline.chaveDoProgresso), isNull);
      expect(await ArranjosLocais.quantas(), 0);
      expect(await SnapshotLocal.ler('songs'), isNull);
      expect(await HinosLocais.lerHino('harpa', 1), isNull);
      expect(await AudiosLocais.ler('au1'), isNull);
      expect(await Armazem.ler(FilaDeEnvio.chaveNoArmazem), '["x"]');
      expect(await Armazem.ler('avisos-sync:v1'), '["y"]');
    });
  });

  // ── áudios com limite de espaço ──────────────────────────────────────────
  group('áudios do chat: só ao tocar, e com limite', () {
    final t0 = DateTime(2026, 11, 1);

    test('planejarDespejo solta o menos usado primeiro, só o necessário', () {
      final itens = [
        ItemDoCache('velho', 40, t0),
        ItemDoCache('meio', 40, t0.add(const Duration(days: 1))),
        ItemDoCache('novo', 40, t0.add(const Duration(days: 2))),
      ];
      expect(planejarDespejo(itens: itens, novoTamanho: 30, limite: 150), isEmpty);
      expect(planejarDespejo(itens: itens, novoTamanho: 50, limite: 150), ['velho']);
      expect(planejarDespejo(itens: itens, novoTamanho: 90, limite: 150),
          ['velho', 'meio']);
    });

    test('item maior que o cache inteiro NÃO esvazia o cache: não se guarda',
        () {
      final itens = [ItemDoCache('a', 10, t0)];
      expect(planejarDespejo(itens: itens, novoTamanho: 500, limite: 100), isNull);
    });

    test('desempate estável: mesma hora, sai pelo id', () {
      final itens = [ItemDoCache('b', 60, t0), ItemDoCache('a', 60, t0)];
      expect(planejarDespejo(itens: itens, novoTamanho: 60, limite: 120), ['a']);
    });

    test('guarda, lê de volta, e passado o limite solta o mais antigo',
        () async {
      Uint8List som(int n) => Uint8List.fromList(List.filled(n, 7));
      expect(await AudiosLocais.guardar('a', som(40), 'audio/mp4',
          agora: t0, limite: 100), isTrue);
      expect(await AudiosLocais.guardar('b', som(40), 'audio/webm',
          agora: t0.add(const Duration(hours: 1)), limite: 100), isTrue);
      // Ouvir "a" de novo o torna o mais recente.
      final a = await AudiosLocais.ler('a', agora: t0.add(const Duration(hours: 2)));
      expect(a!.bytes.length, 40);
      expect(a.tipo, 'audio/mp4');
      // "c" não cabe junto dos dois: sai "b", o menos usado.
      expect(await AudiosLocais.guardar('c', som(40), 'audio/mp4',
          agora: t0.add(const Duration(hours: 3)), limite: 100), isTrue);
      expect(await AudiosLocais.ler('b'), isNull);
      expect(await AudiosLocais.ler('a'), isNotNull);
      expect(await AudiosLocais.ler('c'), isNotNull);
      expect(await AudiosLocais.bytesGuardados(), 80);
    });

    test('guardar o MESMO áudio de novo não conta o espaço duas vezes (e '
        'não despeja outro à toa)', () async {
      await AudiosLocais.guardar('b', Uint8List(40), 'audio/mp4',
          agora: t0, limite: 100);
      await AudiosLocais.guardar('a', Uint8List(40), 'audio/mp4',
          agora: t0.add(const Duration(hours: 1)), limite: 100);
      // Regrava "a": o espaço dele já estava contado. Contando de novo seriam
      // 120 e o "b" (o mais antigo) sairia sem necessidade.
      await AudiosLocais.guardar('a', Uint8List(40), 'audio/mp4',
          agora: t0.add(const Duration(hours: 2)), limite: 100);
      expect(await AudiosLocais.bytesGuardados(), 80);
      expect(await AudiosLocais.ler('b'), isNotNull);
      expect(await AudiosLocais.ler('a'), isNotNull);
    });

    test('áudio maior que o limite não é guardado e nada é apagado', () async {
      await AudiosLocais.guardar('a', Uint8List(10), 'audio/mp4', limite: 100);
      expect(await AudiosLocais.guardar('grande', Uint8List(500), 'audio/mp4',
          limite: 100), isFalse);
      expect(await AudiosLocais.ler('a'), isNotNull);
    });

    test('o limite oficial é maior que a maior mensagem possível (800 KiB)',
        () {
      expect(AudiosLocais.limiteDeBytes, greaterThan(10 * 800 * 1024));
    });
  });

  // ── a faixa ──────────────────────────────────────────────────────────────
  group('a faixa de rede na tela', () {
    testWidgets('com internet e nada pendente: não existe', (t) async {
      final estado = EstadoDaRede.instancia
        ..definirParaTeste(online: true);
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: FaixaDeRede(
                estado: estado, child: const Text('conteúdo da aba'))),
      ));
      expect(find.byIcon(Icons.cloud_off_rounded), findsNothing);
      expect(find.text('conteúdo da aba'), findsOneWidget);
    });

    testWidgets('sem internet há mais de 10 s: diz, sem alarmar', (t) async {
      final agora = DateTime(2026, 11, 20, 12);
      final estado = EstadoDaRede.instancia.._offline(agora);
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: FaixaDeRede(
                estado: estado,
                agora: () => agora.add(const Duration(seconds: 30)),
                child: const Text('conteúdo da aba'))),
      ));
      expect(find.textContaining('Sem internet'), findsOneWidget);
      expect(find.byIcon(Icons.cloud_off_rounded), findsOneWidget);
      EstadoDaRede.instancia.definirParaTeste(online: true);
    });

    testWidgets('a aba NÃO é reconstruída quando a faixa aparece (a busca '
        'digitada e a rolagem sobrevivem a um elevador)', (t) async {
      final agora = DateTime(2026, 11, 20, 12);
      final estado = EstadoDaRede.instancia..definirParaTeste(online: true);
      var hora = agora;
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: FaixaDeRede(
                estado: estado, agora: () => hora, child: const _Contador())),
      ));
      await t.tap(find.byType(_Contador));
      await t.pump();
      expect(find.text('toques: 1'), findsOneWidget);

      estado._offline(agora);
      hora = agora.add(const Duration(seconds: 30));
      await t.pump(const Duration(seconds: 6));
      expect(find.textContaining('Sem internet'), findsOneWidget);
      expect(find.text('toques: 1'), findsOneWidget,
          reason: 'o estado da aba tem de continuar o mesmo');
      EstadoDaRede.instancia.definirParaTeste(online: true);
    });
  });

  // ── os hinos abrem do aparelho ───────────────────────────────────────────
  group('hino pelo número, do aparelho', () {
    var lerIndiceDoBanco = 0;
    var lerHinoDoBanco = 0;
    String? erroDoIndice;

    BibliotecaProvider provider() => BibliotecaProvider(
          lerIndice: (id) async {
            lerIndiceDoBanco++;
            if (erroDoIndice != null) return (indice: null, error: erroDoIndice);
            return (
              indice: IndiceDoHinario(
                  hinario: id,
                  titulos: {15: 'Título 15', 16: 'Título 16'},
                  atualizadoEm: DateTime.utc(2026, 11, 1)),
              error: null
            );
          },
          lerHino: (id, n) async {
            lerHinoDoBanco++;
            return (
              hino: HinoDaBiblioteca(
                  hinario: id, numero: n, titulo: 'Título $n', letra: 'Letra $n'),
              error: null
            );
          },
        );

    setUp(() {
      lerIndiceDoBanco = 0;
      lerHinoDoBanco = 0;
      erroDoIndice = null;
      Rede.definir(true);
    });

    test('1ª vez com internet: lê do banco e GUARDA; na 2ª, o hino abre sem '
        'ler nada do banco', () async {
      final a = provider();
      await a.carregarIndice('harpa');
      final r1 = await a.buscarHino(harpaCrista, 15);
      expect(r1.hino!.letra, 'Letra 15');
      expect(lerHinoDoBanco, 1);
      await Future<void>.delayed(Duration.zero); // a gravação não é esperada

      // "Outra abertura do app": provider novo, mesma memória do aparelho.
      final b = provider();
      Rede.definir(false);
      expect(await b.carregarIndice('harpa'), isNull,
          reason: 'sem internet e com cópia: não é erro');
      expect(b.indiceDe('harpa').tem(15), isTrue);
      final r2 = await b.buscarHino(harpaCrista, 15);
      expect(r2.hino!.letra, 'Letra 15');
      expect(r2.error, isNull);
      expect(lerHinoDoBanco, 1, reason: 'abriu do aparelho, zero leituras');
    });

    test('com cópia e COM internet: a tela não espera a rede, e o banco '
        'atualiza em segundo plano', () async {
      await HinosLocais.guardarIndice(IndiceDoHinario(
          hinario: 'harpa',
          titulos: {15: 'Título velho'},
          atualizadoEm: DateTime.utc(2026, 10, 1)));
      final p = provider();
      expect(await p.carregarIndice('harpa'), isNull);
      // Já tem o que mostrar, na hora...
      expect(p.indiceDe('harpa').tem(15), isTrue);
      // ...e o banco responde logo depois, trazendo o novo.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(lerIndiceDoBanco, 1);
      expect(p.indiceDe('harpa').tem(16), isTrue);
    });

    test('sem cópia e sem internet: o recado diz o que fazer, na hora, sem '
        'esperar o banco', () async {
      erroDoIndice = 'Sem conexão.';
      final p = provider();
      final erro = await p.carregarIndice('harpa');
      expect(erro, 'Sem conexão.');
    });

    test('sem internet e hino NUNCA aberto neste aparelho: diz isso e não '
        'tenta ler do banco', () async {
      await HinosLocais.guardarIndice(IndiceDoHinario(
          hinario: 'harpa',
          titulos: {15: 'Título 15', 16: 'Título 16'},
          atualizadoEm: DateTime.utc(2026, 11, 1)));
      Rede.definir(false);
      final p = provider();
      await p.carregarIndice('harpa');
      final r = await p.buscarHino(harpaCrista, 16);
      expect(r.hino, isNull);
      expect(r.error, contains('Sem internet'));
      expect(r.error, contains('abra-o uma vez'));
      expect(lerHinoDoBanco, 0);
    });

    test('letra guardada de OUTRA importação não é servida (o líder '
        'corrigiu o texto)', () async {
      await HinosLocais.guardarIndice(IndiceDoHinario(
          hinario: 'harpa',
          titulos: {15: 'Título 15'},
          atualizadoEm: DateTime.utc(2026, 11, 1)));
      await HinosLocais.guardarHino(
          HinoDaBiblioteca(
              hinario: 'harpa', numero: 15, titulo: 'Título 15', letra: 'Texto velho'),
          'marca-de-outra-importacao');
      final p = provider();
      await p.carregarIndice('harpa');
      final r = await p.buscarHino(harpaCrista, 15);
      expect(r.hino!.letra, 'Letra 15', reason: 'veio do banco, não do velho');
      expect(lerHinoDoBanco, 1);
    });

    test('número fora do índice continua custando ZERO leituras de letra',
        () async {
      final p = provider();
      final r = await p.buscarHino(harpaCrista, 999);
      expect(r.hino, isNull);
      expect(lerHinoDoBanco, 0);
    });
  });

  // ── o recado de edição perdida ───────────────────────────────────────────
  group('recados de sincronia no Início', () {
    final aviso = AvisoDeSincronia(
      id: 'r1',
      tipo: TipoDeRecado.edicaoPerdida,
      criadoEm: DateTime(2026, 11, 20),
      titulo: 'Sua alteração em "Porto seguro" não foi aplicada',
      texto: 'Nome: você pôs "A", mas outra pessoa já tinha mudado para "B".',
      songId: 'm1',
      alvo: 'musica',
      perdas: const [PerdaDeCampo(campo: 'name', minha: 'A', atual: 'B')],
    );

    testWidgets('sem recado: nada na tela', (t) async {
      AvisosDeSincronia.instancia.esvaziarParaTeste();
      await t.pumpWidget(const MaterialApp(
          home: Scaffold(body: CartaoDeAvisosDeSincronia())));
      expect(find.text('Entendi'), findsNothing);
    });

    testWidgets('mostra o que ficou e oferece "Aplicar a minha mesmo assim"; '
        '"Entendi" tira o recado (e só ele)', (t) async {
      AvisosDeSincronia.instancia.esvaziarParaTeste();
      await AvisosDeSincronia.instancia.adicionar([aviso]);
      AvisoDeSincronia? reaplicado;
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: CartaoDeAvisosDeSincronia(
                aoReaplicar: (a) async => reaplicado = a)),
      ));
      expect(find.textContaining('não foi aplicada'), findsOneWidget);
      expect(find.textContaining('outra pessoa já tinha mudado'), findsOneWidget);

      await t.tap(find.text('Aplicar a minha mesmo assim'));
      await t.pump();
      expect(reaplicado?.id, 'r1');

      await t.tap(find.text('Entendi'));
      await t.pump();
      expect(find.text('Entendi'), findsNothing);
      expect(AvisosDeSincronia.instancia.temAviso, isFalse);
    });

    testWidgets('recado de ação não enviada não oferece reaplicar: não há '
        'campo a reaplicar', (t) async {
      AvisosDeSincronia.instancia.esvaziarParaTeste();
      await AvisosDeSincronia.instancia.adicionar([
        AvisoDeSincronia(
          id: 'r2',
          tipo: TipoDeRecado.acaoNaoEnviada,
          criadoEm: DateTime(2026, 11, 20),
          titulo: 'Uma mensagem do chat não foi enviada',
          texto: 'Sem permissão.',
        )
      ]);
      await t.pumpWidget(const MaterialApp(
          home: Scaffold(body: CartaoDeAvisosDeSincronia())));
      expect(find.text('Aplicar a minha mesmo assim'), findsNothing);
      expect(find.text('Entendi'), findsOneWidget);
      AvisosDeSincronia.instancia.esvaziarParaTeste();
    });
  });

  // ── o que é guardado como "vazio" nunca vale como verdade ────────────────
  test('ArranjosLocais: a ausência guardada não vira uma cifra', () async {
    await ArranjosLocais.guardarAusencia('m9');
    expect(await ArranjosLocais.ler('m9'), isNull);
    expect(await ArranjosLocais.jaSabe('m9'), isTrue);
    expect(await ArranjosLocais.quantas(), 0);
  });

  test('um culto sem ninguém escalado sobrevive ao ir e vir da cópia',
      () async {
    final vazio = ScaleModel(
      id: 'c1',
      date: DateTime(2026, 12, 6, 19),
      serviceType: 'Culto',
      createdBy: 'u1',
      createdAt: DateTime(2026, 1, 1),
    );
    await SnapshotLocal.guardar('scales', [vazio.toFirestore()]);
    final p = ScaleProvider(fila: _fila(online: () => false));
    expect(await p.restaurarDoAparelho(), 1);
    expect(p.scales.single.levitas, isEmpty);
  });
}

/// Um filho com estado, para provar que a árvore não o reconstrói.
class _Contador extends StatefulWidget {
  const _Contador();
  @override
  State<_Contador> createState() => _ContadorState();
}

class _ContadorState extends State<_Contador> {
  int _n = 0;
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () => setState(() => _n++),
        child: Text('toques: $_n'),
      );
}

extension on EstadoDaRede {
  void _offline(DateTime desde) =>
      definirParaTeste(online: false, offlineDesde: desde);
}
