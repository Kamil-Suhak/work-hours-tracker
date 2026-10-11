import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/app_config.dart';

abstract class NotificationService {
  Future<void> initialize();
  Future<bool> requestPermissions();
  Future<void> scheduleShiftReminder({
    required DateTime targetEndTime,
    required int minutesBefore,
  });
  Future<void> cancelShiftReminder();
}

class MethodChannelNotificationService implements NotificationService {
  static const MethodChannel _channel =
      MethodChannel(AppConfig.notificationChannel);

  @override
  Future<void> initialize() async {
    try {
      await _channel.invokeMethod('initialize');
    } catch (_) {}
  }

  @override
  Future<bool> requestPermissions() async {
    try {
      final granted =
          await _channel.invokeMethod<bool>('requestPermissions');
      return granted ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> scheduleShiftReminder({
    required DateTime targetEndTime,
    required int minutesBefore,
  }) async {
    try {
      final triggerTime =
          targetEndTime.subtract(Duration(minutes: minutesBefore));
      await _channel.invokeMethod('scheduleReminder', {
        'triggerAtMillis': triggerTime.millisecondsSinceEpoch,
        'minutesBefore': minutesBefore,
        'title': 'Shift Ending Soon',
        'body': 'Your planned shift ends in $minutesBefore minutes. Don\'t forget to clock out!',
      });
    } catch (e) {
      debugPrint('Error scheduling shift reminder: $e');
    }
  }

  @override
  Future<void> cancelShiftReminder() async {
    try {
      await _channel.invokeMethod('cancelReminder');
    } catch (e) {
      debugPrint('Error cancelling shift reminder: $e');
    }
  }
}

class NoopNotificationService implements NotificationService {
  const NoopNotificationService();

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> requestPermissions() async => true;

  @override
  Future<void> scheduleShiftReminder({
    required DateTime targetEndTime,
    required int minutesBefore,
  }) async {}

  @override
  Future<void> cancelShiftReminder() async {}
}

final notificationServiceProvider = Provider<NotificationService>((ref) {
  if (kIsWeb) {
    return const NoopNotificationService();
  }
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
      return MethodChannelNotificationService();
    default:
      return const NoopNotificationService();
  }
});
