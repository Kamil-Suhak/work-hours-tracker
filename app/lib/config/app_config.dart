/// Central application configuration and constants.
///
/// Provides a single source of truth for compile-time environment defaults,
/// secure storage keys, platform method channels, and application metadata.
class AppConfig {
  const AppConfig._();

  // --- App Metadata ---
  static const String appName = 'Work Hours Tracker';
  static const String appVersion = '1.0.1';

  // --- API Configuration ---
  /// Default base URL for API communication.
  /// Can be overridden at build-time using `--dart-define=API_BASE_URL=https://...`.
  static const String defaultApiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://work-hours-api.workers.dev',
  );

  // --- Secure Storage Keys ---
  static const String deviceTokenKey = 'device_auth_token';
  static const String apiBaseUrlKey = 'api_base_url';
  static const String adminAuthTokenKey = 'admin_auth_token';
  static const String vibrationsEnabledKey = 'vibrations_enabled';
  static const String activeShiftNoteKey = 'active_shift_note';
  static const String legacyPersistedNotesKey = 'local_persisted_shift_notes';

  // --- Platform Method Channels ---
  static const String widgetSyncChannel = 'com.workhours.tracker/widget_sync';

  // --- Reports Configuration ---
  static const String defaultReportFilename = 'work-hours-report.xlsx';
  static const String reportMimeType =
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

  // --- UX & Timing Defaults ---
  static const Duration undoGracePeriod = Duration(minutes: 5);
}
