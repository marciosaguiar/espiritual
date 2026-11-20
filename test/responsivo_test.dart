// O app em telas de tamanhos diferentes: o que muda de lugar, e o que NÃO.
//
// A regra é um app só. O celular a 375 px continua com a barra de baixo e uma
// tela de cada vez; só quando sobra espaço a navegação vai para o lado, a
// leitura ganha largura máxima, e lista e detalhe ficam lado a lado.
//
// TODO o texto é inventado.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:levitasync/core/constants/app_colors.dart';
import 'package:levitasync/presentation/screens/chat/chat_screen.dart';
import 'package:levitasync/presentation/screens/songs/hino_por_numero_screen.dart';
import 'package:levitasync/presentation/widgets/common/glass.dart';
import 'package:levitasync/presentation/widgets/common/responsivo.dart';

import 'utilitarios/app_inventado.dart';
import 'utilitarios/fontes.dart';

const _celular = Tamanho(375, 812, 2);
const _tablet = Tamanho(768, 1024, 1);
const _monitor = Tamanho(1280, 800, 1);
const _monitorGrande = Tamanho(1920, 1080, 1);

void main() {
  setUpAll(carregarFontesDoApp);
  tearDown(() => EntradaDoUsuario.definir(false));

  group('a navegação', () {
    testWidgets('celular: a barra fica EMBAIXO, como sempre foi', (t) async {
      addTearDown(t.view.reset);
      await montarApp(t, tam: _celular);
      for (final rotulo in ['Início', 'Músicas', 'Escala', 'Chat', 'Perfil']) {
        final r = t.getRect(find.text(rotulo).first);
        expect(r.center.dy, greaterThan(812 * 0.88), reason: rotulo);
      }
      expect(find.text('LevitaSync'), findsNothing,
          reason: 'sem o nome do app: é só a barra de baixo');
    });

    testWidgets('tablet: vai para o LADO, só ícone com o nome embaixo',
        (t) async {
      addTearDown(t.view.reset);
      await montarApp(t, tam: _tablet);
      final r = t.getRect(find.text('Escala').first);
      expect(r.center.dx, lessThan(120));
      expect(r.center.dy, lessThan(400), reason: 'não está embaixo');
    });

    testWidgets('monitor: navegação larga, com o nome do app', (t) async {
      addTearDown(t.view.reset);
      await montarApp(t, tam: _monitor);
      expect(find.text('LevitaSync'), findsOneWidget);
      final r = t.getRect(find.text('Escala').first);
      expect(r.left, lessThan(120));
      // O ícone e o nome estão na MESMA linha (não um embaixo do outro).
      final icone = t.getRect(find.byIcon(Icons.calendar_month_outlined));
      expect((icone.center.dy - r.center.dy).abs(), lessThan(6));
    });

    testWidgets('tocar numa aba da lateral troca de aba', (t) async {
      addTearDown(t.view.reset);
      await montarApp(t, tam: _monitor);
      await t.tap(find.text('Chat').first);
      await assentar(t);
      expect(find.byType(ChatScreen), findsOneWidget);
      expect(find.text('Ministério de Louvor'), findsOneWidget);
    });
  });

  group('largura máxima: nada esticado', () {
    testWidgets('o chat não passa de uma coluna de leitura num monitor grande',
        (t) async {
      addTearDown(t.view.reset);
      await montarApp(t, tam: _monitorGrande, aba: 3);
      final w = t.getSize(find.byType(ChatScreen)).width;
      expect(w, lessThanOrEqualTo(Porte.colunaDeLeitura + 0.5));
      expect(w, greaterThan(500));
    });

    testWidgets('o perfil também', (t) async {
      addTearDown(t.view.reset);
      await montarApp(t, tam: _monitorGrande, aba: 4);
      final r = t.getRect(find.text('Nas músicas, eu…'));
      expect(r.left, greaterThan(500), reason: 'centralizado, não colado');
      expect(r.left, lessThan(1100));
    });

    testWidgets('uma tela aberta por cima também fica numa coluna', (t) async {
      t.view.physicalSize = const Size(1920, 1080);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.push(
                  ctx,
                  GlassPageRoute(
                      builder: (_) => const Scaffold(body: Text('conteudo'))),
                ),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      ));
      await t.tap(find.text('abrir'));
      await t.pumpAndSettle();
      expect(t.getSize(find.byType(Scaffold).last).width,
          lessThanOrEqualTo(GlassPageRoute.larguraPadrao));
    });

    testWidgets('no celular a coluna não muda nada', (t) async {
      addTearDown(t.view.reset);
      await montarApp(t, tam: _celular, aba: 3);
      expect(t.getSize(find.byType(ChatScreen)).width, 375);
    });
  });

  group('lista e detalhe lado a lado', () {
    Future<void> montarLista(WidgetTester t, Size tela) async {
      t.view.physicalSize = tela;
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: MestreDetalhe(
            vazioTitulo: 'Escolha um item',
            vazioTexto: 'abre aqui',
            mestre: Builder(
              builder: (ctx) => ListView(children: [
                const TextField(key: Key('busca')),
                ListTile(
                  title: const Text('Item um'),
                  onTap: () => abrirTela(
                      ctx, (_) => const Scaffold(body: Text('Detalhe do um'))),
                ),
                ListTile(
                  title: const Text('Item dois'),
                  onTap: () => abrirTela(
                      ctx, (_) => const Scaffold(body: Text('Detalhe do dois'))),
                ),
              ]),
            ),
          ),
        ),
      ));
      await t.pumpAndSettle();
    }

    testWidgets('em tela larga o detalhe abre AO LADO, e a lista continua',
        (t) async {
      await montarLista(t, const Size(1280, 800));
      expect(find.text('Escolha um item'), findsOneWidget);

      await t.tap(find.text('Item um'));
      await t.pumpAndSettle();
      expect(find.text('Detalhe do um'), findsOneWidget);
      expect(find.text('Item um'), findsOneWidget, reason: 'a lista segue');
      expect(t.getRect(find.text('Detalhe do um')).left,
          greaterThan(t.getRect(find.text('Item um')).right));
    });

    testWidgets('trocar de item troca o detalhe, sem empilhar', (t) async {
      await montarLista(t, const Size(1280, 800));
      await t.tap(find.text('Item um'));
      await t.pumpAndSettle();
      await t.tap(find.text('Item dois'));
      await t.pumpAndSettle();
      expect(find.text('Detalhe do dois'), findsOneWidget);
      expect(find.text('Detalhe do um'), findsNothing);
    });

    testWidgets('em tela estreita abre POR CIMA, como sempre', (t) async {
      await montarLista(t, const Size(375, 812));
      expect(find.text('Escolha um item'), findsNothing);
      await t.tap(find.text('Item um'));
      await t.pumpAndSettle();
      expect(find.text('Detalhe do um'), findsOneWidget);
      expect(find.text('Item dois'), findsNothing,
          reason: 'a tela nova cobre a lista');
    });

    testWidgets('redimensionar a janela NÃO perde o que se digitou na lista',
        (t) async {
      await montarLista(t, const Size(1280, 800));
      await t.enterText(find.byKey(const Key('busca')), 'firmes');
      await t.pumpAndSettle();

      t.view.physicalSize = const Size(700, 800);
      await t.pumpAndSettle();
      expect(find.text('firmes'), findsOneWidget,
          reason: 'virou tela de um painel só; a busca continua');

      t.view.physicalSize = const Size(1280, 800);
      await t.pumpAndSettle();
      expect(find.text('firmes'), findsOneWidget);
    });

    testWidgets('o painel pode ser fechado de fora (é o que o Esc faz)',
        (t) async {
      await montarLista(t, const Size(1280, 800));
      await t.tap(find.text('Item um'));
      await t.pumpAndSettle();
      final painel =
          PainelDeDetalhe.maybeOf(t.element(find.text('Item um')))!;
      expect(painel.aberto, isTrue);
      painel.fechar();
      await t.pumpAndSettle();
      expect(find.text('Detalhe do um'), findsNothing);
      expect(find.text('Escolha um item'), findsOneWidget);
    });
  });

  group('as telas largas do app', () {
    testWidgets('Escala: o culto abre ao lado do calendário', (t) async {
      addTearDown(t.view.reset);
      await montarApp(t, tam: _monitor, aba: 2);
      await t.tap(find.textContaining('Culto de quarta').first);
      await assentar(t);
      expect(find.text('Modo Culto ao vivo'), findsOneWidget);
      // E o calendário continua à esquerda.
      expect(find.text('novembro de 2026'), findsOneWidget);
      expect(t.getRect(find.text('Modo Culto ao vivo')).left,
          greaterThan(t.getRect(find.text('novembro de 2026')).right));
    });

    testWidgets('Músicas: a música abre ao lado da lista', (t) async {
      addTearDown(t.view.reset);
      await montarApp(t, tam: _monitor, aba: 1);
      await t.tap(find.text('Grande é a tua fidelidade').first);
      await assentar(t);
      expect(find.textContaining('Tom'), findsWidgets);
      expect(find.text('Repertório'), findsOneWidget,
          reason: 'a lista segue na tela');
    });

    testWidgets('Hinários: o hino abre ao lado, e no celular, por cima',
        (t) async {
      addTearDown(t.view.reset);
      await montarApp(t, tam: _monitor, aba: 1);
      await t.tap(find.text('Hinários'));
      await assentar(t);
      // Com mouse não há teclado numérico: vai direto para a lista.
      expect(find.text('Digitar o número'), findsNothing);
      // O campo da lista de hinos — o app tem outros (o do chat, fora da
      // tela, mas montado).
      final campo = find.descendant(
          of: find.byType(HinoPorNumeroScreen), matching: find.byType(TextField));
      await t.enterText(campo, '65');
      await t.testTextInput.receiveAction(TextInputAction.search);
      await assentar(t);
      // O 65 está no repertório (é uma música), então abre a tela da música.
      expect(find.textContaining('HC 65'), findsWidgets);
      expect(find.text('Hinários'), findsWidgets, reason: 'a lista segue');
    });

    testWidgets('Início usa as duas colunas, e no celular uma só', (t) async {
      addTearDown(t.view.reset);
      await montarApp(t, tam: _monitor);
      final culto = t.getRect(find.text('Neste culto'));
      final pend = t.getRect(find.text('Um culto sem ninguém escalado'));
      expect(pend.left, greaterThan(culto.right),
          reason: 'as pendências ficam À DIREITA do culto');
    });

    testWidgets('Início, no celular: tudo numa coluna', (t) async {
      addTearDown(t.view.reset);
      await montarApp(t, tam: _celular);
      final culto = t.getRect(find.text('Neste culto'));
      expect(culto.left, lessThan(100));
    });
  });

  group('mouse', () {
    testWidgets('passar o mouse acende o item e mostra a mãozinha',
        (t) async {
      addTearDown(t.view.reset);
      await montarApp(t, tam: _monitor);
      final alvo = find.text('Escala').first;
      final gesto = await t.createGesture(kind: PointerDeviceKind.mouse);
      await gesto.addPointer(location: Offset.zero);
      addTearDown(gesto.removePointer);

      await gesto.moveTo(t.getCenter(alvo));
      await t.pump(const Duration(milliseconds: 300));
      expect(
          RendererBinding.instance.mouseTracker
              .debugDeviceActiveCursor(1),
          SystemMouseCursors.click);
    });

    testWidgets('o mouse vira "mouse"; o dedo vira "toque"', (t) async {
      EntradaDoUsuario.registrar(PointerDeviceKind.touch);
      expect(EntradaDoUsuario.toque.value, isTrue);
      EntradaDoUsuario.registrar(PointerDeviceKind.mouse);
      expect(EntradaDoUsuario.toque.value, isFalse);
      EntradaDoUsuario.registrar(PointerDeviceKind.stylus);
      expect(EntradaDoUsuario.toque.value, isTrue);
      EntradaDoUsuario.registrar(PointerDeviceKind.trackpad);
      expect(EntradaDoUsuario.toque.value, isFalse);
    });

    testWidgets('tela estreita é SEMPRE toque, mesmo que o último ponteiro '
        'tenha sido o mouse', (t) async {
      t.view.physicalSize = const Size(375, 812);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      EntradaDoUsuario.definir(false);
      late bool toque;
      await t.pumpWidget(MaterialApp(
        home: Builder(builder: (ctx) {
          toque = EntradaDoUsuario.usaToque(ctx);
          return const SizedBox();
        }),
      ));
      expect(toque, isTrue);
    });
  });

  group('o Perfil não corta o avatar ao rolar', () {
    // O defeito era VISUAL: ao rolar, o cabeçalho encolhia e o avatar (de
    // altura fixa) ficava pela metade, cortado pela barra. Não lançava erro
    // nenhum — então a conferência é geométrica: em cada ponto da rolagem o
    // avatar grande tem de caber DENTRO do cabeçalho.
    testWidgets('em todo ponto da rolagem o avatar cabe no cabeçalho',
        (t) async {
      addTearDown(t.view.reset);
      await montarApp(t, tam: _celular, aba: 4);
      final cabecalho = find.byWidgetPredicate((w) =>
          w is Container &&
          w.decoration is BoxDecoration &&
          (w.decoration as BoxDecoration).gradient != null &&
          (w.decoration as BoxDecoration).gradient ==
              AppColors.primaryGradient);

      for (final passo in [0.0, -40.0, -40.0, -40.0, -40.0, -60.0]) {
        if (passo != 0) {
          await t.drag(find.byType(CustomScrollView).first, Offset(0, passo));
          await assentar(t);
        }
        final avatar = t.getRect(find.byType(CircleAvatar).first);
        final topo = t.getRect(cabecalho);
        expect(avatar.top, greaterThanOrEqualTo(topo.top - 1),
            reason: 'avatar cortado em cima (rolou $passo)');
        expect(avatar.bottom, lessThanOrEqualTo(topo.bottom + 1),
            reason: 'avatar cortado embaixo (rolou $passo)');
      }
      expect(t.takeException(), isNull);
    });

    testWidgets('recolhido, a barra mostra o nome (antes sobrava vazia)',
        (t) async {
      addTearDown(t.view.reset);
      await montarApp(t, tam: _celular, aba: 4);
      await t.drag(find.byType(CustomScrollView).first, const Offset(0, -500));
      await assentar(t);
      expect(t.takeException(), isNull);
      // O nome aparece NA BARRA (no alto da tela), não só no corpo.
      final nome = find.text('Ana Souza');
      expect(nome, findsWidgets);
      expect(t.getRect(nome.first).top, lessThan(80));
    });
  });
}
