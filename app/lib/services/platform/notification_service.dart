import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../api/models.dart';
import '../../config/app_config.dart';
import 'web_notification_service_stub.dart'
    if (dart.library.html) 'web_notification_service.dart';

/// Determines whether a target-reached notification should fire after polling
/// the server [status].
///
/// Fires when still clocked in, or when the server just auto-stopped the shift
/// at/after [targetEndTime] (truncated to minute). Does NOT fire if the user
/// already clocked out manually before [targetEndTime].
bool shouldFireTargetNotification(
  WorkStatus status,
  DateTime targetEndTime, {
  DateTime? now,
}) {
  if (status.isClockedIn) return true;
  final latest = status.latestEvent;
  if (latest == null || latest.eventType != 'clock_out') return false;

  final targetUtc = targetEndTime.toUtc();
  final targetMinuteUtc = DateTime.utc(
    targetUtc.year,
    targetUtc.month,
    targetUtc.day,
    targetUtc.hour,
    targetUtc.minute,
  );
  if (latest.occurredAtUtc.toUtc().isBefore(targetMinuteUtc)) {
    return false;
  }

  final createdAt = latest.createdAtUtc.toUtc();
  final refNow = (now ?? DateTime.now()).toUtc();
  return refNow.difference(createdAt).inMinutes.abs() <= 5;
}

abstract class NotificationService {
  Future<void> initialize();
  Future<bool> requestPermissions();
  Future<void> scheduleShiftReminder({
    required DateTime targetEndTime,
    required int minutesBefore,
  });
  Future<void> cancelShiftReminder();
  Future<void> scheduleTargetNotification({
    required DateTime targetEndTime,
    required Future<WorkStatus?> Function() checkStatus,
  });
  Future<void> cancelTargetNotification();
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

  @override
  Future<void> scheduleTargetNotification({
    required DateTime targetEndTime,
    required Future<WorkStatus?> Function() checkStatus,
  }) async {
    try {
      final hh = targetEndTime.hour.toString().padLeft(2, '0');
      final mm = targetEndTime.minute.toString().padLeft(2, '0');
      await _channel.invokeMethod('scheduleTargetNotification', {
        'triggerAtMillis': targetEndTime.millisecondsSinceEpoch,
        'targetUtcIso': targetEndTime.toUtc().toIso8601String(),
        'title': 'Clock-Out Target Reached',
        'body': 'Your planned clock-out target ($hh:$mm) has been reached.',
      });
    } catch (e) {
      debugPrint('Error scheduling target notification: $e');
    }
  }

  @override
  Future<void> cancelTargetNotification() async {
    try {
      await _channel.invokeMethod('cancelTargetNotification');
    } catch (e) {
      debugPrint('Error cancelling target notification: $e');
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

  @override
  Future<void> scheduleTargetNotification({
    required DateTime targetEndTime,
    required Future<WorkStatus?> Function() checkStatus,
  }) async {}

  @override
  Future<void> cancelTargetNotification() async {}
}

final notificationServiceProvider = Provider<NotificationService>((ref) {
  if (kIsWeb) {
    return createWebNotificationService();
  }
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
      return MethodChannelNotificationService();
    default:
      return const NoopNotificationService();
  }
});
