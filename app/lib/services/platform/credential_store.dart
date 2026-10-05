import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../config/app_config.dart';

abstract class SecureStorageGateway {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class DefaultSecureStorageGateway implements SecureStorageGateway {
  final FlutterSecureStorage _storage;
  const DefaultSecureStorageGateway([this._storage = const FlutterSecureStorage()]);

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

abstract class CredentialStore {
  bool get isWeb;
  String get defaultBaseUrl;
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class MobileCredentialStore implements CredentialStore {
  final SecureStorageGateway _storage;

  const MobileCredentialStore([this._storage = const DefaultSecureStorageGateway()]);

  @override
  bool get isWeb => false;

  @override
  String get defaultBaseUrl => AppConfig.defaultApiBaseUrl;

  @override
  Future<String?> read(String key) => _storage.read(key);

  @override
  Future<void> write(String key, String value) => _storage.write(key, value);

  @override
  Future<void> delete(String key) => _storage.delete(key);
}

class WebCredentialStore implements CredentialStore {
  final SecureStorageGateway _storage;
  String? _inMemoryAdminToken;

  WebCredentialStore([this._storage = const DefaultSecureStorageGateway()]);

  @override
  bool get isWeb => true;

  @override
  String get defaultBaseUrl => Uri.base.origin;

  @override
  Future<String?> read(String key) async {
    // Admin token is kept in-memory only during the active web session
    if (key == AppConfig.adminAuthTokenKey) {
      return _inMemoryAdminToken;
    }
    return _storage.read(key);
  }

  @override
  Future<void> write(String key, String value) async {
    // Never persist admin token to browser storage
    if (key == AppConfig.adminAuthTokenKey) {
      _inMemoryAdminToken = value;
      return;
    }
    return _storage.write(key, value);
  }

  @override
  Future<void> delete(String key) async {
    if (key == AppConfig.adminAuthTokenKey) {
      _inMemoryAdminToken = null;
      return;
    }
    return _storage.delete(key);
  }
}

final credentialStoreProvider = Provider<CredentialStore>((ref) {
  if (kIsWeb) {
    return WebCredentialStore();
  }
  return const MobileCredentialStore();
});
