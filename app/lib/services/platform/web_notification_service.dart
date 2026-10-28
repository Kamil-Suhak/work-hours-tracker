// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:async';
import 'dart:html' as html;
import 'package:flutter/foundation.dart';
import 'notification_service.dart';

NotificationService createWebNotificationService() => WebNotificationService();

class WebNotificationService implements NotificationService {
  Timer? _reminderTimer;

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> requestPermissions() async {
    try {
      if (!html.Notification.supported) return false;
      final permission = await html.Notification.requestPermission();
      return permission == 'granted';
    } catch (e) {
      debugPrint('Web notification permission error: $e');
      return false;
    }
  }

  @override
  Future<void> scheduleShiftReminder({
    required DateTime targetEndTime,
    required int minutesBefore,
  }) async {
    await cancelShiftReminder();
    final triggerTime =
        targetEndTime.subtract(Duration(minutes: minutesBefore));
    final now = DateTime.now();
    final durationUntilTrigger = triggerTime.difference(now);

    if (durationUntilTrigger.isNegative) {
      // If the trigger time is already in the past, but the shift hasn't ended yet
      if (now.isBefore(targetEndTime)) {
        _showWebNotification(
          'Shift Ending Soon',
          'Your planned shift ends in less than $minutesBefore minutes. Don\'t forget to clock out!',
        );
      }
      return;
    }

    _reminderTimer = Timer(durationUntilTrigger, () {
      _showWebNotification(
        'Shift Ending Soon',
        'Your planned shift ends in $minutesBefore minutes. Don\'t forget to clock out!',
      );
    });
  }

  @override
  Future<void> cancelShiftReminder() async {
    _reminderTimer?.cancel();
    _reminderTimer = null;
  }

  void _showWebNotification(String title, String body) {
    try {
      if (html.Notification.supported &&
          html.Notification.permission == 'granted') {
        html.Notification(
          title,
          body: body,
          icon: 'favicon.png',
        );
      }
    } catch (e) {
      debugPrint('Error displaying web notification: $e');
    }
  }
}
