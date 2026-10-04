import 'package:flutter/services.dart';

class WidgetSyncService {
  static const MethodChannel _channel =
      MethodChannel('com.workhours.tracker/widget_sync');

  static Future<bool> syncCredentials({
    required String baseUrl,
    required String deviceToken,
    bool vibrationsEnabled = true,
  }) async {
    try {
      final result = await _channel.invokeMethod<bool>('syncWidgetCredentials', {
        'baseUrl': baseUrl,
        'deviceToken': deviceToken,
        'vibrationsEnabled': vibrationsEnabled,
      });
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<Map<String, String>?> getWidgetCredentials() async {
    try {
      final result =
          await _channel.invokeMapMethod<String, String>('getWidgetCredentials');
      return result;
    } catch (_) {
      return null;
    }
  }

  static Future<void> vibrate() async {
    try {
      await _channel.invokeMethod('vibrate');
    } catch (_) {}
    try {
      await HapticFeedback.vibrate();
    } catch (_) {}
  }
}
