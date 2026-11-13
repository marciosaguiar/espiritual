// IMPORTANT: Replace the values below with your actual Firebase project configuration.
// To set up Firebase:
// 1. Go to https://console.firebase.google.com/
// 2. Create a project called "LevitaSync"
// 3. Add an Android and iOS app
// 4. Download google-services.json and GoogleService-Info.plist
// 5. Run: dart pub global activate flutterfire_cli && flutterfire configure
// 6. Or manually replace the placeholder values below

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for windows - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  // ⚠️ REPLACE WITH YOUR FIREBASE CONFIG ⚠️

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCj8Sh0C3fuJx5XrA6Orny4_4YwavQknas',
    appId: '1:241914653758:android:96b37569e572f4acadf56f',
    messagingSenderId: '241914653758',
    projectId: 'espiritual-d2403',
    storageBucket: 'espiritual-d2403.firebasestorage.app',
  );
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'YOUR_IOS_API_KEY',
    appId: '1:000000000000:ios:0000000000000000000000',
    messagingSenderId: '000000000000',
    projectId: 'levitasync',
    storageBucket: 'levitasync.appspot.com',
    iosBundleId: 'com.levitasync.app',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'YOUR_MACOS_API_KEY',
    appId: '1:000000000000:ios:0000000000000000000000',
    messagingSenderId: '000000000000',
    projectId: 'levitasync',
    storageBucket: 'levitasync.appspot.com',
    iosBundleId: 'com.levitasync.app',
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
