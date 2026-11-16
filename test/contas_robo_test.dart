import 'package:flutter_test/flutter_test.dart';
import 'package:levitasync/data/models/user_model.dart';

/// Contas de robô: a faxina do chat e o servidor dos avisos.
///
/// Elas existem porque este projeto não usa chave de administrador — os dois
/// robôs entram como líderes comuns, com e-mail e senha. O preço era
/// aparecerem como gente: na lista de Membros, na contagem, nas equipes e nas
/// escalas. E, o pior, contarem na proteção do último líder: dava para
/// remover a última pessoa de verdade porque o robô "ainda era líder".
void main() {
  UserModel conta({bool bot = false, UserRole role = UserRole.levita}) =>
      UserModel(
        id: 'u1',
        name: bot ? 'Faxina' : 'Ana',
        role: role,
        createdAt: DateTime(2026, 11, 16),
        bot: bot,
      );

  group('o campo bot', () {
    test('nasce falso: cadastro de gente não precisa dizer nada', () {
      expect(conta().bot, isFalse);
    });

    test('só vai para o banco quando é verdade', () {
      // Cadastro de gente não ganha campo novo, e a regra do banco só olha o
      // que mudou.
      expect(conta().toFirestore().containsKey('bot'), isFalse);
      expect(conta(bot: true).toFirestore()['bot'], true);
    });

    test('sobrevive à ida e volta do banco', () {
      final lido = UserModel.fromFirestore(conta(bot: true).toFirestore());
      expect(lido.bot, isTrue);
    });

    test('sobrevive à sessão guardada no aparelho', () {
      final lido = UserModel.fromJson(conta(bot: true).toJson());
      expect(lido.bot, isTrue);
    });

    test('só `true` é robô — qualquer outra coisa é gente', () {
      // Um valor estranho escrito à mão no console não pode esconder uma
      // pessoa de verdade das escalas.
      for (final estranho in ['true', 'sim', 1, null, 'bot', {}]) {
        final dados = conta().toFirestore()..['bot'] = estranho;
        expect(UserModel.fromFirestore(dados).bot, isFalse,
            reason: 'bot: $estranho');
      }
    });

    test('copyWith marca e desmarca', () {
      expect(conta().copyWith(bot: true).bot, isTrue);
      expect(conta(bot: true).copyWith(bot: false).bot, isFalse);
      // E não perde a marca quando se mexe em outra coisa.
      expect(conta(bot: true).copyWith(name: 'Faxina do chat').bot, isTrue);
    });
  });

  group('quem entra nas listas', () {
    final pessoas = [
      conta(role: UserRole.admin),
      conta(),
      conta(bot: true, role: UserRole.admin),
      conta(bot: true),
      conta(role: UserRole.pendente),
      conta(role: UserRole.removido),
    ];

    test('escalável é quem é aprovado e NÃO é robô', () {
      // Mesma conta que `AuthService.watchEscalaveis` faz.
      final escalaveis = pessoas.where((u) => u.aprovado && !u.bot).toList();
      expect(escalaveis.length, 2);
      expect(escalaveis.every((u) => !u.bot), isTrue);
    });

    test('a contagem de líderes de verdade não inclui robô', () {
      // É a conta que segura o "o ministério precisa de pelo menos um líder".
      // Com o robô dentro, dava para remover a última pessoa de verdade e o
      // ministério ficava sem ninguém que aprovasse cadastro.
      final lideres =
          pessoas.where((u) => u.isAdmin && !u.bot).length;
      expect(lideres, 1);
    });

    test('robô continua sendo aprovado — ele precisa ler o banco', () {
      // Esconder o robô é coisa da TELA. Ele é líder no banco de propósito:
      // é assim que a faxina apaga mensagem vencida e o servidor dos avisos
      // lê as inscrições, sem chave de administrador.
      expect(conta(bot: true, role: UserRole.admin).aprovado, isTrue);
      expect(conta(bot: true, role: UserRole.admin).isAdmin, isTrue);
    });
  });
}
