/// Central application configuration and constants.
///
/// Provides a single source of truth for compile-time environment defaults,
/// secure storage keys, platform method channels, and application metadata.
class AppConfig {
  const AppConfig._();

  // --- App Metadata ---
  static const String appName = 'Work Hours Tracker';
  static const String appVersion = '1.2.2';

  // --- API Configuration ---
  /// Default base URL for API communication.
  /// Can be overridden at build-time using `--dart-define=API_BASE_URL=https://...`.
  static const String defaultApiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://work-hours-api.kamilsuhak.workers.dev',
  );
  static const String stagingApiBaseUrl = String.fromEnvironment(
    'STAGING_API_BASE_URL',
    defaultValue: 'https://work-hours-api-staging.kamilsuhak.workers.dev',
  );

  // --- Secure Storage Keys ---
  static const String deviceTokenKey = 'device_auth_token';
  static const String apiBaseUrlKey = 'api_base_url';
  static const String prodDeviceTokenKey = 'prod_device_auth_token';
  static const String prodApiBaseUrlKey = 'prod_api_base_url';
  static const String adminAuthTokenKey = 'admin_auth_token';
  static const String vibrationsEnabledKey = 'vibrations_enabled';
  static const String activeShiftNoteKey = 'active_shift_note';
  static const String legacyPersistedNotesKey = 'local_persisted_shift_notes';
  static const String plannedShiftMinutesKey = 'planned_shift_minutes';
  static const String shiftReminderMinutesKey = 'shift_reminder_minutes';
  static const String environmentKey = 'selected_environment';
  static const String stagingTokenKey = 'staging_device_auth_token';
  static const String stagingUrlKey = 'staging_api_base_url';
  static const String prodAdminTokenKey = 'prod_admin_auth_token';
  static const String stagingAdminTokenKey = 'staging_admin_auth_token';
  static const String prodShiftReminderKey = 'prod_shift_reminder_minutes';
  static const String stagingShiftReminderKey = 'staging_shift_reminder_minutes';
  static const String prodVibrationsKey = 'prod_vibrations_enabled';
  static const String stagingVibrationsKey = 'staging_vibrations_enabled';

  // --- Platform Method Channels ---
  static const String widgetSyncChannel = 'com.workhours.tracker/widget_sync';
  static const String notificationChannel = 'com.workhours.tracker/notifications';

  // --- Reports Configuration ---
  static const String defaultReportFilename = 'work-hours-report.xlsx';
  static const String reportMimeType =
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
  static const String docxMimeType =
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document';

  static String mimeTypeForFilename(String filename) {
    return filename.toLowerCase().endsWith('.docx')
        ? docxMimeType
        : reportMimeType;
  }

  // --- UX & Timing Defaults ---
  static const Duration undoGracePeriod = Duration(minutes: 5);
}
