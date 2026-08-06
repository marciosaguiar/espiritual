import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:levitasync/core/utils/crypto_utils.dart';

void main() {
  group('senha', () {
    test('aceita a senha correta', () {
      final hash = CryptoUtils.hashPassword('vamosLouvar123');
      expect(CryptoUtils.verifyPassword('vamosLouvar123', hash), isTrue);
    });

    test('recusa a senha errada', () {
      final hash = CryptoUtils.hashPassword('vamosLouvar123');
      expect(CryptoUtils.verifyPassword('vamosLouvar124', hash), isFalse);
      expect(CryptoUtils.verifyPassword('', hash), isFalse);
    });

    test('a mesma senha gera hashes diferentes (sal aleatório)', () {
      final a = CryptoUtils.hashPassword('mesmaSenha');
      final b = CryptoUtils.hashPassword('mesmaSenha');
      expect(a, isNot(equals(b)));
      // ...e ambos continuam validando.
      expect(CryptoUtils.verifyPassword('mesmaSenha', a), isTrue);
      expect(CryptoUtils.verifyPassword('mesmaSenha', b), isTrue);
    });

    test('o hash guardado não contém a senha', () {
      final hash = CryptoUtils.hashPassword('minhaSenhaSecreta');
      expect(hash.contains('minhaSenhaSecreta'), isFalse);
      expect(hash.startsWith('pbkdf2\$'), isTrue);
    });

    test('acentos e emoji funcionam', () {
      final hash = CryptoUtils.hashPassword('coração🎵');
      expect(CryptoUtils.verifyPassword('coração🎵', hash), isTrue);
      expect(CryptoUtils.verifyPassword('coracao🎵', hash), isFalse);
    });
  });

  group('contas antigas (SHA-256 sem sal)', () {
    // Formato usado antes: hex do SHA-256 puro.
    String legado(String senha) =>
        sha256.convert(utf8.encode(senha)).toString();

    test('quem já tinha conta continua entrando', () {
      expect(
        CryptoUtils.verifyPassword('senhaAntiga', legado('senhaAntiga')),
        isTrue,
      );
      expect(
        CryptoUtils.verifyPassword('outra', legado('senhaAntiga')),
        isFalse,
      );
    });

    test('hash antigo é marcado para atualização', () {
      expect(CryptoUtils.needsUpgrade(legado('senhaAntiga')), isTrue);
    });

    test('hash novo não precisa de atualização', () {
      expect(CryptoUtils.needsUpgrade(CryptoUtils.hashPassword('x')), isFalse);
    });

    test('hash com custo menor é marcado para atualização', () {
      expect(CryptoUtils.needsUpgrade('pbkdf2\$1000\$c2FsdA==\$aGFzaA=='), isTrue);
    });
  });

  group('hash corrompido', () {
    test('não derruba o app, apenas recusa', () {
      for (final ruim in [
        '',
        'pbkdf2\$',
        'pbkdf2\$abc\$def\$ghi',
        'pbkdf2\$60000\$naoEhBase64!!\$xxx',
        'pbkdf2\$60000\$c2FsdA==',
      ]) {
        expect(CryptoUtils.verifyPassword('qualquer', ruim), isFalse,
            reason: 'hash: $ruim');
      }
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
