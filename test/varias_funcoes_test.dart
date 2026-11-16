import 'package:flutter_test/flutter_test.dart';
import 'package:levitasync/data/models/user_model.dart';

/// Várias funções por pessoa.
///
/// No ministério é comum tocar duas coisas — cantar e fazer violão, baixo e
/// teclado. Com uma função só, o cadastro decidia errado a escala e o modo de
/// ver a música para sempre: quem canta num domingo e faz baixo no outro
/// abria a música sempre do mesmo jeito.
void main() {
  UserModel pessoa({
    UserInstrument? principal,
    List<UserInstrument>? funcoes,
  }) =>
      UserModel(
        id: 'u1',
        name: 'Ana',
        instrument: principal ?? UserInstrument.other,
        instruments: funcoes,
        createdAt: DateTime(2026, 11, 16),
      );

  group('a lista de funções', () {
    test('a primeira é a principal', () {
      final p = pessoa(
          funcoes: [UserInstrument.vocalist, UserInstrument.guitar]);
      expect(p.instrument, UserInstrument.vocalist);
      expect(p.temVariasFuncoes, isTrue);
      expect(p.fazFuncao(UserInstrument.guitar), isTrue);
      expect(p.fazFuncao(UserInstrument.drums), isFalse);
    });

    test('sem lista, vale a função única — cadastro antigo continua certo', () {
      final p = pessoa(principal: UserInstrument.keyboard);
      expect(p.instruments, [UserInstrument.keyboard]);
      expect(p.instrument, UserInstrument.keyboard);
      expect(p.temVariasFuncoes, isFalse);
    });

    test('lista vazia NÃO deixa a pessoa sem função', () {
      // `instrument` leria o primeiro item de uma lista vazia e derrubaria a
      // tela inteira. Documento torto no console não pode fazer isso.
      final p = pessoa(principal: UserInstrument.bass, funcoes: []);
      expect(p.instruments, [UserInstrument.bass]);
      expect(p.instrument, UserInstrument.bass);
    });

    test('função repetida entra uma vez só', () {
      final p = pessoa(funcoes: [
        UserInstrument.bass,
        UserInstrument.bass,
        UserInstrument.drums,
      ]);
      expect(p.instruments, [UserInstrument.bass, UserInstrument.drums]);
    });
  });

  group('trocar a principal', () {
    test('as outras funções FICAM', () {
      // Trocar a principal não é deixar de tocar o resto.
      final p = pessoa(funcoes: [
        UserInstrument.vocalist,
        UserInstrument.guitar,
        UserInstrument.bass,
      ]);
      final r = p.copyWith(instrument: UserInstrument.bass);
      expect(r.instrument, UserInstrument.bass);
      expect(r.instruments.length, 3);
      expect(r.fazFuncao(UserInstrument.vocalist), isTrue);
    });

    test('mexer em outra coisa não perde as funções', () {
      final p = pessoa(
          funcoes: [UserInstrument.vocalist, UserInstrument.guitar]);
      expect(p.copyWith(name: 'Ana Maria').instruments.length, 2);
    });
  });

  group('ida e volta no banco', () {
    test('a lista vai e volta, e a principal vai sozinha também', () {
      final p = pessoa(
          funcoes: [UserInstrument.keyboard, UserInstrument.vocalist]);
      final dados = p.toFirestore();
      // `instrument` sozinho é o que uma versão antiga do app lê.
      expect(dados['instrument'], 'keyboard');
      expect(dados['instruments'], ['keyboard', 'vocalist']);
      final lida = UserModel.fromFirestore(dados);
      expect(lida.instruments, p.instruments);
    });

    test('sessão guardada no aparelho também', () {
      final p = pessoa(funcoes: [UserInstrument.drums, UserInstrument.bass]);
      expect(UserModel.fromJson(p.toJson()).instruments, p.instruments);
    });

    test('cadastro antigo, sem o campo, usa a função única', () {
      final dados = pessoa(principal: UserInstrument.guitar).toFirestore()
        ..remove('instruments');
      expect(UserModel.fromFirestore(dados).instruments,
          [UserInstrument.guitar]);
    });

    test('lista estragada no banco não derruba a tela', () {
      for (final lixo in ['vocalist', 42, null, <String>[], {'a': 1}]) {
        final dados = pessoa(principal: UserInstrument.bass).toFirestore()
          ..['instruments'] = lixo;
        final lida = UserModel.fromFirestore(dados);
        expect(lida.instruments.isNotEmpty, isTrue, reason: '$lixo');
        expect(lida.instrument, UserInstrument.bass, reason: '$lixo');
      }
    });

    test('nome de função escrito errado vira "other", e não quebra', () {
      final dados = pessoa(principal: UserInstrument.bass).toFirestore()
        ..['instruments'] = ['vocalist', 'gaita'];
      final lida = UserModel.fromFirestore(dados);
      expect(lida.instruments, [UserInstrument.vocalist, UserInstrument.other]);
    });
  });

  group('o modo de ver a música', () {
    test('cantor lê letra; quem toca lê cifra', () {
      expect(UserModel.leituraDaFuncao(UserInstrument.vocalist),
          ModoLeitura.canto);
      for (final f in [
        UserInstrument.guitar,
        UserInstrument.bass,
        UserInstrument.drums,
        UserInstrument.keyboard,
        UserInstrument.other,
      ]) {
        expect(UserModel.leituraDaFuncao(f), ModoLeitura.toco, reason: '$f');
      }
    });

    test('a escolha do perfil ainda manda fora do culto', () {
      // Quem toca baixo mas prefere ler só a letra continua lendo a letra
      // quando abre a música pelo repertório.
      final p = pessoa(principal: UserInstrument.bass)
          .copyWith(leitura: ModoLeitura.canto);
      expect(p.canta, isTrue);
    });

    test('sem escolha, vale a função principal', () {
      expect(pessoa(principal: UserInstrument.vocalist).canta, isTrue);
      expect(pessoa(principal: UserInstrument.drums).canta, isFalse);
    });
  });
}
