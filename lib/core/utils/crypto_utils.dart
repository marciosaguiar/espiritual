import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Password hashing and id generation.
///
/// Passwords use PBKDF2-HMAC-SHA256 with a per-user random salt. The previous
/// scheme was a bare SHA-256 digest: no salt, and fast enough that common
/// six-character passwords fall in seconds if the user list ever leaks. Old
/// hashes are still accepted and are upgraded silently the next time the
/// person signs in — see [needsUpgrade].
///
/// Note on the limits of this design: the app checks the password on the
/// device, so the stored hash has to be readable by the app. PBKDF2 protects
/// the *typed password* (which people reuse elsewhere), but anyone able to
/// read the database can still impersonate an account inside this app. Closing
/// that gap requires checking the password on a server.
class CryptoUtils {
  /// Cost factor. Runs off the UI thread (see [hashPasswordWorker]), so a
  /// second of work is acceptable; raise it as phones get faster.
  static const int _iterations = 60000;
  static const int _saltBytes = 16;
  static const int _keyBytes = 32;
  static const String _prefix = 'pbkdf2';

  static final Random _random = Random.secure();

  /// Hashes [password] with a fresh random salt.
  ///
  /// Returns `pbkdf2$<iterations>$<salt>$<hash>`, so the cost factor can be
  /// raised later without invalidating existing passwords.
  static String hashPassword(String password) {
    final salt = _randomBytes(_saltBytes);
    final key = _pbkdf2(utf8.encode(password), salt, _iterations, _keyBytes);
    return '$_prefix\$$_iterations\$${base64.encode(salt)}\$${base64.encode(key)}';
  }

  /// Checks [password] against [stored], accepting both the current format and
  /// the legacy bare SHA-256 digest.
  static bool verifyPassword(String password, String stored) {
    if (stored.isEmpty) return false;

    if (!stored.startsWith('$_prefix\$')) {
      // Legacy: hex SHA-256 of the password, no salt.
      return _constantTimeEquals(
        utf8.encode(sha256.convert(utf8.encode(password)).toString()),
        utf8.encode(stored),
      );
    }

    final parts = stored.split('\$');
    if (parts.length != 4) return false;

    final iterations = int.tryParse(parts[1]);
    if (iterations == null || iterations <= 0) return false;

    try {
      final salt = base64.decode(parts[2]);
      final expected = base64.decode(parts[3]);
      final actual =
          _pbkdf2(utf8.encode(password), salt, iterations, expected.length);
      return _constantTimeEquals(expected, actual);
    } catch (_) {
      return false;
    }
  }

  /// Whether [stored] should be re-hashed after a successful sign-in, either
  /// because it uses the legacy scheme or a weaker cost factor.
  static bool needsUpgrade(String stored) {
    if (!stored.startsWith('$_prefix\$')) return true;
    final parts = stored.split('\$');
    if (parts.length != 4) return true;
    final iterations = int.tryParse(parts[1]) ?? 0;
    return iterations < _iterations;
  }

  /// Random, collision-safe id.
  ///
  /// The previous version derived ids from the clock, so two records created
  /// in the same microsecond collided.
  static String generateId() {
    return base64Url.encode(_randomBytes(16)).replaceAll('=', '');
  }

  // ─── internals ────────────────────────────────────────────────────────────

  static Uint8List _randomBytes(int length) {
    final bytes = Uint8List(length);
    for (var i = 0; i < length; i++) {
      bytes[i] = _random.nextInt(256);
    }
    return bytes;
  }

  /// PBKDF2 as described in RFC 8018, with HMAC-SHA256 as the pseudorandom
  /// function.
  static Uint8List _pbkdf2(
    List<int> password,
    List<int> salt,
    int iterations,
    int keyLength,
  ) {
    final hmac = Hmac(sha256, password);
    final output = BytesBuilder();
    var block = 1;

    while (output.length < keyLength) {
      final counter = Uint8List(4)
        ..buffer.asByteData().setUint32(0, block, Endian.big);

      var u = Uint8List.fromList(
        hmac.convert(<int>[...salt, ...counter]).bytes,
      );
      final result = Uint8List.fromList(u);

      for (var i = 1; i < iterations; i++) {
        u = Uint8List.fromList(hmac.convert(u).bytes);
        for (var j = 0; j < result.length; j++) {
          result[j] ^= u[j];
        }
      }

      output.add(result);
      block++;
    }

    return Uint8List.fromList(output.takeBytes().sublist(0, keyLength));
  }

  /// Comparison that does not stop at the first differing byte.
  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}

/// Entry points for `compute`, so hashing runs off the UI thread and the app
/// does not freeze for a second while signing in.
String hashPasswordWorker(String password) => CryptoUtils.hashPassword(password);

bool verifyPasswordWorker(List<String> passwordAndHash) =>
    CryptoUtils.verifyPassword(passwordAndHash[0], passwordAndHash[1]);
