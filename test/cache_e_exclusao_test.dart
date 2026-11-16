import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:levitasync/firebase_options.dart';

/// Duas travas que não têm como ser testadas pelo comportamento do app: uma
/// linha de configuração que, se sumir, não quebra nada — só volta a custar
/// caro —, e um caminho de apagar que não pode voltar a existir.
void main() {
  group('cache no aparelho', () {
    test('o app continua ligando o cache persistente', () {
      // Medido no emulador, com o banco do tamanho do ministério: a segunda
      // abertura baixava 202 documentos do servidor e passou a baixar zero.
      // Tirar esta linha não quebra tela nenhuma — o app continua
      // funcionando, lendo tudo de novo a cada abertura e gastando a cota de
      // leitura, que é a que aperta no plano grátis. É o tipo de perda que
      // ninguém nota até a cota estourar num domingo.
      final main = File('lib/main.dart').readAsStringSync();
      expect(main, contains('persistenceEnabled: true'),
          reason: 'sem isto cada abertura relê tudo do servidor');
      expect(main.indexOf('persistenceEnabled: true'),
          greaterThan(main.indexOf('Firebase.initializeApp')),
          reason: 'as configurações valem depois de iniciar o Firebase e '
              'antes da primeira leitura');
    });
  });

  group('culto não se apaga', () {
    test('nenhum caminho do app apaga um culto', () {
      final culpados = <String>[];
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        if (f.readAsStringSync().contains('deleteScale')) {
          culpados.add(f.path);
        }
      }
      expect(culpados, isEmpty,
          reason: 'cancelar é um campo, nunca exclusão: um culto apagado '
              'leva junto quem confirmou, o repertório e o registro de quem '
              'tocou — e o da agenda fixa voltaria sozinho');
    });

    test('a regra do banco recusa apagar culto, inclusive do líder', () {
      // A trava de verdade é esta: esconder o botão não adianta, porque
      // qualquer um fala direto com o banco pela API.
      final regras = File('firestore.rules').readAsStringSync();
      final inicio = regras.indexOf('match /scales/{scaleId} {');
      expect(inicio, greaterThan(-1), reason: 'bloco de scales não encontrado');
      // O bloco do culto termina onde começa o do estado "ao vivo", que é
      // subcoleção dele e tem regra de apagar própria (estado efêmero).
      final fim = regras.indexOf('match /scales/{scaleId}/aoVivo', inicio);
      expect(fim, greaterThan(inicio));

      final bloco = regras.substring(inicio, fim);
      expect(bloco, contains('allow delete: if false'));
      expect(bloco.contains('allow delete: if ehLider()'), isFalse);
    });
  });

  group('plataformas sem projeto no Firebase', () {
    test('iOS e macOS avisam na hora, em vez de abrir e falhar calado', () {
      // Os dois blocos apontavam para um projeto `levitasync` que nunca
      // existiu. Compilar nativo não dava erro: o app abria, toda chamada ao
      // banco falhava e as telas ficavam vazias.
      for (final plataforma in [TargetPlatform.iOS, TargetPlatform.macOS]) {
        debugDefaultTargetPlatformOverride = plataforma;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);

        expect(
          () => DefaultFirebaseOptions.currentPlatform,
          throwsA(isA<UnsupportedError>().having(
            (e) => e.message,
            'recado',
            allOf(
              contains('espiritual-d2403'),
              contains('flutterfire configure'),
              // O plist é de exemplo pelo mesmo motivo e seria a próxima
              // pedra no caminho de quem acabou de ler este erro.
              contains('GoogleService-Info.plist'),
            ),
          )),
        );
      }
      debugDefaultTargetPlatformOverride = null;
    });

    test('nenhuma chave de exemplo sobrou no arquivo', () {
      final fonte = File('lib/firebase_options.dart').readAsStringSync();
      expect(fonte.contains("apiKey: 'YOUR_"), isFalse);
      expect(fonte.contains("projectId: 'levitasync'"), isFalse,
          reason: 'projeto de exemplo que não existe');
    });

    test('as chaves que sobraram são as do projeto de verdade', () {
      for (final o in [
        DefaultFirebaseOptions.web,
        DefaultFirebaseOptions.android,
      ]) {
        expect(o.projectId, 'espiritual-d2403');
        expect(o.apiKey.startsWith('YOUR_'), isFalse);
        expect(o.appId.contains('000000000000'), isFalse);
      }
    });
  });
}
