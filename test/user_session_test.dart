import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:levitasync/data/models/user_model.dart';

/// Guards the bug that made every login fail: the session used to be encoded
/// from the Firestore map, which carries a `Timestamp`. `jsonEncode` throws on
/// it, so `login()` always fell into its catch block and returned
/// "Erro inesperado" — and a stored session could never be read back.
void main() {
  final user = UserModel(
    id: 'u1',
    name: 'Márcio',
    passwordHash: 'nao-deve-vazar',
    role: UserRole.admin,
    instrument: UserInstrument.keyboard,
    favoriteSongs: const ['s1', 's2'],
    savedTones: const {'s1': 2},
    createdAt: DateTime(2026, 3, 14, 9, 30),
  );

  group('sessão local', () {
    test('a sessão pode ser convertida para JSON sem erro', () {
      expect(() => jsonEncode(user.toJson()), returnsNormally);
    });

    test('a senha nunca é gravada no aparelho', () {
      final json = jsonEncode(user.toJson());
      expect(json.contains('nao-deve-vazar'), isFalse);
      expect(user.toJson().containsKey('passwordHash'), isFalse);
    });

    test('ida e volta preserva os dados do usuário', () {
      final restored = UserModel.fromJson(
        Map<String, dynamic>.from(jsonDecode(jsonEncode(user.toJson())) as Map),
      );

      expect(restored.id, user.id);
      expect(restored.name, user.name);
      expect(restored.role, UserRole.admin);
      expect(restored.instrument, UserInstrument.keyboard);
      expect(restored.favoriteSongs, ['s1', 's2']);
      expect(restored.savedTones, {'s1': 2});
      expect(restored.createdAt, user.createdAt);
      expect(restored.isAdmin, isTrue);
    });

    test('sessão restaurada não carrega a senha', () {
      final restored = UserModel.fromJson(user.toJson());
      expect(restored.passwordHash, isEmpty);
    });
  });

  group('nome sem diferenciar maiúsculas', () {
    test('normaliza espaços e caixa', () {
      expect(UserModel.normalizeName('  Márcio  '), 'márcio');
      expect(UserModel.normalizeName('MARCIO'), 'marcio');
    });

    test('o documento do Firestore guarda o nome normalizado', () {
      expect(user.toFirestore()['nameLower'], 'márcio');
    });
  });

  group('leitura do Firestore', () {
    test('usuário sem passwordHash não quebra a leitura', () {
      final restored = UserModel.fromFirestore({
        'id': 'u2',
        'name': 'Ana',
        'role': 'levita',
        'instrument': 'vocalist',
      });

      expect(restored.name, 'Ana');
      expect(restored.passwordHash, isEmpty);
      expect(restored.isAdmin, isFalse);
    });
  });
}
