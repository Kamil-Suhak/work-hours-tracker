import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:work_hours_mobile/services/platform/platform_services.dart';

class _FakeSecureStorageGateway implements SecureStorageGateway {
  final Map<String, String> _data = {};

  @override
  Future<String?> read(String key) async => _data[key];

  @override
  Future<void> write(String key, String value) async {
    _data[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _data.remove(key);
  }

  bool containsKey(String key) => _data.containsKey(key);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('HapticFeedbackService Tests', () {
    test('MobileHapticService reports isSupported true', () {
      const service = MobileHapticService();
      expect(service.isSupported, isTrue);
    });

    test('WebHapticService reports isSupported false and performs no-ops', () async {
      const service = WebHapticService();
      expect(service.isSupported, isFalse);
      await service.lightImpact();
      await service.mediumImpact();
      await service.vibrate();
    });
  });

  group('ReportFileService Tests', () {
    test('NoOpReportFileService returns null for save and false for open', () async {
      const service = NoOpReportFileService();
      final saveResult = await service.saveAndOpenReport(
        bytes: Uint8List.fromList([1, 2, 3]),
        filename: 'report.xlsx',
      );
      expect(saveResult, isNull);

      final openResult = await service.openReportFile('/path/report.xlsx');
      expect(openResult, isFalse);
    });
  });

  group('WidgetSyncService Tests', () {
    test('NoOpWidgetSyncService returns true for sync and null for credentials', () async {
      const service = NoOpWidgetSyncService();
      final syncResult = await service.syncCredentials(
        baseUrl: 'https://api.work.com',
        deviceToken: 'token-123',
      );
      expect(syncResult, isTrue);

      final creds = await service.getWidgetCredentials();
      expect(creds, isNull);

      final noteResult = await service.syncActiveNote('Note');
      expect(noteResult, isTrue);
    });
  });

  group('CredentialStore Security Tests', () {
    test('WebCredentialStore keeps admin_auth_token in memory only', () async {
      final fakeStorage = _FakeSecureStorageGateway();
      final store = WebCredentialStore(fakeStorage);

      expect(store.isWeb, isTrue);

      // 1. Write device token -> should be written to storage
      await store.write('device_auth_token', 'dev-token-abc');
      expect(await store.read('device_auth_token'), equals('dev-token-abc'));
      expect(fakeStorage.containsKey('device_auth_token'), isTrue);

      // 2. Write admin token -> MUST NOT be written to storage (in-memory only)
      await store.write('admin_auth_token', 'super-secret-admin');
      expect(await store.read('admin_auth_token'), equals('super-secret-admin'));
      expect(fakeStorage.containsKey('admin_auth_token'), isFalse);

      // 3. Delete admin token clears in-memory state
      await store.delete('admin_auth_token');
      expect(await store.read('admin_auth_token'), isNull);
    });

    test('MobileCredentialStore persists both tokens to storage', () async {
      final fakeStorage = _FakeSecureStorageGateway();
      final store = MobileCredentialStore(fakeStorage);

      expect(store.isWeb, isFalse);

      await store.write('device_auth_token', 'dev-token-123');
      await store.write('admin_auth_token', 'admin-token-456');

      expect(fakeStorage.containsKey('device_auth_token'), isTrue);
      expect(fakeStorage.containsKey('admin_auth_token'), isTrue);
    });
  });
}
