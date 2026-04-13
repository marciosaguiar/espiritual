import 'dart:convert';
import 'package:crypto/crypto.dart';

class CryptoUtils {
  /// Hash password using SHA-256
  static String hashPassword(String password) {
    final bytes = utf8.encode(password);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Verify password against hash
  static bool verifyPassword(String password, String hash) {
    return hashPassword(password) == hash;
  }

  /// Generate a simple UUID-like ID
  static String generateId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    final random = DateTime.now().microsecond.toString();
    final combined = '$timestamp$random';
    final bytes = utf8.encode(combined);
    final digest = sha256.convert(bytes);
    return digest.toString().substring(0, 20);
  }
}
