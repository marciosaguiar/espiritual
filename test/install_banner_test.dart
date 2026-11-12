import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:levitasync/core/platform/install.dart';
import 'package:levitasync/presentation/widgets/common/install_banner.dart';

/// Nos testes vale a implementação de `install_stub.dart` — a mesma que
/// Android e iOS usam. É exatamente o caso que precisa ser garantido: num app
/// já instalado, nada de instalação pode aparecer.
void main() {
  group('plataforma nativa', () {
    test('o app nativo se considera instalado', () {
      expect(estaInstalado, isTrue);
      expect(caminhoDeInstalacao, InstallRoute.naoSeAplica);
    });

    test('não existe convite do navegador para abrir', () async {
      expect(await convidarParaInstalar(), isFalse);
    });

    testWidgets('a faixa não ocupa espaço nenhum no app instalado',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: InstallBanner()),
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('tela de início'), findsNothing);
      expect(find.byType(ElevatedButton), findsNothing);
      // Um SizedBox.shrink não tem altura: a tela inicial não ganha um vão.
      expect(tester.getSize(find.byType(InstallBanner)), Size.zero);
    });
  });
}
