import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:levitasync/data/models/scale_model.dart';
import 'package:levitasync/data/models/user_model.dart';
import 'package:levitasync/data/services/firestore_service.dart';

void main() {
  group('tirar a pessoa de uma lista', () {
    final equipe = [
      {'userId': 'a', 'instrument': 'bass'},
      {'userId': 'b', 'instrument': 'drums'},
    ];

    test('devolve a lista sem ela', () {
      final r = FirestoreService.semAPessoa(equipe, 'a');
      expect(r, isNotNull);
      expect(r!.length, 1);
      expect((r.first as Map)['userId'], 'b');
    });

    test('devolve null quando ela não estava lá — e aí não se grava nada', () {
      // Gravar uma lista idêntica custaria uma escrita por documento e
      // marcaria o culto como mexido sem nada ter mudado.
      expect(FirestoreService.semAPessoa(equipe, 'z'), isNull);
    });

    test('lista vazia ou campo ausente não quebram', () {
      expect(FirestoreService.semAPessoa(const [], 'a'), isNull);
      expect(FirestoreService.semAPessoa(null, 'a'), isNull);
      expect(FirestoreService.semAPessoa('nem é lista', 'a'), isNull);
    });

    test('tira a pessoa de todas as posições, não só da primeira', () {
      final r = FirestoreService.semAPessoa([
        {'userId': 'a'},
        {'userId': 'b'},
        {'userId': 'a'},
      ], 'a');
      expect(r!.length, 1);
    });
  });

  group('carimbo de saída no cadastro', () {
    final saiu = UserModel(
      id: 'u1',
      name: 'Bruno',
      email: 'bruno@levitas.app',
      role: UserRole.removido,
      createdAt: DateTime(2026, 1, 1),
      removedAt: DateTime(2026, 11, 14, 10, 30),
      removedBy: 'uid-lider',
    );

    test('vai e volta do Firestore', () {
      final lido = UserModel.fromFirestore(saiu.toFirestore());
      expect(lido.role, UserRole.removido);
      expect(lido.aprovado, isFalse);
      expect(lido.removedAt, DateTime(2026, 11, 14, 10, 30));
      expect(lido.removedBy, 'uid-lider');
    });

    test('vai e volta do aparelho sem Timestamp no caminho', () {
      // jsonEncode sobre um Timestamp lança, e isso já quebrou todo o login
      // uma vez — ver CLAUDE.md.
      final json = saiu.toJson();
      expect(json['removedAt'], isA<String>());
      final lido = UserModel.fromJson(json);
      expect(lido.removedAt, DateTime(2026, 11, 14, 10, 30));
      expect(lido.removedBy, 'uid-lider');
    });

    test('devolver o acesso apaga o carimbo', () {
      final devolvido =
          saiu.copyWith(role: UserRole.levita, limparRemocao: true);
      expect(devolvido.aprovado, isTrue);
      expect(devolvido.removedAt, isNull);
      expect(devolvido.removedBy, isNull);
    });

    test('copyWith comum não apaga o carimbo sem querer', () {
      expect(saiu.copyWith(name: 'Bruno Silva').removedBy, 'uid-lider');
    });

    test('cadastro sem carimbo lê como nulo', () {
      final dados = saiu.toFirestore()
        ..remove('removedAt')
        ..remove('removedBy');
      final lido = UserModel.fromFirestore(dados);
      expect(lido.removedAt, isNull);
      expect(lido.removedBy, isNull);
    });
  });

  group('o estado antigo "recusado"', () {
    test('é lido como removido, sem precisar migrar documento', () {
      expect(UserRoleExtension.fromString('recusado'), UserRole.removido);
    });

    test('e não volta a ser gravado', () {
      expect(UserRole.values.map((e) => e.name), isNot(contains('recusado')));
    });
  });

  group('aviso de quem faltou no culto', () {
    test('vai e volta do Firestore', () {
      final c = ScaleModel(
        id: 'c1',
        date: DateTime(2026, 11, 15, 9),
        serviceType: 'Culto',
        createdBy: 'lider',
        createdAt: DateTime(2026, 11, 1),
        faltando: const ['Bruno'],
      );
      final lido = ScaleModel.fromFirestore(c.toFirestore());
      expect(lido.faltando, ['Bruno']);
    });

    test('culto antigo, sem o campo, não tem aviso nenhum', () {
      final dados = ScaleModel(
        id: 'c2',
        date: DateTime(2026, 11, 15, 9),
        serviceType: 'Culto',
        createdBy: 'lider',
        createdAt: DateTime(2026, 11, 1),
      ).toFirestore()
        ..remove('faltando');
      expect(ScaleModel.fromFirestore(dados).faltando, isEmpty);
    });
  });
}
