import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Stores router MQTT passwords outside SharedPreferences.
abstract class CredentialStore {
  Future<String?> read(String meshId);

  /// Returns false if the password could not be stored securely.
  Future<bool> write(String meshId, String password);

  Future<void> delete(String meshId);
}

/// Android Keystore-backed storage via `flutter_secure_storage`.
class SecureCredentialStore implements CredentialStore {
  SecureCredentialStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static String _key(String meshId) => 'router_mqtt_password.$meshId';

  @override
  Future<String?> read(String meshId) async {
    try {
      return await _storage.read(key: _key(meshId));
    } catch (e) {
      debugPrint('CredentialStore: read failed - $e');
      return null;
    }
  }

  @override
  Future<bool> write(String meshId, String password) async {
    try {
      await _storage.write(key: _key(meshId), value: password);
      return await _storage.read(key: _key(meshId)) == password;
    } catch (e) {
      debugPrint('CredentialStore: write failed - $e');
      return false;
    }
  }

  @override
  Future<void> delete(String meshId) async {
    try {
      await _storage.delete(key: _key(meshId));
    } catch (e) {
      debugPrint('CredentialStore: delete failed - $e');
    }
  }
}

/// In-memory store for tests.
class MemoryCredentialStore implements CredentialStore {
  final values = <String, String>{};
  bool failWrites = false;

  @override
  Future<String?> read(String meshId) async => values[meshId];

  @override
  Future<bool> write(String meshId, String password) async {
    if (failWrites) return false;
    values[meshId] = password;
    return true;
  }

  @override
  Future<void> delete(String meshId) async => values.remove(meshId);
}
