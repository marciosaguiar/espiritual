// As chaves do projeto do Firebase, por plataforma.
//
// Geradas por `flutterfire configure`. Só existem web e Android, que são as
// duas plataformas em que este app roda: o iPhone usa o PWA instalado na tela
// de início, não um aplicativo nativo.
//
// iOS e macOS tinham blocos aqui, com chaves de exemplo apontando para um
// projeto chamado `levitasync` que nunca existiu. Compilar nativo com eles
// não dava erro de compilação: o app abria e toda chamada ao banco falhava,
// que é a pior forma de uma configuração faltar. Agora a falta é dita na
// hora, com o nome do projeto certo.

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// O recado de quem tentou compilar para uma plataforma sem projeto.
///
/// Diz o que fazer, e cita o id do projeto de verdade — sem isso, quem leu o
/// erro iria procurar as chaves do `levitasync`, que não existe.
String _semProjeto(String plataforma) =>
    'O $plataforma não está configurado no Firebase.\n\n'
    'Este app roda como web/PWA (é assim que ele é usado no iPhone, instalado '
    'na tela de início) e como aplicativo Android. Para compilar nativo para '
    '$plataforma seria preciso, antes, registrar essa plataforma no projeto '
    'espiritual-d2403 e rodar `flutterfire configure` na pasta do projeto, '
    'que reescreve este arquivo.\n\n'
    'Atenção: `ios/Runner/GoogleService-Info.plist` também é de exemplo, do '
    'projeto antigo `levitasync`, e precisa ser trocado no mesmo passo.';

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        throw UnsupportedError(_semProjeto('iOS'));
      case TargetPlatform.macOS:
        throw UnsupportedError(_semProjeto('macOS'));
      case TargetPlatform.windows:
        throw UnsupportedError(_semProjeto('Windows'));
      case TargetPlatform.linux:
        throw UnsupportedError(_semProjeto('Linux'));
      default:
        throw UnsupportedError(_semProjeto('esta plataforma'));
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCj8Sh0C3fuJx5XrA6Orny4_4YwavQknas',
    appId: '1:241914653758:android:96b37569e572f4acadf56f',
    messagingSenderId: '241914653758',
    projectId: 'espiritual-d2403',
    storageBucket: 'espiritual-d2403.firebasestorage.app',
  );
  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyCmC08W1DPC2xEKVGB0fF_EHeDrFxNwCwE',
    appId: '1:241914653758:web:2152e261d85fb083adf56f',
    messagingSenderId: '241914653758',
    projectId: 'espiritual-d2403',
    authDomain: 'espiritual-d2403.firebaseapp.com',
    storageBucket: 'espiritual-d2403.firebasestorage.app',
    measurementId: 'G-KK5FTPDM2Y',
  );
}
