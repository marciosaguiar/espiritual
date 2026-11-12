import 'package:flutter_test/flutter_test.dart';
import 'package:levitasync/data/models/scale_model.dart';

/// Guards the two methods the home card depends on. They existed from the
/// start and were never called, which is why nobody was ever told they were
/// scheduled.
void main() {
  ScaleModel escala(List<ScaleLevita> levitas) => ScaleModel(
        id: 'c1',
        date: DateTime(2026, 11, 15, 9, 0),
        levitas: levitas,
        createdAt: DateTime(2026, 11, 1),
      );

  const ana = ScaleLevita(
      userId: 'u1', userName: 'Ana', instrument: 'vocalist', confirmed: true);
  const bruno = ScaleLevita(
      userId: 'u2', userName: 'Bruno', instrument: 'bass');

  group('estou escalado?', () {
    test('reconhece quem está na escala', () {
      final e = escala([ana, bruno]);
      expect(e.isUserInScale('u1'), isTrue);
      expect(e.isUserInScale('u2'), isTrue);
      expect(e.isUserInScale('u3'), isFalse);
    });

    test('escala vazia não escala ninguém', () {
      expect(escala([]).isUserInScale('u1'), isFalse);
    });
  });

  group('já confirmei?', () {
    test('separa quem confirmou de quem só está escalado', () {
      final e = escala([ana, bruno]);
      expect(e.hasUserConfirmed('u1'), isTrue);
      expect(e.hasUserConfirmed('u2'), isFalse);
    });

    test('quem não está na escala nunca conta como confirmado', () {
      expect(escala([ana]).hasUserConfirmed('u3'), isFalse);
    });

    test('contagem de confirmados', () {
      expect(escala([ana, bruno]).confirmedCount, 1);
      expect(escala([]).confirmedCount, 0);
    });
  });

  group('horário do culto', () {
    test('a data guarda a hora, não só o dia', () {
      final e = escala([]);
      final volta = ScaleModel.fromFirestore(e.toFirestore());
      expect(volta.date.hour, 9);
      expect(volta.date.minute, 0);
    });

    test('remarcar preserva o resto do culto', () {
      final e = escala([ana, bruno]);
      final remarcado = e.copyWith(date: DateTime(2026, 11, 15, 19, 30));
      expect(remarcado.date.hour, 19);
      expect(remarcado.levitas.length, 2);
      expect(remarcado.hasUserConfirmed('u1'), isTrue);
    });
  });
}
