import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class WidgetSyncService {
  static const MethodChannel _channel =
      MethodChannel('com.workhours.tracker/widget_sync');

  static bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<bool> syncCredentials({
    required String baseUrl,
    required String deviceToken,
    bool vibrationsEnabled = true,
  }) async {
    if (!_isAndroid) return true;
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
    if (!_isAndroid) return null;
    try {
      final result =
          await _channel.invokeMapMethod<String, String>('getWidgetCredentials');
      return result;
    } catch (_) {
      return null;
    }
  }

  static Future<bool> syncActiveNote(String note) async {
    if (!_isAndroid) return true;
    try {
      final result = await _channel.invokeMethod<bool>('syncActiveNote', {
        'note': note,
      });
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> vibrate() async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod('vibrate');
    } catch (_) {}
    try {
      await HapticFeedback.vibrate();
    } catch (_) {}
  }
}
