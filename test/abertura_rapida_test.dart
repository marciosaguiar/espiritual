// A abertura do app: o que foi tirado do caminho, e o que impede de voltar.
//
// Cada item aqui é uma coisa MEDIDA num Chromium com a rede e o processador de
// um celular segurados (ver `ferramentas/medir/`). O que estes testes guardam
// é o que não aparece na tela quando volta: ninguém vê um emoji que faz o
// navegador baixar 380 KB, nem uma fonte que passou a ser pedida antes do
// primeiro quadro.
//
// TODO o texto é inventado.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:levitasync/core/utils/fonte_mono.dart';
import 'package:levitasync/presentation/screens/chat/chat_screen.dart';
import 'package:levitasync/presentation/screens/profile/profile_screen.dart';

import 'utilitarios/app_inventado.dart';

String _ler(String caminho) => File(caminho).readAsStringSync();

/// A versão do SDK do Firebase que o `firebase_core_web` do projeto carrega.
String _versaoDoSdk() {
  final config = jsonDecode(_ler('.dart_tool/package_config.json'))
      as Map<String, dynamic>;
  final pacote = (config['packages'] as List)
      .cast<Map<String, dynamic>>()
      .firstWhere((p) => p['name'] == 'firebase_core_web');
  final raiz = Uri.parse(pacote['rootUri'] as String);
  final base = raiz.isAbsolute
      ? raiz.toFilePath()
      : Directory('.dart_tool').uri.resolveUri(raiz).toFilePath();
  final fonte = _ler('$base/lib/src/firebase_sdk_version.dart');
  return RegExp(r"supportedFirebaseJsSdkVersion\s*=\s*'([^']+)'")
      .firstMatch(fonte)!
      .group(1)!;
}

void main() {
  setUpAll(carregarFontes);

  group('dicas de rede do index.html', () {
    final html = _ler('web/index.html');

    test('o SDK que se antecipa é o MESMO que o app vai carregar', () {
      // Versão diferente = o navegador baixa 175 KB que ninguém usa e o app
      // baixa de novo o que ele pediu: a dica passa a custar em vez de
      // ajudar, e nada na tela avisa.
      final v = _versaoDoSdk();
      for (final s in ['app', 'auth', 'firestore']) {
        expect(
          html,
          contains(
              '<link rel="modulepreload" href="https://www.gstatic.com/firebasejs/$v/firebase-$s.js">'),
          reason: 'firebase-$s.js não está antecipado, ou está em outra versão '
              '(o pubspec.lock carrega $v)',
        );
      }
    });

    test('conecta antes aos três servidores do Google que o app usa', () {
      for (final h in [
        'https://www.gstatic.com',
        'https://identitytoolkit.googleapis.com',
        'https://firestore.googleapis.com',
      ]) {
        expect(html, contains('<link rel="preconnect" href="$h" crossorigin>'));
      }
    });
  });

  group('o service worker não disputa a linha com a abertura', () {
    final html = _ler('web/index.html');

    test('só registra DEPOIS do primeiro quadro do Flutter', () {
      // Registrar no `load` fazia o navegador começar a instalar o cache
      // enquanto o app ainda baixava o motor gráfico: duas filas, uma linha.
      expect(html, contains("'flutter-first-frame'"));
      expect(
        RegExp(r"addEventListener\('load',\s*function \(\)\s*\{\s*navigator\.serviceWorker\.register")
            .hasMatch(html),
        isFalse,
        reason: 'o registro voltou a ficar preso ao evento `load`',
      );
    });

    test('a primeira instalação NÃO recarrega a página', () {
      // O service worker assume a página já aberta; recarregá-la jogava fora
      // o app no meio do uso (numa linha lenta, minutos depois de abrir).
      expect(html, contains('tinhaControlador'));
      expect(html, contains('if (!tinhaControlador)'));
    });
  });

  group('fora do caminho da abertura', () {
    test('a fonte da cifra não é preloaded: é ativo, carregado sob demanda', () {
      final pubspec = _ler('pubspec.yaml');
      final fontes = pubspec.substring(pubspec.indexOf('  fonts:'));
      expect(fontes.contains('family: JetBrainsMono'), isFalse,
          reason: 'declarada em `fonts:`, o navegador a baixa antes do '
              'primeiro quadro, toda abertura (89 KB)');
      expect(pubspec, contains('- assets/fonts/JetBrainsMono.ttf'),
          reason: 'sem ser ativo, FonteMono não tem de onde carregar');
    });

    test('o nome "Roboto" existe no pacote: sem ele o Flutter baixa a Roboto '
        'do Google na abertura', () {
      final pubspec = _ler('pubspec.yaml');
      expect(pubspec, contains('family: Roboto'),
          reason: 'sem este nome o motor busca a fonte em fonts.gstatic.com, '
              'numa conexão nova, no caminho de ligar o app (~1 s numa linha '
              'ruim)');
      expect(pubspec, contains('assets/fonts/Roboto-minima.ttf'));
      // Tem de ser mínima: apontar para uma fonte inteira faz o navegador
      // baixar essa fonte uma vez a mais.
      final tamanho = File('assets/fonts/Roboto-minima.ttf').lengthSync();
      expect(tamanho, lessThan(4096));
    });

    test('toda tela que usa a fonte da cifra a pede', () {
      // Sem isto a cifra ficaria na fonte comum e os acordes sairiam do
      // lugar — o erro mais caro de uma cifra.
      final sem = <String>[];
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        if (f.path.endsWith('fonte_mono.dart')) continue;
        final t = f.readAsStringSync();
        if (t.contains("'JetBrainsMono'") && !t.contains('FonteMono')) {
          sem.add(f.path);
        }
      }
      expect(sem, isEmpty, reason: 'usam JetBrainsMono sem pedir: $sem');
    });

    test('pedir a fonte várias vezes registra uma vez só', () async {
      final a = FonteMono.garantir();
      final b = FonteMono.garantir();
      expect(identical(a, b), isTrue);
      await a; // e não lança
    });

    test('o Início não tem emoji: o navegador baixaria a fonte de emoji do '
        'Google (~380 KB) em TODA abertura', () {
      final achados = <String>[];
      for (final pasta in [
        'lib/presentation/screens/home',
        'lib/presentation/widgets/home',
      ]) {
        for (final f in Directory(pasta).listSync(recursive: true)) {
          if (f is! File || !f.path.endsWith('.dart')) continue;
          var n = 0;
          for (final linha in f.readAsLinesSync()) {
            n++;
            if (linha.trimLeft().startsWith('//')) continue;
            if (linha.runes.any((r) => r >= 0x1F300 && r <= 0x1FAFF ||
                r >= 0x2600 && r <= 0x27BF)) {
              achados.add('${f.path}:$n');
            }
          }
        }
      }
      expect(achados, isEmpty);
    });
  });

  group('abas construídas sob demanda', () {
    testWidgets('só a aba de abertura nasce pronta', (t) async {
      addTearDown(t.view.reset);
      await montarApp(t, tam: tamanhos[375]!, aba: 0);
      // `skipOffstage: false` enxerga também o que está escondido.
      expect(find.byType(ChatScreen, skipOffstage: false), findsNothing,
          reason: 'o chat foi construído na abertura, sem ninguém pedir');
      expect(find.byType(ProfileScreen, skipOffstage: false), findsNothing);
    });

    testWidgets('na primeira visita a aba é construída, e DEPOIS fica',
        (t) async {
      addTearDown(t.view.reset);
      await montarApp(t, tam: tamanhos[375]!, aba: 0);

      await t.tap(find.text('Chat').last);
      await assentar(t);
      expect(find.byType(ChatScreen), findsOneWidget);

      // Volta ao Início: a aba do chat continua montada (guarda o que foi
      // digitado), só escondida.
      await t.tap(find.text('Início').last);
      await assentar(t);
      expect(find.byType(ChatScreen, skipOffstage: false), findsOneWidget);
    });

    testWidgets('a aba de abertura pedida é a que nasce (aviso no chat)',
        (t) async {
      addTearDown(t.view.reset);
      await montarApp(t, tam: tamanhos[375]!, aba: 3);
      expect(find.byType(ChatScreen), findsOneWidget);
    });
  });
}
