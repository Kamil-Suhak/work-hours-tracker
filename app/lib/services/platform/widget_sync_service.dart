import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/app_config.dart';

abstract class WidgetSyncService {
  Future<bool> syncCredentials({
    required String baseUrl,
    required String deviceToken,
    bool vibrationsEnabled = true,
  });
  Future<Map<String, String>?> getWidgetCredentials();
  Future<bool> syncActiveNote(String note);
  Future<bool> syncWidgetStatus({
    required bool isClockedIn,
    String? activeNote,
    String? syncTime,
  });
}

class AndroidWidgetSyncService implements WidgetSyncService {
  static const MethodChannel _channel =
      MethodChannel(AppConfig.widgetSyncChannel);

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

  @override
  Future<bool> syncWidgetStatus({
    required bool isClockedIn,
    String? activeNote,
    String? syncTime,
  }) async {
    try {
      final result = await _channel.invokeMethod<bool>('syncWidgetStatus', {
        'isClockedIn': isClockedIn,
        if (activeNote != null) 'activeNote': activeNote,
        if (syncTime != null) 'syncTime': syncTime,
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

  @override
  Future<bool> syncWidgetStatus({
    required bool isClockedIn,
    String? activeNote,
    String? syncTime,
  }) async => true;
}

final widgetSyncServiceProvider = Provider<WidgetSyncService>((ref) {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    return const AndroidWidgetSyncService();
  }
  return const NoOpWidgetSyncService();
});
