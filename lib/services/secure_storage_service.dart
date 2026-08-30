import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Stores credentials in the platform credential vault (Keychain/KeyStore).
///
/// The in-memory fallback is deliberately non-persistent. It keeps the app
/// usable in test environments or on a platform where a credential vault is
/// unavailable, without falling back to plaintext preferences.
class SecureStorageService {
  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static final Map<String, String> _volatileValues = <String, String>{};

  static Future<String?> read(String key) async {
    try {
      final value = await _storage.read(key: key);
      if (value != null) return value;
    } catch (_) {
      // A platform without a credential vault must never make us read a
      // plaintext fallback from SharedPreferences.
    }
    return _volatileValues[key];
  }

  /// Returns whether the value reached persistent secure storage.
  static Future<bool> write(String key, String value) async {
    _volatileValues[key] = value;
    try {
      await _storage.write(key: key, value: value);
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> delete(String key) async {
    _volatileValues.remove(key);
    try {
      await _storage.delete(key: key);
      return true;
    } catch (_) {
      return false;
    }
  }
}
