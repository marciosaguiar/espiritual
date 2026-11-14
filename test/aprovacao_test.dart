import 'package:flutter_test/flutter_test.dart';
import 'package:levitasync/data/models/user_model.dart';

/// A aprovação do líder depende de duas decisões pequenas que, erradas,
/// deixam a porta aberta sem ninguém perceber: o que um valor desconhecido
/// vira, e quem conta como aprovado. As regras do Firestore fazem a mesma
/// conta do outro lado, e os testes do emulador cobrem aquele lado.
void main() {
  group('função desconhecida', () {
    test('vira pendente, nunca levita', () {
      // Um documento meio gravado, um campo faltando ou um nome escrito
      // errado no console não podem resultar em acesso normal.
      for (final valor in ['', 'levit', 'LEVITA', 'chefe', 'null', 'Admin']) {
        expect(UserRoleExtension.fromString(valor), UserRole.pendente,
            reason: 'valor "$valor" deveria cair em pendente');
      }
    });

    test('os quatro valores conhecidos são lidos como são', () {
      for (final papel in UserRole.values) {
        expect(UserRoleExtension.fromString(papel.name), papel);
      }
    });
  });

  group('quem está aprovado', () {
    UserModel com(UserRole papel) =>
        UserModel(
          id: 'u',
          name: 'Fulano',
          email: 'f@levitas.app',
          role: papel,
          createdAt: DateTime(2026, 11, 14),
        );

    test('levita e líder entram; pendente e recusado não', () {
      expect(com(UserRole.levita).aprovado, isTrue);
      expect(com(UserRole.admin).aprovado, isTrue);
      expect(com(UserRole.pendente).aprovado, isFalse);
      expect(com(UserRole.recusado).aprovado, isFalse);
    });

    test('nenhuma função nova entra sozinha na lista de aprovados', () {
      // Se um dia alguém acrescentar um valor ao enum, este teste quebra e
      // obriga a decidir de que lado ele fica — aqui e nas regras.
      expect(UserRole.values.where((p) => com(p).aprovado).toSet(),
          {UserRole.levita, UserRole.admin});
    });

    test('só o líder é líder', () {
      expect(com(UserRole.admin).isAdmin, isTrue);
      expect(com(UserRole.levita).isAdmin, isFalse);
      expect(com(UserRole.pendente).isAdmin, isFalse);
    });
  });

  group('o que a tela mostra', () {
    test('nenhum rótulo é o nome técnico', () {
      for (final papel in UserRole.values) {
        expect(papel.label, isNot(equals(papel.name)));
        expect(papel.label, isNotEmpty);
      }
    });
  });

  group('ida e volta no banco', () {
    test('pendente sobrevive à gravação e à leitura', () {
      final novo = UserModel(
        id: 'u1',
        name: 'Bruno',
        email: 'bruno@levitas.app',
        role: UserRole.pendente,
        createdAt: DateTime(2026, 11, 14),
      );
      final lido = UserModel.fromFirestore(novo.toFirestore());
      expect(lido.role, UserRole.pendente);
      expect(lido.aprovado, isFalse);
    });

    test('cadastro sem o campo role é tratado como pendente', () {
      final dados = UserModel(
        id: 'u2',
        name: 'Sem Função',
        email: 's@levitas.app',
        role: UserRole.levita,
        createdAt: DateTime(2026, 11, 14),
      ).toFirestore()
        ..remove('role');

      expect(UserModel.fromFirestore(dados).aprovado, isFalse);
    });
  });
}
