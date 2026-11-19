// Dois cultos no mesmo dia (domingo de manhã e de noite): ao tocar no dia do
// calendário, a Escala mostrava SÓ UM.
//
// A causa era uma conta que devolvia "o culto do dia" — `firstWhere` — numa
// igreja em que o domingo tem dois, e a quarta também. O culto da noite
// existia, aparecia na lista de próximos cultos e tinha o seu ponto no
// calendário, mas era impossível de abrir pelo dia.
//
// TODO o texto é inventado.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:levitasync/data/models/scale_model.dart';
import 'package:levitasync/data/models/user_model.dart';
import 'package:levitasync/presentation/providers/auth_provider.dart';
import 'package:levitasync/presentation/providers/scale_provider.dart';
import 'package:levitasync/presentation/screens/scale/scale_screen.dart';

ScaleModel _culto(DateTime quando, {bool canceled = false}) => ScaleModel(
      id: ScaleModel.idPara(quando),
      date: quando,
      serviceType: 'Culto',
      createdBy: 'lider',
      createdAt: DateTime(2026, 1, 1),
      canceled: canceled,
    );

class _Auth extends AuthProvider {
  final bool lider;
  _Auth({required this.lider});

  @override
  bool get isAdmin => lider;

  @override
  UserModel? get user => UserModel(
        id: 'uid-teste',
        name: 'Teste',
        role: lider ? UserRole.admin : UserRole.levita,
        createdAt: DateTime(2026),
      );
}

void main() {
  group('a conta: os cultos de um dia', () {
    // 15/11/2026 foi domingo.
    final manha = _culto(DateTime(2026, 11, 15, 8));
    final noite = _culto(DateTime(2026, 11, 15, 19));
    final quarta = _culto(DateTime(2026, 11, 18, 8));

    test('domingo com dois cultos: os DOIS aparecem', () {
      final r = ScaleProvider.cultosDoDia(
          [manha, noite, quarta], DateTime(2026, 11, 15));
      expect(r.map((c) => c.id), [manha.id, noite.id]);
    });

    test('em ordem de hora, mesmo com a lista embaralhada', () {
      final r = ScaleProvider.cultosDoDia(
          [quarta, noite, manha], DateTime(2026, 11, 15));
      expect(r.map((c) => c.date.hour), [8, 19]);
    });

    test('a hora do dia tocado não importa: o toque do calendário vem às 12h', () {
      final r = ScaleProvider.cultosDoDia(
          [manha, noite], DateTime(2026, 11, 15, 12));
      expect(r.length, 2);
    });

    test('três no mesmo dia (ensaio, manhã e noite) também', () {
      final ensaio = _culto(DateTime(2026, 11, 15, 16, 30));
      final r = ScaleProvider.cultosDoDia(
          [noite, ensaio, manha], DateTime(2026, 11, 15));
      expect(r.map((c) => c.date.hour), [8, 16, 19]);
    });

    test('dia sem culto: lista vazia, não erro', () {
      expect(ScaleProvider.cultosDoDia([manha, noite], DateTime(2026, 11, 17)),
          isEmpty);
      expect(ScaleProvider.cultosDoDia(const [], DateTime(2026, 11, 15)),
          isEmpty);
    });

    test('o culto da meia-noite vizinha não vaza para o dia ao lado', () {
      final tarde = _culto(DateTime(2026, 11, 14, 23, 30));
      final cedo = _culto(DateTime(2026, 11, 16, 0, 30));
      final r = ScaleProvider.cultosDoDia(
          [tarde, manha, noite, cedo], DateTime(2026, 11, 15));
      expect(r.map((c) => c.id), [manha.id, noite.id]);
    });

    test('culto cancelado continua à vista: ele aparece riscado, com a marca',
        () {
      final cancelado = _culto(DateTime(2026, 11, 15, 19), canceled: true);
      final r =
          ScaleProvider.cultosDoDia([manha, cancelado], DateTime(2026, 11, 15));
      expect(r.length, 2);
      expect(r.last.canceled, isTrue);
    });
  });

  group('a conta: quantos cultos em cada dia do mês', () {
    test('o ponto do calendário sabe contar: dois no domingo, um na quarta', () {
      final todos = [
        _culto(DateTime(2026, 11, 15, 8)),
        _culto(DateTime(2026, 11, 15, 19)),
        _culto(DateTime(2026, 11, 18, 8)),
        _culto(DateTime(2026, 12, 2, 8)), // outro mês
      ];
      final r = ScaleProvider.cultosPorDia(todos, 2026, 11);
      expect(r[DateTime(2026, 11, 15)], 2);
      expect(r[DateTime(2026, 11, 18)], 1);
      expect(r.containsKey(DateTime(2026, 12, 2)), isFalse);
      expect(r.length, 2);
    });
  });

  group('a tela: tocar no dia mostra todos os cultos dele', () {
    Future<void> montar(
      WidgetTester t,
      List<ScaleModel> cultos, {
      bool lider = false,
    }) async {
      await initializeDateFormatting('pt_BR');
      t.view.physicalSize = const Size(375 * 3, 812 * 3);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);

      final provider = ScaleProvider()..carregarParaTeste(cultos);
      await t.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(
                value: _Auth(lider: lider)),
            ChangeNotifierProvider<ScaleProvider>.value(value: provider),
          ],
          child: const MaterialApp(home: ScaleScreen()),
        ),
      );
      await t.pump();
    }

    /// Toca no dia de hoje, dentro do calendário (o número do dia também
    /// aparece nos cartões da lista de próximos cultos).
    Future<void> tocarEmHoje(WidgetTester t) async {
      final hoje = DateTime.now().day;
      await t.tap(find.descendant(
        of: find.byType(TableCalendar),
        matching: find.text('$hoje'),
      ));
      await t.pumpAndSettle();
    }

    testWidgets('dois cultos no mesmo dia: os dois aparecem', (t) async {
      final h = DateTime.now();
      await montar(t, [
        _culto(DateTime(h.year, h.month, h.day, 8)),
        _culto(DateTime(h.year, h.month, h.day, 19, 30)),
      ]);
      await tocarEmHoje(t);

      expect(find.textContaining('às 08:00'), findsOneWidget);
      expect(find.textContaining('às 19:30'), findsOneWidget);
    });

    testWidgets('um culto só continua sendo um cartão', (t) async {
      final h = DateTime.now();
      await montar(t, [_culto(DateTime(h.year, h.month, h.day, 19, 30))]);
      await tocarEmHoje(t);

      expect(find.textContaining('às 19:30'), findsOneWidget);
      expect(find.textContaining('às 08:00'), findsNothing);
    });

    testWidgets('dia sem culto: a frase de sempre', (t) async {
      final h = DateTime.now();
      // Um culto em OUTRO dia do mês, para a tela não cair no "vazio geral".
      final outro = h.day == 1 ? 2 : 1;
      await montar(t, [_culto(DateTime(h.year, h.month, outro, 8))]);
      await tocarEmHoje(t);

      expect(find.textContaining('Nenhum culto em'), findsOneWidget);
    });

    testWidgets('o calendário marca dois pontos no dia de dois cultos',
        (t) async {
      final h = DateTime.now();
      await montar(t, [
        _culto(DateTime(h.year, h.month, h.day, 8)),
        _culto(DateTime(h.year, h.month, h.day, 19)),
      ]);
      // Cada culto é um ponto: o líder vê, sem tocar, que o dia tem dois.
      expect(find.byType(Positioned), findsWidgets);
      final calendario = t.widget<TableCalendar<dynamic>>(
          find.byType(TableCalendar<dynamic>));
      final eventos = calendario.eventLoader!(DateTime(h.year, h.month, h.day));
      expect(eventos.length, 2);
    });

    testWidgets(
        'o "+" de quem lidera abre a criação MESMO num dia que já tem culto',
        (t) async {
      // Antes, "+" num dia com culto pulava para o culto existente — e com
      // dois cultos por dia isso impedia criar o segundo.
      final h = DateTime.now();
      await montar(
        t,
        [_culto(DateTime(h.year, h.month, h.day, 8))],
        lider: true,
      );
      await tocarEmHoje(t);

      await t.tap(find.byIcon(Icons.add_rounded));
      await t.pumpAndSettle();

      expect(find.textContaining('Criar Culto'), findsOneWidget);
      // E diz o que já existe nesse dia.
      expect(find.textContaining('já há'), findsOneWidget);
    });

    testWidgets('criar no MESMO horário de um culto que existe é recusado',
        (t) async {
      final h = DateTime.now();
      // O horário padrão do diálogo é 09:00.
      await montar(
        t,
        [_culto(DateTime(h.year, h.month, h.day, 9))],
        lider: true,
      );
      await tocarEmHoje(t);

      await t.tap(find.byIcon(Icons.add_rounded));
      await t.pumpAndSettle();
      await t.tap(find.text('Criar'));
      await t.pumpAndSettle();

      expect(find.textContaining('Já existe um culto às 09:00'),
          findsOneWidget);
    });
  });
}
