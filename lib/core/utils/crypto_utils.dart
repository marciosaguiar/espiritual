import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

/// Random identifiers.
///
/// Password hashing used to live here (PBKDF2 over a per-user salt). It was
/// removed when sign-in moved to Firebase Authentication: the password now
/// never reaches this app's code, and no hash is stored in Firestore.
class CryptoUtils {
  static final Random _random = Random.secure();

  /// Random, collision-safe id.
  ///
  /// An earlier version derived ids from the clock, so two records created in
  /// the same microsecond collided.
  static String generateId() {
    return base64Url.encode(_randomBytes(16)).replaceAll('=', '');
  }

  static Uint8List _randomBytes(int length) {
    final bytes = Uint8List(length);
    for (var i = 0; i < length; i++) {
      bytes[i] = _random.nextInt(256);
    }
    return bytes;
  }
}
