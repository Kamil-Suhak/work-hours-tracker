import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:work_hours_mobile/features/settings/widget_sync_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.workhours.tracker/widget_sync');
  final List<MethodCall> log = [];

  setUp(() {
    log.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      log.add(methodCall);
      switch (methodCall.method) {
        case 'syncActiveNote':
          return true;
        case 'syncWidgetCredentials':
          return true;
        case 'getWidgetCredentials':
          return {
            'baseUrl': 'https://example.com',
            'deviceToken': 'test-token',
            'vibrationsEnabled': 'true',
          };
        case 'vibrate':
          return true;
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('WidgetSyncService Tests', () {
    test('syncActiveNote invokes native channel with note payload', () async {
      final success = await WidgetSyncService.syncActiveNote('Testing active shift note');

      expect(success, isTrue);
      expect(log, hasLength(1));
      expect(log.first.method, equals('syncActiveNote'));
      expect(log.first.arguments, equals({'note': 'Testing active shift note'}));
    });

    test('syncActiveNote returns false if method call throws', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        throw PlatformException(code: 'ERROR', message: 'Failed');
      });

      final success = await WidgetSyncService.syncActiveNote('Test note');
      expect(success, isFalse);
    });

    test('syncCredentials invokes native channel with credentials', () async {
      final success = await WidgetSyncService.syncCredentials(
        baseUrl: 'https://api.work.com',
        deviceToken: 'token123',
        vibrationsEnabled: false,
      );

      expect(success, isTrue);
      expect(log, hasLength(1));
      expect(log.first.method, equals('syncWidgetCredentials'));
      expect(log.first.arguments, equals({
        'baseUrl': 'https://api.work.com',
        'deviceToken': 'token123',
        'vibrationsEnabled': false,
      }));
    });

    test('getWidgetCredentials returns map from native channel', () async {
      final creds = await WidgetSyncService.getWidgetCredentials();

      expect(creds, isNotNull);
      expect(creds!['baseUrl'], equals('https://example.com'));
      expect(creds['deviceToken'], equals('test-token'));
    });

    test('vibrate invokes native vibration channel without error', () async {
      await WidgetSyncService.vibrate();

      expect(log.any((call) => call.method == 'vibrate'), isTrue);
    });
  });
}
