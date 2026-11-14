import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:levitasync/data/models/scale_model.dart';
import 'package:levitasync/data/models/team_model.dart';
import 'package:levitasync/data/services/firestore_service.dart';

void main() {
  group('id determinístico do culto', () {
    test('monta data e hora no formato combinado', () {
      expect(ScaleModel.idPara(DateTime(2026, 11, 15, 8, 0)),
          '2026-11-15_0800');
      expect(ScaleModel.idPara(DateTime(2026, 11, 15, 19, 30)),
          '2026-11-15_1930');
      expect(ScaleModel.idPara(DateTime(2026, 1, 4, 0, 5)),
          '2026-01-04_0005');
    });

    test('a mesma data e hora sempre dá o mesmo id', () {
      // É isto que impede dois líderes de criarem o culto em duplicata:
      // ambos calculam o mesmo id e escrevem o mesmo documento.
      final a = ScaleModel.idPara(DateTime(2026, 11, 15, 8, 0));
      final b = ScaleModel.idPara(DateTime(2026, 11, 15, 8, 0, 59));
      expect(a, b);
    });

    test('horários diferentes no mesmo dia dão ids diferentes', () {
      final manha = ScaleModel.idPara(DateTime(2026, 11, 15, 8, 0));
      final noite = ScaleModel.idPara(DateTime(2026, 11, 15, 19, 0));
      expect(manha, isNot(equals(noite)));
    });
  });

  group('próxima data de um horário fixo', () {
    const domingo8 = ScheduleSlot(id: 'dom-0800', weekday: 7, hour: 8, minute: 0);
    const quarta1930 =
        ScheduleSlot(id: 'qua-1930', weekday: 3, hour: 19, minute: 30);

    test('a partir de uma segunda, acha o domingo seguinte', () {
      // 2026-11-16 é segunda-feira.
      final d = domingo8.proximaData(DateTime(2026, 11, 16, 10, 0));
      expect(d.weekday, DateTime.sunday);
      expect(d, DateTime(2026, 11, 22, 8, 0));
    });

    test('no próprio dia, devolve hoje com o horário do culto', () {
      // 2026-11-15 é domingo.
      final d = domingo8.proximaData(DateTime(2026, 11, 15, 6, 0));
      expect(d, DateTime(2026, 11, 15, 8, 0));
    });

    test('respeita os minutos', () {
      final d = quarta1930.proximaData(DateTime(2026, 11, 16, 0, 0));
      expect(d, DateTime(2026, 11, 18, 19, 30));
      expect(d.weekday, DateTime.wednesday);
    });

    test('quatro semanas rendem quatro datas por horário', () {
      final inicio = DateTime(2026, 11, 16);
      final limite = inicio.add(const Duration(days: 28));
      var quando = domingo8.proximaData(inicio);
      final datas = <DateTime>[];
      while (!quando.isAfter(limite)) {
        datas.add(quando);
        quando = quando.add(const Duration(days: 7));
      }
      expect(datas.length, 4);
      expect(datas.every((d) => d.weekday == DateTime.sunday), isTrue);
      expect(datas.map(ScaleModel.idPara).toSet().length, 4);
    });
  });

  group('agenda padrão da igreja', () {
    final padrao = FixedSchedule.padraoDaIgreja(
        equipeManha: 'tm', equipeNoite: 'tn');

    test('são os cinco cultos combinados', () {
      expect(padrao.length, 5);
      final resumo = padrao
          .map((s) => '${s.weekday}-${s.horaFormatada}')
          .toList();
      expect(resumo, [
        '3-08:00', // quarta manhã
        '3-19:30', // quarta noite
        '5-19:30', // sexta
        '7-08:00', // domingo manhã
        '7-19:00', // domingo noite
      ]);
    });

    test('manhã e noite recebem equipes diferentes', () {
      final manha = padrao.where((s) => s.hour < 12);
      final noite = padrao.where((s) => s.hour >= 12);
      expect(manha.every((s) => s.teamId == 'tm'), isTrue);
      expect(noite.every((s) => s.teamId == 'tn'), isTrue);
    });

    test('sem equipes informadas, os horários ficam sem equipe', () {
      expect(FixedSchedule.padraoDaIgreja().every((s) => s.teamId.isEmpty),
          isTrue);
    });

    test('cada horário tem id próprio', () {
      expect(padrao.map((s) => s.id).toSet().length, 5);
    });
  });

  group('culto da agenda x culto avulso', () {
    ScaleModel culto({String fromSlot = ''}) => ScaleModel(
          id: 'x',
          date: DateTime(2026, 11, 15, 8),
          createdAt: DateTime(2026),
          fromSlot: fromSlot,
        );

    test('reconhece quem nasceu da agenda fixa', () {
      expect(culto(fromSlot: 'dom-0800').daAgendaFixa, isTrue);
      expect(culto().daAgendaFixa, isFalse);
    });

    test('cancelado e editado à mão nascem falsos', () {
      final c = culto(fromSlot: 'dom-0800');
      expect(c.canceled, isFalse);
      expect(c.manuallyEdited, isFalse);
    });

    test('ida e volta pelo Firestore preserva os campos novos', () {
      final c = ScaleModel(
        id: '2026-11-15_0800',
        date: DateTime(2026, 11, 15, 8),
        createdAt: DateTime(2026),
        fromSlot: 'dom-0800',
        teamId: 'tm',
        manuallyEdited: true,
        canceled: true,
      );
      final volta = ScaleModel.fromFirestore(c.toFirestore());
      expect(volta.fromSlot, 'dom-0800');
      expect(volta.teamId, 'tm');
      expect(volta.manuallyEdited, isTrue);
      expect(volta.canceled, isTrue);
    });

    test('culto antigo, sem os campos novos, continua sendo lido', () {
      // Cultos gravados antes desta entrega não têm fromSlot, teamId,
      // manuallyEdited nem canceled; a leitura precisa tolerar a ausência.
      final volta = ScaleModel.fromFirestore({
        'id': 'antigo',
        'date': Timestamp.fromDate(DateTime(2026, 11, 15, 8)),
        'serviceType': 'Culto',
        'songs': <dynamic>[],
        'levitas': <dynamic>[],
      });
      expect(volta.daAgendaFixa, isFalse);
      expect(volta.canceled, isFalse);
      expect(volta.manuallyEdited, isFalse);
      expect(volta.teamId, isEmpty);
    });
  });

  group('equipe', () {
    final equipe = TeamModel(
      id: 't1',
      name: 'Equipe Manhã',
      members: const [
        TeamMember(userId: 'u1', instrument: 'vocalist'),
        TeamMember(userId: 'u2', instrument: 'bass'),
      ],
      updatedAt: DateTime(2026),
    );

    test('guarda só o id de cada pessoa, nunca o nome', () {
      final json = equipe.toFirestore();
      final membros = json['members'] as List;
      for (final m in membros) {
        expect((m as Map).containsKey('userName'), isFalse);
        expect(m.containsKey('userId'), isTrue);
      }
    });

    test('ida e volta preserva membros e instrumentos', () {
      final volta = TeamModel.fromFirestore(equipe.toFirestore());
      expect(volta.name, 'Equipe Manhã');
      expect(volta.members.length, 2);
      expect(volta.members.first.instrument, 'vocalist');
      expect(volta.hasMember('u2'), isTrue);
      expect(volta.hasMember('u9'), isFalse);
    });

    test('equipe vazia é reconhecida', () {
      expect(TeamModel(id: 't', name: 'x', updatedAt: DateTime(2026)).isEmpty,
          isTrue);
    });
  });

  group('ida e volta da agenda fixa', () {
    test('preserva dia, horário, nome e equipe', () {
      final agenda = FixedSchedule(
        slots: FixedSchedule.padraoDaIgreja(equipeManha: 'tm', equipeNoite: 'tn'),
        updatedAt: DateTime(2026),
      );
      final volta = FixedSchedule.fromFirestore(agenda.toFirestore());
      expect(volta.slots.length, 5);
      expect(volta.slots.first.weekday, 3);
      expect(volta.slots.first.hour, 8);
      expect(volta.slots.first.teamId, 'tm');
      expect(volta.slots.last.horaFormatada, '19:00');
    });
  });

  group('quais cultos faltam criar', () {
    // Segunda-feira, 16/11/2026, 10h.
    final segunda = DateTime(2026, 11, 16, 10, 0);
    final slots = FixedSchedule.padraoDaIgreja(
        equipeManha: 'tm', equipeNoite: 'tn');
    final equipes = {
      'tm': TeamModel(
        id: 'tm',
        name: 'Manhã',
        members: const [TeamMember(userId: 'u1', instrument: 'vocalist')],
        updatedAt: DateTime(2026),
      ),
      'tn': TeamModel(
        id: 'tn',
        name: 'Noite',
        members: const [
          TeamMember(userId: 'u2', instrument: 'bass'),
          TeamMember(userId: 'u3', instrument: 'drums'),
        ],
        updatedAt: DateTime(2026),
      ),
    };

    List<ScaleModel> faltando({
      List<ScaleModel> existentes = const [],
      int semanas = 4,
    }) =>
        FirestoreService.servicosFaltando(
          slots: slots,
          equipes: equipes,
          existentes: existentes,
          agora: segunda,
          semanas: semanas,
        );

    test('do zero, 4 semanas x 5 cultos = 20', () {
      expect(faltando().length, 20);
    });

    test('nenhum id se repete', () {
      final ids = faltando().map((s) => s.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('saem em ordem de data', () {
      final datas = faltando().map((s) => s.date).toList();
      for (var i = 1; i < datas.length; i++) {
        expect(datas[i].isAfter(datas[i - 1]), isTrue);
      }
    });

    test('todos no futuro, nenhum no passado', () {
      expect(faltando().every((s) => s.date.isAfter(segunda)), isTrue);
    });

    test('o que já existe não é proposto de novo', () {
      final todos = faltando();
      final metade = todos.take(10).toList();
      final resto = faltando(existentes: metade);
      expect(resto.length, 10);
      final idsMetade = metade.map((s) => s.id).toSet();
      expect(resto.any((s) => idsMetade.contains(s.id)), isFalse);
    });

    test('rodar de novo com tudo criado não propõe nada', () {
      expect(faltando(existentes: faltando()), isEmpty);
    });

    test('culto cancelado NÃO volta', () {
      // É o ponto mais importante: o id vem da data, então sem isto o
      // cancelamento seria desfeito na abertura seguinte.
      final todos = faltando();
      final cancelado = todos.first.copyWith(canceled: true);
      final resto = faltando(existentes: [cancelado, ...todos.skip(1)]);
      expect(resto, isEmpty);
    });

    test('a equipe padrão entra escalada e sem ninguém confirmado', () {
      final manha = faltando().firstWhere((s) => s.date.hour == 8);
      final noite = faltando().firstWhere((s) => s.date.hour == 19);
      expect(manha.levitas.length, 1);
      expect(noite.levitas.length, 2);
      expect(manha.teamId, 'tm');
      expect(noite.teamId, 'tn');
      expect([...manha.levitas, ...noite.levitas].every((l) => !l.confirmed),
          isTrue);
    });

    test('cada culto sabe de qual linha da agenda nasceu', () {
      for (final s in faltando()) {
        expect(s.fromSlot, isNotEmpty);
        expect(slots.any((slot) => slot.id == s.fromSlot), isTrue);
      }
      expect(faltando().every((s) => !s.manuallyEdited), isTrue);
      expect(faltando().every((s) => !s.canceled), isTrue);
    });

    test('horário fixo sem equipe gera culto sem ninguém', () {
      final semEquipe = FirestoreService.servicosFaltando(
        slots: const [
          ScheduleSlot(id: 'dom-0800', weekday: 7, hour: 8, minute: 0)
        ],
        equipes: equipes,
        existentes: const [],
        agora: segunda,
      );
      expect(semEquipe, isNotEmpty);
      expect(semEquipe.every((s) => s.levitas.isEmpty), isTrue);
    });

    test('sem agenda configurada, não cria nada', () {
      expect(
        FirestoreService.servicosFaltando(
            slots: const [], equipes: equipes, existentes: const [],
            agora: segunda),
        isEmpty,
      );
    });

    test('o culto de hoje que já passou não é criado', () {
      // Domingo 15h: o culto das 8h já passou, o das 19h ainda não.
      final domingoTarde = DateTime(2026, 11, 15, 15, 0);
      final hoje = FirestoreService.servicosFaltando(
        slots: slots,
        equipes: equipes,
        existentes: const [],
        agora: domingoTarde,
        semanas: 1,
      ).where((s) =>
          s.date.year == 2026 && s.date.month == 11 && s.date.day == 15);
      expect(hoje.length, 1);
      expect(hoje.first.date.hour, 19);
    });

    test('duas semanas rendem metade', () {
      expect(faltando(semanas: 2).length, 10);
    });
  });
}
