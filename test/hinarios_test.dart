import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:levitasync/core/constants/hinarios.dart';
import 'package:levitasync/data/models/song_model.dart';
import 'package:levitasync/presentation/providers/songs_provider.dart';

/// Hino pelo número: a conta que decide se o hino abre em segundos.
///
/// O caso que isto protege é o do dirigente anunciando "hino 15 da Harpa" com
/// a igreja de pé. Tudo aqui é função pura — número, título, busca —, porque
/// é justamente a parte que erra em silêncio: um teclado que não acha o hino
/// não dá erro nenhum, só não abre.

SongModel hino(
  String hinario,
  int? numero,
  String nome, {
  String artista = 'Harpa Cristã',
  String letra = '',
  bool fora = false,
}) =>
    SongModel(
      id: '$hinario-$numero-$nome',
      name: nome,
      artist: artista,
      lyrics: letra,
      originalKey: 'G',
      createdAt: DateTime(2026, 11, 18),
      hinario: hinario,
      numero: numero,
      archived: fora,
    );

void main() {
  group('o número existe no hinário?', () {
    test('o caso do roteiro: não existe o hino 700', () {
      // A Harpa vai até 640 e o Cantor até 581. Dizer "não existe" é melhor
      // que dizer "ainda não está no repertório": o segundo manda o líder
      // cadastrar um hino que não existe em livro nenhum.
      expect(harpaCrista.existe(700), isFalse);
      expect(cantorCristao.existe(700), isFalse);
      expect(cantorCristao.existe(600), isFalse);
    });

    test('as bordas, que é onde este tipo de conta quebra', () {
      expect(harpaCrista.existe(0), isFalse);
      expect(harpaCrista.existe(1), isTrue);
      expect(harpaCrista.existe(640), isTrue);
      expect(harpaCrista.existe(641), isFalse);
      expect(cantorCristao.existe(581), isTrue);
      expect(cantorCristao.existe(582), isFalse);
    });

    test('número negativo não vira hino', () {
      expect(harpaCrista.existe(-15), isFalse);
    });
  });

  group('abrir sem confirmar', () {
    test('quando nenhum número maior é possível, abre na hora', () {
      // 650 passa de 640, então "65" não pode crescer: não há o que esperar.
      expect(harpaCrista.podeCrescer('65'), isFalse);
      expect(harpaCrista.podeCrescer('100'), isFalse);
      // No Cantor o teto é mais baixo, então o mesmo "65" já é final... não:
      // 650 > 581 também. O que muda é a fronteira.
      expect(cantorCristao.podeCrescer('59'), isFalse);
      expect(cantorCristao.podeCrescer('58'), isTrue); // 580 existe
    });

    test('quando ainda pode crescer, espera o próximo dígito', () {
      expect(harpaCrista.podeCrescer('1'), isTrue);
      expect(harpaCrista.podeCrescer('15'), isTrue); // pode virar 150
      expect(harpaCrista.podeCrescer('64'), isTrue); // pode virar 640
    });

    test('zero e vazio esperam, em vez de abrir o "hino 0"', () {
      // Quem toca "0" por engano antes do 5 não pode receber um
      // "não existe o hino 0" na cara no mesmo instante.
      expect(harpaCrista.podeCrescer(''), isTrue);
      expect(harpaCrista.podeCrescer('0'), isTrue);
    });
  });

  group('o título que a música ganha', () {
    test('leva a sigla e o número, para o hino se reconhecer na escala', () {
      // A sigla fica gravada no nome de propósito: é o que faz o hino
      // aparecer identificado na escala, no chat e no lembrete da véspera sem
      // que nenhuma dessas telas saiba o que é um hinário.
      expect(harpaCrista.tituloDe(15, 'Sou Grato'), 'HC 15 · Sou Grato');
      expect(cantorCristao.tituloDe(125, 'Firme nas Promessas'),
          'CC 125 · Firme nas Promessas');
    });

    test('espaço sobrando no nome digitado não entra no título', () {
      expect(harpaCrista.tituloDe(15, '  Sou Grato  '), 'HC 15 · Sou Grato');
    });

    test('todo título gerado contém o número', () {
      // Se um dia alguém "melhorar" o formato e tirar o número, o hino deixa
      // de ser identificável justamente nas telas que não sabem de hinário.
      for (final h in hinariosDisponiveis) {
        for (final n in [1, 15, 125, 581]) {
          expect(h.tituloDe(n, 'Nome'), contains('$n'));
        }
      }
    });
  });

  group('o registro de hinários', () {
    test('id desconhecido devolve nulo, nunca o primeiro da lista', () {
      // Documento com `hinario` escrito errado no console tem de aparecer
      // como música comum, não como hino do hinário errado.
      expect(hinarioPorId('harpa')?.nome, 'Harpa Cristã');
      expect(hinarioPorId('cantor')?.nome, 'Cantor Cristão');
      expect(hinarioPorId('Harpa'), isNull); // maiúscula é outro id
      expect(hinarioPorId('nao-existe'), isNull);
      expect(hinarioPorId(''), isNull);
      expect(hinarioPorId(null), isNull);
    });

    test('nada repetido, nada vazio, nada com teto zero', () {
      final ids = hinariosDisponiveis.map((h) => h.id).toList();
      final siglas = hinariosDisponiveis.map((h) => h.sigla).toList();
      expect(ids.toSet().length, ids.length, reason: 'id repetido');
      expect(siglas.toSet().length, siglas.length, reason: 'sigla repetida');
      for (final h in hinariosDisponiveis) {
        expect(h.id, isNotEmpty);
        expect(h.nome, isNotEmpty);
        expect(h.sigla, isNotEmpty);
        expect(h.ultimo, greaterThan(0));
      }
    });

    test('a regra do banco conhece TODOS os hinários do app', () {
      // Contrato entre dois lugares, como o da agenda fixa. A lista na regra
      // é fechada: um hinário acrescentado aqui e esquecido lá seria recusado
      // pelo banco na hora de cadastrar, com erro de permissão — que não
      // explica nada a ninguém.
      final regras = File('firestore.rules').readAsStringSync();
      final lista = RegExp(r"d\.hinario in \[([^\]]*)\]").firstMatch(regras);
      expect(lista, isNotNull, reason: 'a lista fechada saiu do firestore.rules');
      for (final h in hinariosDisponiveis) {
        expect(lista!.group(1), contains("'${h.id}'"),
            reason: '${h.id} não está na regra');
      }
    });
  });

  group('achar o hino na lista', () {
    final repertorio = [
      hino('harpa', 15, 'Sou Grato'),
      hino('harpa', 150, 'Outro Hino'),
      hino('cantor', 15, 'Hino Batista', artista: 'Cantor Cristão'),
      SongModel(
        id: 'comum',
        name: 'Digno És',
        artist: 'Hillsong',
        lyrics: '',
        originalKey: 'C',
        createdAt: DateTime(2026),
      ),
    ];

    test('acha pelos CAMPOS, e o hinário faz parte da chave', () {
      expect(SongsProvider.acharHino(repertorio, 'harpa', 15)?.name,
          'Sou Grato');
      // Mesmo número, hinário diferente: são hinos diferentes. Sem o hinário
      // na chave, o teclado abriria o hino errado — o pior desfecho possível,
      // porque a pessoa toca sem perceber.
      expect(SongsProvider.acharHino(repertorio, 'cantor', 15)?.name,
          'Hino Batista');
      expect(SongsProvider.acharHino(repertorio, 'harpa', 150)?.name,
          'Outro Hino');
    });

    test('número que ninguém cadastrou devolve nulo', () {
      expect(SongsProvider.acharHino(repertorio, 'harpa', 16), isNull);
      expect(SongsProvider.acharHino(repertorio, 'cantor', 150), isNull);
    });

    test('música comum nunca é achada como hino', () {
      expect(SongsProvider.acharHino(repertorio, '', 0), isNull);
      // E não é achada nem procurando com hinário vazio e número nulo, que é
      // exatamente o que ela tem gravado.
      expect(repertorio.last.ehHino, isFalse);
    });

    test('hino meio cadastrado não é hino', () {
      // Hinário sem número não dá para abrir; número sem hinário não dá para
      // saber de onde é. A regra do banco recusa os dois, mas documento
      // mexido no console chega assim — e não pode derrubar nada.
      expect(hino('harpa', null, 'Sem número').ehHino, isFalse);
      expect(hino('', 15, 'Sem hinário').ehHino, isFalse);
      expect(SongsProvider.acharHino(
              [hino('harpa', null, 'Sem número')], 'harpa', 15),
          isNull);
    });
  });

  group('busca de hino', () {
    final lista = [
      hino('harpa', 150, 'Ao Deus de Abraão'),
      hino('harpa', 15, 'Sou Grato', letra: 'Sou grato pelo seu amor'),
      hino('harpa', 7, 'Coração Contrito', letra: 'Firme nas promessas'),
      hino('cantor', 1, 'Antífona'),
    ];

    test('vem em ordem de número, não na ordem do banco', () {
      // Lista que dança a cada abertura faz a pessoa tocar na linha errada.
      final r = SongsProvider.hinosFiltrados(lista, 'harpa', '');
      expect(r.map((h) => h.numero).toList(), [7, 15, 150]);
    });

    test('ignora acento, porque ninguém digita acento com pressa', () {
      expect(
          SongsProvider.hinosFiltrados(lista, 'harpa', 'coracao')
              .map((h) => h.numero),
          [7]);
      expect(
          SongsProvider.hinosFiltrados(lista, 'harpa', 'ABRAAO')
              .map((h) => h.numero),
          [150]);
    });

    test('acha por trecho da LETRA, que é como se lembra de hino', () {
      expect(
          SongsProvider.hinosFiltrados(lista, 'harpa', 'firme nas promessas')
              .map((h) => h.numero),
          [7]);
    });

    test('acha pelo número digitado no campo de busca', () {
      final r = SongsProvider.hinosFiltrados(lista, 'harpa', '15');
      expect(r.map((h) => h.numero).toList(), [15, 150]);
    });

    test('busca vazia mostra o hinário todo, não esconde tudo', () {
      expect(SongsProvider.hinosFiltrados(lista, 'harpa', '').length, 3);
      expect(SongsProvider.hinosFiltrados(lista, 'cantor', '').length, 1);
    });

    test('não mistura hinários', () {
      expect(
          SongsProvider.hinosFiltrados(lista, 'cantor', '')
              .map((h) => h.name)
              .toList(),
          ['Antífona']);
    });
  });

  group('o que vai e volta do banco', () {
    final h = hino('harpa', 15, 'HC 15 · Sou Grato');

    test('Firestore preserva hinário e número', () {
      final volta = SongModel.fromFirestore(h.toFirestore());
      expect(volta.hinario, 'harpa');
      expect(volta.numero, 15);
      expect(volta.ehHino, isTrue);
    });

    test('o aparelho preserva hinário e número', () {
      // `Timestamp` não vira JSON — por isso os dois caminhos existem, e por
      // isso os dois precisam de teste.
      final volta = SongModel.fromJson(h.toJson());
      expect(volta.hinario, 'harpa');
      expect(volta.numero, 15);
    });

    test('música cadastrada ANTES disto não vira hino', () {
      // Compatibilidade com os dados que já existem: documento sem os campos
      // é música comum, como sempre foi.
      final antiga = <String, dynamic>{
        'id': 'x',
        'name': 'Digno És',
        'artist': 'Hillsong',
        'lyrics': '',
        'originalKey': 'C',
        'createdAt': Timestamp.fromDate(DateTime(2026)),
      };
      final m = SongModel.fromFirestore(antiga);
      expect(m.hinario, '');
      expect(m.numero, isNull);
      expect(m.ehHino, isFalse);
    });

    test('número gravado como TEXTO no console ainda é lido', () {
      // Quem mexe no console digita "15", não 15. Perder o número aí faria o
      // hino desaparecer do teclado sem nada na tela.
      final m = SongModel.fromFirestore({
        'id': 'x',
        'name': 'HC 15',
        'artist': '',
        'lyrics': '',
        'originalKey': 'C',
        'createdAt': Timestamp.fromDate(DateTime(2026)),
        'hinario': 'harpa',
        'numero': '15',
      });
      expect(m.numero, 15);
    });

    test('número que é lixo vira nulo, não zero', () {
      final m = SongModel.fromFirestore({
        'id': 'x',
        'name': 'HC',
        'artist': '',
        'lyrics': '',
        'originalKey': 'C',
        'createdAt': Timestamp.fromDate(DateTime(2026)),
        'hinario': 'harpa',
        'numero': 'quinze',
      });
      expect(m.numero, isNull);
      expect(m.ehHino, isFalse);
    });

    test('copyWith não perde o hino ao mexer em outra coisa', () {
      final mexida = h.copyWith(originalKey: 'A');
      expect(mexida.hinario, 'harpa');
      expect(mexida.numero, 15);
    });
  });
}
