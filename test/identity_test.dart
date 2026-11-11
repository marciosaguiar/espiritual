import 'package:flutter_test/flutter_test.dart';
import 'package:levitasync/core/utils/crypto_utils.dart';
import 'package:levitasync/data/models/user_model.dart';

void main() {
  group('nome -> e-mail interno', () {
    test('nome simples', () {
      expect(UserModel.emailForName('Marcio'), 'marcio@levitas.app');
    });

    test('espaço vira ponto', () {
      expect(UserModel.emailForName('Marcio Aguiar'),
          'marcio.aguiar@levitas.app');
    });

    test('acento é removido — quem cadastrou "Márcio" entra como "Marcio"', () {
      expect(UserModel.emailForName('Márcio'), UserModel.emailForName('Marcio'));
      expect(UserModel.emailForName('João Coração'),
          'joao.coracao@levitas.app');
      expect(UserModel.emailForName('Agnès'), 'agnes@levitas.app');
    });

    test('maiúsculas e espaços nas pontas não mudam nada', () {
      const esperado = 'ana.clara@levitas.app';
      for (final escrito in ['Ana Clara', '  ana clara  ', 'ANA CLARA', 'AnA  cLaRa']) {
        expect(UserModel.emailForName(escrito), esperado, reason: escrito);
      }
    });

    test('símbolos não viram endereço inválido', () {
      expect(UserModel.emailForName("Zé d'Ávila"), 'ze.d.avila@levitas.app');
      expect(UserModel.emailForName('Ana-Maria'), 'ana.maria@levitas.app');
      expect(UserModel.emailForName('Ju!!!'), 'ju@levitas.app');
      expect(UserModel.emailForName('Pedro 2'), 'pedro.2@levitas.app');
    });

    test('nome só de símbolos ainda gera endereço utilizável', () {
      expect(UserModel.emailForName('###'), 'levita@levitas.app');
      expect(UserModel.emailForName('   '), 'levita@levitas.app');
      expect(UserModel.emailForName('🎸'), 'levita@levitas.app');
    });

    test('nome longo não passa do limite do endereço', () {
      final email = UserModel.emailForName('a' * 200);
      final local = email.split('@').first;
      expect(local.length, lessThanOrEqualTo(48));
      expect(email.endsWith('@levitas.app'), isTrue);
    });

    test('o resultado é sempre um endereço válido', () {
      final re = RegExp(r'^[a-z0-9]([a-z0-9.]*[a-z0-9])?@levitas\.app$');
      for (final nome in [
        'Marcio', 'Márcio Aguiar', '  ...Ana...  ', 'Zé', '###', '🎵 Ju 🎵',
        'Maria   da   Silva', 'a' * 200, 'Ñuño', '123',
      ]) {
        expect(re.hasMatch(UserModel.emailForName(nome)), isTrue,
            reason: '$nome -> ${UserModel.emailForName(nome)}');
      }
    });

    test('derivedEmail usa o nome do próprio usuário', () {
      final u = UserModel(
        id: 'x',
        name: 'Márcio Aguiar',
        createdAt: DateTime.now(),
      );
      expect(u.derivedEmail, 'marcio.aguiar@levitas.app');
    });
  });

  group('generateId', () {
    test('não repete', () {
      final ids = List.generate(500, (_) => CryptoUtils.generateId());
      expect(ids.toSet().length, 500);
    });

    test('tem tamanho utilizável e sem "=" de preenchimento', () {
      final id = CryptoUtils.generateId();
      expect(id.length, greaterThanOrEqualTo(20));
      expect(id.contains('='), isFalse);
    });
  });
}
