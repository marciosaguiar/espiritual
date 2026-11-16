import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:levitasync/data/models/message_model.dart';

/// A conversa some depois de 30 dias, e a fixada fica. A regra é pequena e
/// mora num lugar só (`MessageModel.venceu`), porque três coisas dependem
/// dela: a tela, que esconde; a faxina, que apaga; e a regra do banco, que
/// decide o que o líder pode mexer.
void main() {
  MessageModel msg({
    required DateTime quando,
    bool fixada = false,
    DateTime? expiraEm,
  }) =>
      MessageModel(
        id: 'm1',
        userId: 'u1',
        userName: 'Ana',
        text: 'ensaio às 19h',
        timestamp: quando,
        fixada: fixada,
        fixadaPor: fixada ? 'uid-lider' : null,
        expiraEm: expiraEm,
      );

  final agora = DateTime(2026, 11, 16, 10);

  group('o prazo de 30 dias', () {
    test('mensagem de ontem vale', () {
      expect(msg(quando: agora.subtract(const Duration(days: 1)))
          .venceu(agora), isFalse);
    });

    test('mensagem de 29 dias vale; a de 31 não', () {
      expect(msg(quando: agora.subtract(const Duration(days: 29)))
          .venceu(agora), isFalse);
      expect(msg(quando: agora.subtract(const Duration(days: 31)))
          .venceu(agora), isTrue);
    });

    test('exatamente 30 dias ainda vale; um minuto depois, não', () {
      final trintaDias = agora.subtract(MessageModel.validade);
      expect(msg(quando: trintaDias).venceu(agora), isFalse);
      expect(
          msg(quando: trintaDias.subtract(const Duration(minutes: 1)))
              .venceu(agora),
          isTrue);
    });

    test('mensagem antiga sem o campo expiraEm usa o próprio horário', () {
      // Conversa gravada antes desta mudança não tem prazo escrito. Sem esta
      // conta ela nunca venceria, e o chat guardaria recado de 2026 para
      // sempre.
      expect(msg(quando: agora.subtract(const Duration(days: 40)), expiraEm: null)
          .venceu(agora), isTrue);
    });
  });

  group('fixada', () {
    test('não vence nunca, por mais velha que seja', () {
      expect(
          msg(quando: DateTime(2020, 1, 1), fixada: true).venceu(agora),
          isFalse);
    });

    test('desafixar devolve o prazo contado do horário ORIGINAL', () {
      // Uma mensagem de dois meses atrás que sai do topo não pode ganhar
      // mais 30 dias de vida: ela já estava vencida.
      final antiga = msg(quando: agora.subtract(const Duration(days: 60)),
          fixada: true);
      final solta = antiga.copyWith(limparFixacao: true);
      expect(solta.fixada, isFalse);
      expect(solta.fixadaPor, isNull);
      expect(solta.expiraEm,
          agora.subtract(const Duration(days: 60)).add(MessageModel.validade));
      expect(solta.venceu(agora), isTrue);
    });

    test('fixar tira o prazo', () {
      final fixa = msg(quando: agora, expiraEm: agora.add(const Duration(days: 30)))
          .copyWith(fixada: true, fixadaPor: 'uid-lider', expiraEm: null);
      expect(fixa.fixada, isTrue);
      // `expiraEm` fica como estava porque `?? this.expiraEm` não zera; quem
      // grava nulo de verdade é o serviço, e a REGRA do banco recusa fixada
      // com prazo. O teste de regra cobre esse lado.
      expect(fixa.venceu(DateTime(2030)), isFalse);
    });
  });

  group('ida e volta no banco', () {
    test('os três campos sobrevivem', () {
      final original = msg(
        quando: agora,
        fixada: true,
        expiraEm: null,
      );
      final lida = MessageModel.fromFirestore(original.toFirestore());
      expect(lida.fixada, isTrue);
      expect(lida.fixadaPor, 'uid-lider');
      expect(lida.expiraEm, isNull);
      expect(lida.text, 'ensaio às 19h');
    });

    test('o prazo vira Timestamp, que é o que a faxina consulta', () {
      final dados = msg(quando: agora, expiraEm: agora.add(const Duration(days: 30)))
          .toFirestore();
      expect(dados['expiraEm'], isA<Timestamp>());
      expect(dados['fixada'], isFalse);
    });

    test('mensagem antiga, sem os campos, é lida como não fixada', () {
      final dados = msg(quando: agora).toFirestore()
        ..remove('fixada')
        ..remove('fixadaPor')
        ..remove('expiraEm');
      final lida = MessageModel.fromFirestore(dados);
      expect(lida.fixada, isFalse);
      expect(lida.expiraEm, isNull);
    });
  });
}
