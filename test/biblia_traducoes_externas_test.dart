// NVI, Linguagem de Hoje (NTLH), ARA, ARC e NAA: no fim de cada capítulo.
//
// Essas traduções são de editoras e NÃO moram no app (ver `biblia_test.dart`,
// que reprova se alguma entrar na lista de textos). O que o app oferece é abrir
// o MESMO capítulo nelas, no YouVersion, com a NVI como padrão.
//
// O que estes testes guardam:
//   · os números do YouVersion, que foram conferidos no site e são um contrato:
//     um número errado levaria a pessoa a outra Bíblia sem aviso nenhum;
//   · a tela: a NVI em destaque, as outras quatro na mesma ordem, tudo à vista
//     e cabendo a 375 px;
//   · o capítulo do link ACOMPANHA a leitura (depois de passar de capítulo, o
//     link não pode continuar no antigo);
//   · link que não abre AVISA, em vez de um toque que não faz nada.
//
// TODO o texto bíblico aqui é inventado.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:levitasync/core/constants/livros_biblia.dart';
import 'package:levitasync/data/services/biblia_service.dart';
import 'package:levitasync/data/services/local_storage_service.dart';
import 'package:levitasync/presentation/providers/biblia_provider.dart';
import 'package:levitasync/presentation/screens/biblia/biblia_leitura_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'utilitarios/fontes.dart';

const _canal = MethodChannel('plugins.flutter.io/url_launcher');

Traducao _inventada({int versos = 2}) => Traducao(
      id: 'inventada',
      sigla: 'TESTE',
      nome: 'Texto inventado',
      credito: 'Crédito inventado para o teste.',
      licenca: 'Inventada',
      licencaUrl: '',
      capitulos: {
        'jo': [
          ['Versículo inventado um.', 'Versículo inventado dois.'],
          ['Versículo inventado um.'],
          [for (var i = 1; i <= versos; i++) 'Versículo inventado número $i.'],
          ['Versículo inventado um.'],
        ],
      },
    );

void main() {
  setUpAll(carregarFontesDoApp);

  group('os números do YouVersion (conferidos no bible.com)', () {
    test('a NVI é a primeira, e a padrão', () {
      expect(traducoesExternas.first.sigla, 'NVI');
      expect(traducoesExternas.first.codigoNoYouVersion, 129);
    });

    test('são as cinco combinadas, nesta ordem', () {
      expect([for (final t in traducoesExternas) t.sigla],
          ['NVI', 'NTLH', 'ARA', 'ARC', 'NAA']);
    });

    test('cada sigla abre o seu número, e o capítulo é o mesmo', () {
      // Cada número foi aberto no site e mostrou "João 3 | <SIGLA> Bíblia".
      const esperado = {
        'NVI': 129,
        'NTLH': 211,
        'ARA': 1608,
        'ARC': 212,
        'NAA': 1840,
      };
      for (final t in traducoesExternas) {
        expect(t.codigoNoYouVersion, esperado[t.sigla],
            reason: '${t.sigla} está com o número errado');
        final u = BibliaService.noYouVersion('jo', 3, em: t);
        expect(u.host, 'www.bible.com');
        expect(u.path, '/pt/bible/${esperado[t.sigla]}/JHN.3');
      }
    });

    test('sem dizer a tradução, abre a NVI', () {
      expect(BibliaService.noYouVersion('jo', 3).path, '/pt/bible/129/JHN.3');
    });

    test('o livro continua certo em qualquer tradução (USFM)', () {
      final ara = traducoesExternas.firstWhere((t) => t.sigla == 'ARA');
      expect(BibliaService.noYouVersion('ct', 2, em: ara).path,
          '/pt/bible/1608/SNG.2');
      expect(BibliaService.noYouVersion('1co', 13, em: ara).path,
          '/pt/bible/1608/1CO.13');
    });

    test('livro que não conhecemos cai na busca, em qualquer tradução', () {
      final ntlh = traducoesExternas.firstWhere((t) => t.sigla == 'NTLH');
      final u = BibliaService.noYouVersion('xx', 1, em: ntlh);
      expect(u.path, '/search/bible');
    });

    test('nada se repete: nem id, nem sigla, nem número', () {
      final ids = {for (final t in traducoesExternas) t.id};
      final siglas = {for (final t in traducoesExternas) t.sigla};
      final numeros = {for (final t in traducoesExternas) t.codigoNoYouVersion};
      expect(ids, hasLength(traducoesExternas.length));
      expect(siglas, hasLength(traducoesExternas.length));
      expect(numeros, hasLength(traducoesExternas.length));
    });

    test('as externas NÃO são as que moram no app (e vice-versa)', () {
      // Se uma sigla de editora aparecesse nas duas listas, o app estaria
      // oferecendo para ler dentro dele o que só pode abrir fora.
      final dentro = {for (final t in traducoesDisponiveis) t.sigla};
      for (final t in traducoesExternas) {
        expect(dentro, isNot(contains(t.sigla)));
      }
    });

    test('todas dizem quem publica e como a pessoa as conhece', () {
      for (final t in traducoesExternas) {
        expect(t.nome.trim(), isNotEmpty);
        expect(t.editora.trim(), isNotEmpty);
      }
      // "Linguagem de Hoje" é como o ministério chama a NTLH: a sigla sozinha
      // não diz nada a quem não é da área.
      expect(
          traducoesExternas.firstWhere((t) => t.sigla == 'NTLH').nome,
          contains('Linguagem de Hoje'));
    });
  });

  group('a tela de leitura', () {
    late List<String> abertos;
    late bool abre;

    setUp(() async {
      abertos = [];
      abre = true;
      SharedPreferences.setMockInitialValues({});
      await LocalStorageService.init();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_canal, (call) async {
        if (call.method == 'launch') {
          abertos.add((call.arguments as Map)['url'] as String);
          return abre;
        }
        return abre; // canLaunch
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_canal, null);
    });

    Future<void> montar(WidgetTester t,
        {double largura = 375,
        double altura = 812,
        int capitulo = 3,
        int versos = 2,
        bool rolarAteOFim = true}) async {
      t.view.physicalSize = Size(largura, altura);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        ChangeNotifierProvider(
          create: (_) =>
              BibliaProvider()..carregarParaTeste(_inventada(versos: versos)),
          child: MaterialApp(
            home: BibliaLeituraScreen(
              livro: livroPorSigla('jo')!,
              capitulo: capitulo,
            ),
          ),
        ),
      );
      await t.pump();
      if (!rolarAteOFim) return;
      // O que se quer ver fica no FIM da página: rola até lá, como a pessoa.
      await t.drag(find.byType(ListView), const Offset(0, -2000));
      await t.pumpAndSettle();
    }

    testWidgets('a NVI aparece em destaque, e as outras quatro logo abaixo',
        (t) async {
      await montar(t);
      expect(find.text('Ler João 3 na NVI'), findsOneWidget);
      expect(find.textContaining('Nova Versão Internacional'), findsOneWidget);

      // As quatro outras, na MESMA ordem da lista — lista que muda de lugar
      // faz a pessoa tocar na linha errada.
      final y = [
        for (final s in ['NTLH', 'ARA', 'ARC', 'NAA']) t.getTopLeft(find.text(s)).dy
      ];
      expect(y, [...y]..sort());
      expect(y.toSet(), hasLength(4));

      // E abaixo do botão da NVI.
      expect(y.first,
          greaterThan(t.getBottomLeft(find.text('Ler João 3 na NVI')).dy));
    });

    testWidgets('diz que abre fora e que precisa de internet', (t) async {
      await montar(t);
      expect(find.textContaining('precisa de internet'), findsOneWidget);
      expect(find.textContaining('não podem ser guardadas'), findsOneWidget);
    });

    testWidgets('a 375 px nada estoura nem passa da borda', (t) async {
      await montar(t);
      expect(t.takeException(), isNull);
      for (final s in ['NTLH', 'ARA', 'ARC', 'NAA']) {
        expect(t.getRect(find.text(s)).right, lessThanOrEqualTo(375));
      }
      expect(t.getRect(find.text('Ler João 3 na NVI')).right,
          lessThanOrEqualTo(375));
    });

    testWidgets('em tela estreita e com letra do sistema grande, ainda cabe',
        (t) async {
      // 320 px é o celular mais estreito que ainda se usa.
      await montar(t, largura: 320, altura: 640);
      expect(t.takeException(), isNull);
    });

    testWidgets('a NVI abre o capítulo na NVI', (t) async {
      await montar(t);
      await t.tap(find.text('Ler João 3 na NVI'));
      await t.pumpAndSettle();
      expect(abertos, ['https://www.bible.com/pt/bible/129/JHN.3']);
    });

    for (final c in const {
      'NTLH': 211,
      'ARA': 1608,
      'ARC': 212,
      'NAA': 1840,
    }.entries) {
      testWidgets('tocar em ${c.key} abre o capítulo na ${c.key}', (t) async {
        await montar(t);
        await t.tap(find.text(c.key));
        await t.pumpAndSettle();
        expect(abertos, ['https://www.bible.com/pt/bible/${c.value}/JHN.3']);
      });
    }

    testWidgets('o link ACOMPANHA o capítulo: passou para o 4, abre o 4',
        (t) async {
      await montar(t);
      await t.tap(find.text('João 4')); // o botão "próximo" da barra de baixo
      await t.pumpAndSettle();
      await t.drag(find.byType(ListView), const Offset(0, -2000));
      await t.pumpAndSettle();

      expect(find.text('Ler João 4 na NVI'), findsOneWidget);
      await t.tap(find.text('ARA'));
      await t.pumpAndSettle();
      expect(abertos, ['https://www.bible.com/pt/bible/1608/JHN.4']);
    });

    testWidgets('link que não abre AVISA, com o endereço e um "Copiar"',
        (t) async {
      abre = false;
      await montar(t);
      await t.tap(find.text('NTLH'));
      await t.pumpAndSettle();
      expect(find.textContaining('Não consegui abrir'), findsOneWidget);
      expect(find.textContaining('/pt/bible/211/JHN.3'), findsOneWidget);
      expect(find.text('Copiar'), findsOneWidget);
    });

    testWidgets('o toque dá sinal: há um Material entre a caixa e as linhas',
        (t) async {
      // O efeito do toque é pintado no Material mais próximo. Sem um dentro
      // da caixa colorida, ela o esconde e o toque parece não ter feito nada.
      await montar(t);
      for (final s in ['NTLH', 'ARA', 'ARC', 'NAA']) {
        final material = find.ancestor(
            of: find.text(s),
            matching: find.byWidgetPredicate(
                (w) => w is Material && w.type == MaterialType.transparency));
        expect(material, findsWidgets, reason: '$s sem Material por perto');
      }
    });

    testWidgets('cada linha tem altura de dedo (44 px ou mais)', (t) async {
      await montar(t);
      for (final s in ['NTLH', 'ARA', 'ARC', 'NAA']) {
        final linha = find.ancestor(
            of: find.text(s), matching: find.byType(InkWell));
        expect(t.getSize(linha.first).height, greaterThanOrEqualTo(44),
            reason: '$s: toque pequeno demais');
      }
      // `FilledButton.icon` cria uma subclasse: `byType` só acha o tipo exato.
      expect(t.getSize(find.bySubtype<FilledButton>()).height,
          greaterThanOrEqualTo(44));
    });

    testWidgets('num capítulo comprido, rolando se chega ao fim e tudo aparece '
        'ACIMA da barra de capítulos', (t) async {
      // Foi o que quase enganou a primeira foto: um arrasto só pára numa
      // estimativa do tamanho da página, e o cartão ficava debaixo da barra.
      // Aqui se rola como a pessoa, até o último aviso aparecer.
      await montar(t, versos: 30, rolarAteOFim: false);
      final rodape = find.textContaining('não podem ser guardadas');
      await t.scrollUntilVisible(rodape, 300,
          scrollable: find.byType(Scrollable).first);
      await t.pumpAndSettle();

      final barra = t.getRect(find.bySubtype<OutlinedButton>().first);
      expect(t.getRect(rodape).bottom, lessThanOrEqualTo(barra.top),
          reason: 'o aviso final ficou escondido pela barra de baixo');
      for (final s in ['NTLH', 'ARA', 'ARC', 'NAA']) {
        expect(t.getRect(find.text(s)).bottom, lessThanOrEqualTo(barra.top),
            reason: '$s ficou escondida pela barra de baixo');
      }
    });

    testWidgets('a leitura em si não mudou: o texto e o crédito continuam',
        (t) async {
      await montar(t);
      expect(find.textContaining('Crédito inventado'), findsOneWidget);
    });
  });
}
