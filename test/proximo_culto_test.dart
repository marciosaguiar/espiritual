import 'package:flutter_test/flutter_test.dart';
import 'package:levitasync/data/models/scale_model.dart';
import 'package:levitasync/presentation/providers/scale_provider.dart';

/// O card "Próximo Culto" mostrou, num domingo às 20h53, o culto das 8h
/// daquele mesmo domingo. A conta comparava só a DATA e jogava a hora fora,
/// então qualquer culto do dia corrente contava como futuro até a meia-noite.
///
/// Estes testes fixam a regra combinada: vale o culto que ainda não começou,
/// e o que começou há menos de duas horas, porque quem abre o app no meio do
/// culto quer ver o culto de agora.
void main() {
  ScaleModel culto(DateTime quando, {bool canceled = false}) => ScaleModel(
        id: ScaleModel.idPara(quando),
        date: quando,
        serviceType: 'Culto',
        createdBy: 'lider',
        createdAt: DateTime(2026, 1, 1),
        canceled: canceled,
      );

  group('o domingo que deu errado', () {
    // 15/11/2026 foi domingo. Cultos de manhã e de noite, como na igreja.
    final manha = culto(DateTime(2026, 11, 15, 8));
    final noite = culto(DateTime(2026, 11, 15, 19));
    final quarta = culto(DateTime(2026, 11, 18, 8));

    test('às 20h53, o culto das 8h NÃO vale mais', () {
      final agora = DateTime(2026, 11, 15, 20, 53);
      expect(ScaleProvider.aindaVale(manha, agora), isFalse);
    });

    test('às 20h53, o das 19h ainda vale: está acontecendo', () {
      final agora = DateTime(2026, 11, 15, 20, 53);
      expect(ScaleProvider.aindaVale(noite, agora), isTrue);
    });

    test('às 21h30, nem o das 19h: o próximo é o de quarta', () {
      final agora = DateTime(2026, 11, 15, 21, 30);
      expect(ScaleProvider.aindaVale(manha, agora), isFalse);
      expect(ScaleProvider.aindaVale(noite, agora), isFalse);
      expect(ScaleProvider.aindaVale(quarta, agora), isTrue);
    });

    test('de manhã cedo, o culto das 8h ainda é o próximo', () {
      final agora = DateTime(2026, 11, 15, 6, 30);
      expect(ScaleProvider.aindaVale(manha, agora), isTrue);
    });
  });

  group('a virada do dia', () {
    test('23h59: o culto de 00h30 do dia seguinte vale', () {
      final agora = DateTime(2026, 11, 15, 23, 59);
      expect(ScaleProvider.aindaVale(culto(DateTime(2026, 11, 16, 0, 30)), agora),
          isTrue);
    });

    test('00h30: o culto das 23h de ONTEM ainda vale, começou há 1h30', () {
      // A conta antiga reprovava este caso pelo motivo contrário: a data de
      // ontem é anterior à de hoje, e o culto sumia no meio dele.
      final agora = DateTime(2026, 11, 16, 0, 30);
      expect(ScaleProvider.aindaVale(culto(DateTime(2026, 11, 15, 23)), agora),
          isTrue);
    });

    test('01h30: o culto das 23h de ontem já passou', () {
      final agora = DateTime(2026, 11, 16, 1, 30);
      expect(ScaleProvider.aindaVale(culto(DateTime(2026, 11, 15, 23)), agora),
          isFalse);
    });

    test('exatamente duas horas depois do início, já não vale', () {
      final inicio = DateTime(2026, 11, 15, 19);
      expect(ScaleProvider.aindaVale(culto(inicio),
          inicio.add(ScaleProvider.duracaoDoCulto)), isFalse);
      expect(
          ScaleProvider.aindaVale(
              culto(inicio),
              inicio.add(ScaleProvider.duracaoDoCulto -
                  const Duration(minutes: 1))),
          isTrue);
    });
  });

  group('culto cancelado', () {
    test('nunca é o próximo, mesmo no horário dele', () {
      final quando = DateTime(2026, 11, 15, 19);
      expect(ScaleProvider.aindaVale(culto(quando, canceled: true), quando),
          isFalse);
    });
  });

  group('o horário sobrevive ao banco', () {
    test('ida e volta mantém a hora, não só o dia', () {
      // Se a hora se perdesse na gravação, a conta certa não adiantaria.
      final quando = DateTime(2026, 11, 15, 19, 30);
      final lido = ScaleModel.fromFirestore(culto(quando).toFirestore());
      expect(lido.date, quando);
      expect(lido.date.hour, 19);
      expect(lido.date.minute, 30);
    });

    test('o id do culto também carrega a hora', () {
      expect(ScaleModel.idPara(DateTime(2026, 11, 15, 19)), '2026-11-15_1900');
      expect(ScaleModel.idPara(DateTime(2026, 11, 15, 8)), '2026-11-15_0800');
    });
  });
}
