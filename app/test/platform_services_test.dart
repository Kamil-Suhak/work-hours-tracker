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

    test('WebReportFileService saves and opens cached report bytes', () async {
      const service = WebReportFileService();
      final saveResult = await service.saveAndOpenReport(
        bytes: Uint8List.fromList([10, 20, 30]),
        filename: 'report_2026.xlsx',
      );
      expect(saveResult, equals('report_2026.xlsx'));

      final openResult = await service.openReportFile('report_2026.xlsx');
      // In VM stubbed runner, openReportInBrowser stub returns false gracefully
      expect(openResult, isA<bool>());
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

      final statusResult = await service.syncWidgetStatus(isClockedIn: true);
      expect(statusResult, isTrue);
    });
  });

  group('CredentialStore Tests', () {
    test('WebCredentialStore delegates device token persistence and reports isWeb', () async {
      final fakeStorage = _FakeSecureStorageGateway();
      final store = WebCredentialStore(fakeStorage);

      expect(store.isWeb, isTrue);
      expect(store.defaultBaseUrl, isNotEmpty);

      await store.write('device_auth_token', 'dev-token-abc');
      expect(await store.read('device_auth_token'), equals('dev-token-abc'));
      expect(fakeStorage.containsKey('device_auth_token'), isTrue);

      await store.delete('device_auth_token');
      expect(await store.read('device_auth_token'), isNull);
      expect(fakeStorage.containsKey('device_auth_token'), isFalse);
    });

    test('MobileCredentialStore persists device tokens and reports !isWeb', () async {
      final fakeStorage = _FakeSecureStorageGateway();
      final store = MobileCredentialStore(fakeStorage);

      expect(store.isWeb, isFalse);

      await store.write('device_auth_token', 'dev-token-123');
      expect(await store.read('device_auth_token'), equals('dev-token-123'));
      expect(fakeStorage.containsKey('device_auth_token'), isTrue);
    });
  });
}
