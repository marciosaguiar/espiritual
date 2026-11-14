import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:levitasync/presentation/widgets/common/glass.dart';

/// Opening a screen on top of another one used to show the two mixed together
/// for the length of the animation: both themes set the Scaffold background to
/// transparent so the app-wide backdrop shows through, and that made the
/// incoming screen see-through as well.
///
/// The fix has two halves, and a test for each — the second one matters most,
/// because the fix only holds while every push site uses the new route.
void main() {
  group('transição de tela', () {
    testWidgets('a rota que entra pinta o próprio fundo', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (_, child) => GlassBackdrop(child: child!),
          home: const Scaffold(body: Text('calendário')),
        ),
      );

      // Only the app-wide backdrop so far.
      expect(find.byType(GlassBackdrop), findsOneWidget);

      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.push(GlassPageRoute(
        builder: (_) => const Scaffold(body: Text('detalhe do culto')),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      // Mid-animation the incoming route carries a backdrop of its own, which
      // is what covers the screen underneath.
      expect(find.byType(GlassBackdrop), findsNWidgets(2));
      expect(find.text('detalhe do culto'), findsOneWidget);

      await tester.pumpAndSettle();
      expect(find.byType(GlassBackdrop), findsNWidgets(2));
    });

    testWidgets('a rota é opaca, então o Navigator para de pintar o que está '
        'embaixo quando ela chega', (tester) async {
      final rota = GlassPageRoute<void>(builder: (_) => const SizedBox());
      expect(rota.opaque, isTrue);
    });

    test('nenhuma tela volta a usar MaterialPageRoute', () {
      final telas = Directory('lib/presentation/screens');
      expect(telas.existsSync(), isTrue,
          reason: 'rode os testes da raiz do projeto');

      final reincidentes = <String>[];
      for (final f in telas.listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        if (f.readAsStringSync().contains('MaterialPageRoute(')) {
          reincidentes.add(f.path);
        }
      }

      expect(reincidentes, isEmpty,
          reason: 'MaterialPageRoute deixa a tela que entra transparente '
              'durante a animação; use GlassPageRoute');
    });
  });
}
