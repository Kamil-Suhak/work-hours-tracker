import '../../services/platform/platform_services.dart';

/// Backward-compatibility shim that delegates to platform services.
/// Prefer injecting [widgetSyncServiceProvider] and [hapticServiceProvider] via Riverpod.
class WidgetSyncService {
  static const AndroidWidgetSyncService _delegate = AndroidWidgetSyncService();
  static const MobileHapticService _haptic = MobileHapticService();

  static Future<bool> syncCredentials({
    required String baseUrl,
    required String deviceToken,
    bool vibrationsEnabled = true,
  }) =>
      _delegate.syncCredentials(
        baseUrl: baseUrl,
        deviceToken: deviceToken,
        vibrationsEnabled: vibrationsEnabled,
      );

  static Future<Map<String, String>?> getWidgetCredentials() =>
      _delegate.getWidgetCredentials();

  static Future<bool> syncActiveNote(String note) =>
      _delegate.syncActiveNote(note);

  static Future<void> vibrate() async {
    await _delegate.vibrate();
    await _haptic.vibrate();
  }
}
