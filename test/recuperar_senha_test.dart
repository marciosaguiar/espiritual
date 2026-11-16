import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:levitasync/data/models/user_model.dart';

/// Recuperar a senha num app em que ninguém tem e-mail.
///
/// O endereço com que o Firebase identifica cada conta nasce do nome
/// (`ana@levitas.app`) e esse domínio não é de ninguém. Então o caminho todo
/// se apoia em duas contas de uma linha cada — e as duas, erradas, falham em
/// silêncio: a primeira manda o link de recuperação para o vazio, a segunda
/// impede a pessoa de entrar.
void main() {
  group('nome ou e-mail, no mesmo campo', () {
    test('sem arroba é nome, e sai o endereço interno', () {
      expect(UserModel.emailParaEntrar('Ana Silva'), 'ana.silva@levitas.app');
      expect(UserModel.emailParaEntrar('  Márcio Aguiar  '),
          'marcio.aguiar@levitas.app');
    });

    test('com arroba é e-mail, e vai como está', () {
      expect(UserModel.emailParaEntrar('ana@gmail.com'), 'ana@gmail.com');
    });

    test('e-mail digitado com maiúsculas e espaços ainda entra', () {
      // O teclado do iPhone põe maiúscula na primeira letra sozinho, e o
      // Firebase diferencia: sem isto, metade das tentativas de entrar por
      // e-mail falharia com "senha incorreta" — o erro mais enganoso
      // possível, porque a senha estava certa.
      expect(UserModel.emailParaEntrar('  Ana@Gmail.Com '), 'ana@gmail.com');
    });

    test('nome com acento e símbolo continua virando endereço válido', () {
      expect(UserModel.emailParaEntrar('João 2'), 'joao.2@levitas.app');
    });
  });

  group('endereço interno não recebe e-mail', () {
    test('reconhece o domínio do app, em qualquer caixa', () {
      expect(UserModel.enderecoInterno('ana@levitas.app'), isTrue);
      expect(UserModel.enderecoInterno('  ANA@LEVITAS.APP '), isTrue);
    });

    test('e-mail de verdade não é confundido com o interno', () {
      expect(UserModel.enderecoInterno('ana@gmail.com'), isFalse);
      // O nome do app dentro do endereço não faz dele interno: o que importa
      // é o domínio, não a palavra aparecer no meio.
      expect(UserModel.enderecoInterno('levitas.app@gmail.com'), isFalse);
    });

    test('todo endereço derivado de nome é interno', () {
      for (final nome in ['Ana', 'João 2', 'Maria das Dores', '###']) {
        expect(UserModel.enderecoInterno(UserModel.emailForName(nome)), isTrue,
            reason: 'nome "$nome" gerou endereço que parece de verdade');
      }
    });
  });

  group('o sim/não no cadastro', () {
    UserModel ana({bool? recuperacao}) => UserModel(
          id: 'u1',
          name: 'Ana',
          createdAt: DateTime(2026, 11, 16),
          recuperacaoPorEmail: recuperacao ?? false,
        );

    test('cadastro antigo, sem o campo, conta como SEM e-mail', () {
      // Lado seguro: o líder vê "falta cadastrar" e pergunta de novo. Se a
      // falta valesse "tem", o aviso sumiria justamente para quem está
      // desprotegido — e ninguém descobriria antes de perder o acesso.
      final antigo = UserModel.fromFirestore({
        'id': 'u1',
        'name': 'Ana',
        'role': 'levita',
      });
      expect(antigo.recuperacaoPorEmail, isFalse);
    });

    test('só true conta; valor torto no console não protege ninguém', () {
      for (final valor in ['true', 1, 'sim', null, {}]) {
        final u = UserModel.fromFirestore({
          'id': 'u1',
          'name': 'Ana',
          'role': 'levita',
          'recuperacaoPorEmail': valor,
        });
        expect(u.recuperacaoPorEmail, isFalse,
            reason: 'valor $valor não deveria valer como "tem e-mail"');
      }
    });

    test('ida e volta no banco e no aparelho', () {
      for (final valor in [true, false]) {
        final u = ana(recuperacao: valor);
        expect(UserModel.fromFirestore(u.toFirestore()).recuperacaoPorEmail,
            valor);
        expect(UserModel.fromJson(u.toJson()).recuperacaoPorEmail, valor);
      }
    });

    test('false não é gravado, como o bot', () {
      // Campo só aparece quando é verdade: mantém o documento enxuto e deixa
      // claro no console que a ausência é o normal.
      expect(ana().toFirestore().containsKey('recuperacaoPorEmail'), isFalse);
      expect(
          ana(recuperacao: true).toFirestore()['recuperacaoPorEmail'], isTrue);
    });

    test('copyWith preserva e troca', () {
      expect(ana().copyWith(recuperacaoPorEmail: true).recuperacaoPorEmail,
          isTrue);
      expect(ana(recuperacao: true).copyWith(name: 'Ana M.')
          .recuperacaoPorEmail, isTrue);
    });
  });

  group('a conta reautentica com o endereço certo', () {
    test('trocar a senha usa o e-mail da conta, não o derivado do nome', () {
      // Esta entrega criaria um defeito exatamente em quem se protegeu: quem
      // cadastra e-mail passa a ter esse endereço na conta, e reautenticar
      // com o derivado do nome falharia — "A sua senha está incorreta" com a
      // senha certa. O teste varre o arquivo porque o conserto é uma linha
      // que não dá sintoma nenhum em quem não cadastrou e-mail.
      final fonte = File('lib/data/services/auth_service.dart')
          .readAsStringSync();
      final trechos = RegExp(r'EmailAuthProvider\.credential\(\s*\n\s*email: ([^,]+),')
          .allMatches(fonte)
          .map((m) => m.group(1)!.trim())
          .toList();
      expect(trechos, isNotEmpty, reason: 'nenhuma reautenticação encontrada');
      for (final t in trechos) {
        expect(t.startsWith('account.email'), isTrue,
            reason: 'reautenticação usando "$t" quebra quem cadastrou e-mail');
      }
    });
  });
}
