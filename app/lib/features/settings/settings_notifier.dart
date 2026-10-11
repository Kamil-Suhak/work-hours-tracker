import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/app_config.dart';
import '../../services/platform/platform_services.dart';

const String defaultApiBaseUrl = AppConfig.defaultApiBaseUrl;

class AppSettings {
  final String baseUrl;
  final String deviceToken;
  final String? adminToken;
  final bool isConfigured;
  final bool vibrationsEnabled;
  final int shiftReminderMinutes;
  final String environment;
  final String? stagingUrl;
  final String? stagingToken;

  const AppSettings({
    required this.baseUrl,
    required this.deviceToken,
    this.adminToken,
    required this.isConfigured,
    this.vibrationsEnabled = true,
    this.shiftReminderMinutes = 0,
    this.environment = 'production',
    this.stagingUrl,
    this.stagingToken,
  });

  AppSettings copyWith({
    String? baseUrl,
    String? deviceToken,
    String? adminToken,
    bool? isConfigured,
    bool? vibrationsEnabled,
    int? shiftReminderMinutes,
    String? environment,
    String? stagingUrl,
    String? stagingToken,
  }) {
    return AppSettings(
      baseUrl: baseUrl ?? this.baseUrl,
      deviceToken: deviceToken ?? this.deviceToken,
      adminToken: adminToken ?? this.adminToken,
      isConfigured: isConfigured ?? this.isConfigured,
      vibrationsEnabled: vibrationsEnabled ?? this.vibrationsEnabled,
      shiftReminderMinutes: shiftReminderMinutes ?? this.shiftReminderMinutes,
      environment: environment ?? this.environment,
      stagingUrl: stagingUrl ?? this.stagingUrl,
      stagingToken: stagingToken ?? this.stagingToken,
    );
  }
}

class SettingsNotifier extends AsyncNotifier<AppSettings> {
  static const String _tokenStorageKey = AppConfig.deviceTokenKey;
  static const String _baseUrlStorageKey = AppConfig.apiBaseUrlKey;
  static const String _adminTokenStorageKey = AppConfig.adminAuthTokenKey;
  static const String _hapticsStorageKey = AppConfig.vibrationsEnabledKey;
  static const String _reminderStorageKey = AppConfig.shiftReminderMinutesKey;
  static const String _envStorageKey = AppConfig.environmentKey;
  static const String _stagingUrlStorageKey = AppConfig.stagingUrlKey;
  static const String _stagingTokenStorageKey = AppConfig.stagingTokenKey;

  @override
  Future<AppSettings> build() async {
    final store = ref.read(credentialStoreProvider);
    final widgetSync = ref.read(widgetSyncServiceProvider);

    final storedUrl = await store.read(_baseUrlStorageKey);
    final storedToken = await store.read(_tokenStorageKey);
    final storedAdminToken = await store.read(_adminTokenStorageKey);
    final storedHaptics = await store.read(_hapticsStorageKey);
    final storedReminder = await store.read(_reminderStorageKey);
    final storedEnv = await store.read(_envStorageKey);
    final storedStagingUrl = await store.read(_stagingUrlStorageKey);
    final storedStagingToken = await store.read(_stagingTokenStorageKey);

    final defaultUrl = store.defaultBaseUrl;

    final isDefaultPlaceholder = storedUrl?.trim() == defaultApiBaseUrl;
    final baseUrl = (storedUrl != null &&
            storedUrl.trim().isNotEmpty &&
            (!store.isWeb || !isDefaultPlaceholder))
        ? storedUrl.trim()
        : defaultUrl;

    final deviceToken = storedToken?.trim() ?? '';
    final isConfigured =
        deviceToken.isNotEmpty && (store.isWeb || baseUrl != defaultApiBaseUrl);
    final vibrationsEnabled = storedHaptics != 'false';
    final shiftReminderMinutes = int.tryParse(storedReminder ?? '0') ?? 0;
    final environment = storedEnv?.trim().isNotEmpty == true ? storedEnv!.trim() : 'production';

    if (isConfigured) {
      await widgetSync.syncCredentials(
        baseUrl: baseUrl,
        deviceToken: deviceToken,
        vibrationsEnabled: vibrationsEnabled,
      );
    }

    return AppSettings(
      baseUrl: baseUrl,
      deviceToken: deviceToken,
      adminToken: storedAdminToken?.trim(),
      isConfigured: isConfigured,
      vibrationsEnabled: vibrationsEnabled,
      shiftReminderMinutes: shiftReminderMinutes,
      environment: environment,
      stagingUrl: storedStagingUrl?.trim(),
      stagingToken: storedStagingToken?.trim(),
    );
  }

  Future<void> saveSettings({
    required String baseUrl,
    required String deviceToken,
    String? adminToken,
    bool vibrationsEnabled = true,
    int shiftReminderMinutes = 0,
    String environment = 'production',
    String? stagingUrl,
    String? stagingToken,
  }) async {
    final store = ref.read(credentialStoreProvider);
    final widgetSync = ref.read(widgetSyncServiceProvider);

    var cleanedUrl = baseUrl.trim();
    if (cleanedUrl.endsWith('/')) {
      cleanedUrl = cleanedUrl.substring(0, cleanedUrl.length - 1);
    }
    final cleanedToken = deviceToken.trim();

    await store.write(_baseUrlStorageKey, cleanedUrl);
    await store.write(_tokenStorageKey, cleanedToken);
    if (adminToken != null && adminToken.trim().isNotEmpty) {
      await store.write(_adminTokenStorageKey, adminToken.trim());
    } else {
      await store.delete(_adminTokenStorageKey);
    }
    await store.write(_hapticsStorageKey, vibrationsEnabled.toString());
    await store.write(_reminderStorageKey, shiftReminderMinutes.toString());
    await store.write(_envStorageKey, environment);

    if (stagingUrl != null && stagingUrl.trim().isNotEmpty) {
      await store.write(_stagingUrlStorageKey, stagingUrl.trim());
    }
    if (stagingToken != null && stagingToken.trim().isNotEmpty) {
      await store.write(_stagingTokenStorageKey, stagingToken.trim());
    }

    await widgetSync.syncCredentials(
      baseUrl: cleanedUrl,
      deviceToken: cleanedToken,
      vibrationsEnabled: vibrationsEnabled,
    );

    state = AsyncValue.data(
      AppSettings(
        baseUrl: cleanedUrl,
        deviceToken: cleanedToken,
        adminToken: adminToken?.trim(),
        isConfigured:
            cleanedToken.isNotEmpty && (store.isWeb || cleanedUrl != defaultApiBaseUrl),
        vibrationsEnabled: vibrationsEnabled,
        shiftReminderMinutes: shiftReminderMinutes,
        environment: environment,
        stagingUrl: stagingUrl?.trim(),
        stagingToken: stagingToken?.trim(),
      ),
    );
  }

  Future<void> setSessionAdminToken(String token) async {
    final store = ref.read(credentialStoreProvider);
    final cleaned = token.trim();
    if (cleaned.isNotEmpty) {
      await store.write(_adminTokenStorageKey, cleaned);
    } else {
      await store.delete(_adminTokenStorageKey);
    }
    if (state.hasValue) {
      state = AsyncValue.data(
        state.value!.copyWith(adminToken: cleaned.isNotEmpty ? cleaned : null),
      );
    }
  }
}

final settingsProvider =
    AsyncNotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);
