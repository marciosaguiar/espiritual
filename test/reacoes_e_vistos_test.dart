import 'package:flutter_test/flutter_test.dart';
import 'package:levitasync/data/models/leitura_do_chat.dart';
import 'package:levitasync/data/models/message_model.dart';
import 'package:levitasync/data/models/user_model.dart';

void main() {
  final quando = DateTime(2026, 11, 16, 19, 30);

  MessageModel msg({
    String de = 'u-marcio',
    Map<String, String> reacoes = const {},
    DateTime? em,
  }) =>
      MessageModel(
        id: 'm1',
        userId: de,
        userName: 'Marcio',
        text: 'quem leva o cabo?',
        timestamp: em ?? quando,
        expiraEm: (em ?? quando).add(MessageModel.validade),
        reacoes: reacoes,
      );

  UserModel pessoa(String id, String nome,
          {bool bot = false, UserRole role = UserRole.levita}) =>
      UserModel(
          id: id,
          name: nome,
          role: role,
          bot: bot,
          createdAt: DateTime(2026, 1, 1));

  group('reações', () {
    test('a contagem agrupa por emoji', () {
      final m = msg(reacoes: {
        'u-ana': '🙏',
        'u-joao': '🙏',
        'u-pedro': '👍',
      });
      expect(m.contagemDeReacoes, [
        (emoji: '👍', quantas: 1),
        (emoji: '🙏', quantas: 2),
      ]);
    });

    test('a ordem é SEMPRE a da lista oficial', () {
      // Contagem que muda de lugar a cada reação faz a pessoa tocar no emoji
      // errado — é por isso que a ordem não é por quantidade.
      final m = msg(reacoes: {'a': '😂', 'b': '👍', 'c': '❤️'});
      expect(m.contagemDeReacoes.map((r) => r.emoji).toList(),
          ['👍', '❤️', '😂']);
    });

    test('uma reação por pessoa: reagir de novo troca, não soma', () {
      final m = msg(reacoes: {'u-ana': '🙏'});
      final trocada = m.copyWith(reacoes: {'u-ana': '🔥'});
      expect(trocada.contagemDeReacoes, [(emoji: '🔥', quantas: 1)]);
      expect(trocada.minhaReacao('u-ana'), '🔥');
    });

    test('minha reação, e a falta dela', () {
      final m = msg(reacoes: {'u-ana': '❤️'});
      expect(m.minhaReacao('u-ana'), '❤️');
      expect(m.minhaReacao('u-joao'), isNull);
      expect(msg().temReacoes, isFalse);
    });

    test('emoji fora da lista NÃO desenha na bolha de todo mundo', () {
      // A regra do banco já recusa, mas documento mexido no console, ou
      // gravado antes dela, não pode virar lixo na tela.
      final lida = MessageModel.fromFirestore(
          msg().toFirestore()..['reacoes'] = {'u-ana': '🤡', 'u-joao': '👍'});
      expect(lida.reacoes, {'u-joao': '👍'});
      expect(lida.contagemDeReacoes, [(emoji: '👍', quantas: 1)]);
    });

    test('mapa de reações estragado não derruba a tela', () {
      for (final lixo in ['👍', 42, null, <String>[], {'u': 7}]) {
        final lida = MessageModel.fromFirestore(
            msg().toFirestore()..['reacoes'] = lixo);
        expect(lida.reacoes, isEmpty, reason: '$lixo');
      }
    });

    test('mensagem sem o campo (antiga) lê como sem reações', () {
      final dados = msg().toFirestore();
      expect(dados.containsKey('reacoes'), isFalse,
          reason: 'mensagem simples não ganha campo novo');
      expect(MessageModel.fromFirestore(dados).reacoes, isEmpty);
    });

    test('as reações sobrevivem ao fixar e ao desafixar', () {
      final m = msg(reacoes: {'u-ana': '🙏'});
      expect(m.copyWith(fixada: true, expiraEm: null).reacoes.length, 1);
      expect(m.copyWith(limparFixacao: true).reacoes.length, 1);
    });
  });

  group('responder citando', () {
    test('o pedaço citado é copiado, e sobrevive ao banco', () {
      final m = MessageModel(
        id: 'm2',
        userId: 'u-ana',
        userName: 'Ana',
        text: 'eu levo',
        timestamp: quando,
        respondeA: 'm1',
        respondeANome: 'Marcio',
        respondeATexto: 'quem leva o cabo?',
      );
      expect(m.temCitacao, isTrue);
      final lida = MessageModel.fromFirestore(m.toFirestore());
      expect(lida.respondeA, 'm1');
      expect(lida.respondeANome, 'Marcio');
      expect(lida.respondeATexto, 'quem leva o cabo?');
    });

    test('mensagem comum não tem citação', () {
      expect(msg().temCitacao, isFalse);
      expect(msg().toFirestore().containsKey('respondeA'), isFalse);
    });
  });

  group('menções', () {
    test('a lista de uid vai e volta', () {
      final m = MessageModel(
        id: 'm3',
        userId: 'u-ana',
        userName: 'Ana',
        text: '@Marcio consegue levar?',
        timestamp: quando,
        mencoes: const ['u-marcio'],
      );
      expect(m.mencionou('u-marcio'), isTrue);
      expect(m.mencionou('u-joao'), isFalse);
      expect(MessageModel.fromFirestore(m.toFirestore()).mencoes,
          ['u-marcio']);
    });

    test('lista estragada no banco não derruba a tela', () {
      final lida = MessageModel.fromFirestore(
          msg().toFirestore()..['mencoes'] = 'u-marcio');
      expect(lida.mencoes, isEmpty);
    });
  });

  group('visto por', () {
    final ministerio = [
      pessoa('u-marcio', 'Marcio', role: UserRole.admin),
      pessoa('u-ana', 'Ana'),
      pessoa('u-joao', 'João'),
    ];

    LeituraDoChat leu(String id, String nome, Duration depois) =>
        LeituraDoChat(
            userId: id, userName: nome, lidoAte: quando.add(depois));

    test('quem leu depois da mensagem viu; quem leu antes, não', () {
      final r = quemViu(
        mensagem: msg(),
        leituras: [
          leu('u-ana', 'Ana', const Duration(minutes: 1)),
          leu('u-joao', 'João', const Duration(minutes: -5)),
        ],
        aprovados: ministerio,
      );
      expect(r.viram.map((v) => v.userName).toList(), ['Ana']);
      expect(r.naoViram, ['João']);
    });

    test('o autor não entra na conta', () {
      // Ele obviamente viu o que escreveu; aparecer na lista confunde.
      final r = quemViu(
        mensagem: msg(de: 'u-marcio'),
        leituras: [leu('u-ana', 'Ana', const Duration(minutes: 1))],
        aprovados: ministerio,
      );
      expect(r.viram.length + r.naoViram.length, 2);
      expect(r.viram.any((v) => v.userId == 'u-marcio'), isFalse);
      expect(r.naoViram.contains('Marcio'), isFalse);
    });

    test('robô NÃO entra: ele nunca abre o chat', () {
      // Com o robô na conta, os dois tiques azuis seriam impossíveis para
      // sempre — e ninguém entenderia por quê.
      final comRobo = [...ministerio, pessoa('u-faxina', 'Faxina', bot: true)];
      final r = quemViu(
        mensagem: msg(),
        leituras: [
          leu('u-ana', 'Ana', const Duration(minutes: 1)),
          leu('u-joao', 'João', const Duration(minutes: 1)),
        ],
        aprovados: comRobo,
      );
      expect(r.naoViram, isEmpty);
      expect(
          vistaPorTodos(
              mensagem: msg(),
              leituras: [
                leu('u-ana', 'Ana', const Duration(minutes: 1)),
                leu('u-joao', 'João', const Duration(minutes: 1)),
              ],
              aprovados: comRobo),
          isTrue);
    });

    test('quem nunca abriu o chat conta como não viu', () {
      final r = quemViu(
          mensagem: msg(), leituras: const [], aprovados: ministerio);
      expect(r.viram, isEmpty);
      expect(r.naoViram, ['Ana', 'João']);
    });

    test('ler no MESMO instante da mensagem conta como visto', () {
      final r = quemViu(
        mensagem: msg(),
        leituras: [
          leu('u-ana', 'Ana', Duration.zero),
          leu('u-joao', 'João', Duration.zero),
        ],
        aprovados: ministerio,
      );
      expect(r.naoViram, isEmpty);
    });

    test('os dois tiques azuis só com TODOS', () {
      final umSo = [leu('u-ana', 'Ana', const Duration(minutes: 1))];
      expect(
          vistaPorTodos(
              mensagem: msg(), leituras: umSo, aprovados: ministerio),
          isFalse);
      expect(
          vistaPorTodos(
            mensagem: msg(),
            leituras: [
              ...umSo,
              leu('u-joao', 'João', const Duration(minutes: 2))
            ],
            aprovados: ministerio,
          ),
          isTrue);
    });

    test('ministério de uma pessoa só NÃO acende os dois tiques', () {
      // Não há ninguém para ver: dois tiques azuis ali significariam "todo
      // mundo viu" quando não houve ninguém.
      expect(
          vistaPorTodos(
            mensagem: msg(),
            leituras: const [],
            aprovados: [pessoa('u-marcio', 'Marcio', role: UserRole.admin)],
          ),
          isFalse);
    });

    test('o nome vem do cadastro, não do marcador de leitura', () {
      // Quem mudou de nome aparece com o atual.
      final r = quemViu(
        mensagem: msg(),
        leituras: [leu('u-ana', 'Ana Antiga', const Duration(minutes: 1))],
        aprovados: ministerio,
      );
      expect(r.viram.first.userName, 'Ana');
    });

    test('marcador sem o carimbo do servidor conta como não lido', () {
      // Melhor "ainda não viu" por um instante que dois tiques azuis para
      // quem não viu nada.
      final lida = LeituraDoChat.fromFirestore(
          {'userId': 'u-ana', 'userName': 'Ana'});
      // `toUtc()`: a data zero é 1/1/1970 em UTC, mas em Brasília (UTC-3) é
      // 31/12/1969 às 21h. Sem isto o teste passava no GitHub e no contêiner,
      // que são UTC, e REPROVAVA no Mac do dono — e o `publicar.sh`, que roda
      // os testes antes de enviar, parava por causa de um teste e não de um
      // defeito.
      expect(lida.lidoAte.toUtc().year, 1970);
      expect(
          quemViu(
              mensagem: msg(),
              leituras: [lida],
              aprovados: ministerio).naoViram,
          contains('Ana'));
    });
  });
}
