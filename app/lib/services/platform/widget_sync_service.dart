import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract class WidgetSyncService {
  Future<bool> syncCredentials({
    required String baseUrl,
    required String deviceToken,
    bool vibrationsEnabled = true,
  });
  Future<Map<String, String>?> getWidgetCredentials();
  Future<bool> syncActiveNote(String note);
}

class AndroidWidgetSyncService implements WidgetSyncService {
  static const MethodChannel _channel =
      MethodChannel('com.workhours.tracker/widget_sync');

  const AndroidWidgetSyncService();

  @override
  Future<bool> syncCredentials({
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

  @override
  Future<Map<String, String>?> getWidgetCredentials() async {
    try {
      final result =
          await _channel.invokeMapMethod<String, String>('getWidgetCredentials');
      return result;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> syncActiveNote(String note) async {
    try {
      final result = await _channel.invokeMethod<bool>('syncActiveNote', {
        'note': note,
      });
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> vibrate() async {
    try {
      await _channel.invokeMethod('vibrate');
    } catch (_) {}
  }
}

class NoOpWidgetSyncService implements WidgetSyncService {
  const NoOpWidgetSyncService();

  @override
  Future<bool> syncCredentials({
    required String baseUrl,
    required String deviceToken,
    bool vibrationsEnabled = true,
  }) async => true;

  @override
  Future<Map<String, String>?> getWidgetCredentials() async => null;

  @override
  Future<bool> syncActiveNote(String note) async => true;
}

final widgetSyncServiceProvider = Provider<WidgetSyncService>((ref) {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    return const AndroidWidgetSyncService();
  }
  return const NoOpWidgetSyncService();
});
