import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:work_hours_mobile/config/app_config.dart';
import 'package:work_hours_mobile/services/platform/notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NotificationService Tests', () {
    test('MethodChannelNotificationService invokes initialize, requestPermissions, scheduleReminder, cancelReminder', () async {
      final List<MethodCall> calls = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel(AppConfig.notificationChannel),
        (MethodCall call) async {
          calls.add(call);
          if (call.method == 'requestPermissions') return true;
          return null;
        },
      );

      final service = MethodChannelNotificationService();
      await service.initialize();
      expect(calls.any((c) => c.method == 'initialize'), isTrue);

      final granted = await service.requestPermissions();
      expect(granted, isTrue);
      expect(calls.any((c) => c.method == 'requestPermissions'), isTrue);

      final targetTime = DateTime.now().add(const Duration(hours: 1));
      await service.scheduleShiftReminder(
        targetEndTime: targetTime,
        minutesBefore: 15,
      );
      final scheduleCall = calls.firstWhere((c) => c.method == 'scheduleReminder');
      expect(scheduleCall.arguments['minutesBefore'], 15);
      expect(scheduleCall.arguments['title'], 'Shift Ending Soon');

      await service.cancelShiftReminder();
      expect(calls.any((c) => c.method == 'cancelReminder'), isTrue);
    });

    test('notificationServiceProvider provides a non-null service', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final service = container.read(notificationServiceProvider);
      expect(service, isNotNull);
    });
  });
}
