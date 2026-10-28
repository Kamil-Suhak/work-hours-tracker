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
  final String prodUrl;
  final String prodToken;
  final String? prodAdminToken;
  final int prodReminderMinutes;
  final bool prodVibrationsEnabled;
  final String stagingUrl;
  final String stagingToken;
  final String? stagingAdminToken;
  final int stagingReminderMinutes;
  final bool stagingVibrationsEnabled;

  const AppSettings({
    required this.baseUrl,
    required this.deviceToken,
    this.adminToken,
    required this.isConfigured,
    this.vibrationsEnabled = true,
    this.shiftReminderMinutes = 0,
    this.environment = 'production',
    this.prodUrl = AppConfig.defaultApiBaseUrl,
    this.prodToken = '',
    this.prodAdminToken,
    this.prodReminderMinutes = 0,
    this.prodVibrationsEnabled = true,
    this.stagingUrl = AppConfig.stagingApiBaseUrl,
    this.stagingToken = '',
    this.stagingAdminToken,
    this.stagingReminderMinutes = 0,
    this.stagingVibrationsEnabled = true,
  });

  AppSettings copyWith({
    String? baseUrl,
    String? deviceToken,
    String? adminToken,
    bool? isConfigured,
    bool? vibrationsEnabled,
    int? shiftReminderMinutes,
    String? environment,
    String? prodUrl,
    String? prodToken,
    String? prodAdminToken,
    int? prodReminderMinutes,
    bool? prodVibrationsEnabled,
    String? stagingUrl,
    String? stagingToken,
    String? stagingAdminToken,
    int? stagingReminderMinutes,
    bool? stagingVibrationsEnabled,
  }) {
    return AppSettings(
      baseUrl: baseUrl ?? this.baseUrl,
      deviceToken: deviceToken ?? this.deviceToken,
      adminToken: adminToken ?? this.adminToken,
      isConfigured: isConfigured ?? this.isConfigured,
      vibrationsEnabled: vibrationsEnabled ?? this.vibrationsEnabled,
      shiftReminderMinutes: shiftReminderMinutes ?? this.shiftReminderMinutes,
      environment: environment ?? this.environment,
      prodUrl: prodUrl ?? this.prodUrl,
      prodToken: prodToken ?? this.prodToken,
      prodAdminToken: prodAdminToken ?? this.prodAdminToken,
      prodReminderMinutes: prodReminderMinutes ?? this.prodReminderMinutes,
      prodVibrationsEnabled:
          prodVibrationsEnabled ?? this.prodVibrationsEnabled,
      stagingUrl: stagingUrl ?? this.stagingUrl,
      stagingToken: stagingToken ?? this.stagingToken,
      stagingAdminToken: stagingAdminToken ?? this.stagingAdminToken,
      stagingReminderMinutes:
          stagingReminderMinutes ?? this.stagingReminderMinutes,
      stagingVibrationsEnabled:
          stagingVibrationsEnabled ?? this.stagingVibrationsEnabled,
    );
  }
}

class SettingsNotifier extends AsyncNotifier<AppSettings> {
  static const String _tokenStorageKey = AppConfig.deviceTokenKey;
  static const String _baseUrlStorageKey = AppConfig.apiBaseUrlKey;
  static const String _prodTokenStorageKey = AppConfig.prodDeviceTokenKey;
  static const String _prodUrlStorageKey = AppConfig.prodApiBaseUrlKey;
  static const String _adminTokenStorageKey = AppConfig.adminAuthTokenKey;
  static const String _hapticsStorageKey = AppConfig.vibrationsEnabledKey;
  static const String _reminderStorageKey = AppConfig.shiftReminderMinutesKey;
  static const String _envStorageKey = AppConfig.environmentKey;
  static const String _stagingUrlStorageKey = AppConfig.stagingUrlKey;
  static const String _stagingTokenStorageKey = AppConfig.stagingTokenKey;

  static const String _legacyGenericWorkersDevUrl =
      'https://work-hours-api.workers.dev';

  @override
  Future<AppSettings> build() async {
    final store = ref.read(credentialStoreProvider);
    final widgetSync = ref.read(widgetSyncServiceProvider);

    final storedProdUrl = await store.read(_prodUrlStorageKey);
    final storedProdToken = await store.read(_prodTokenStorageKey);
    final storedUrl = await store.read(_baseUrlStorageKey);
    final storedToken = await store.read(_tokenStorageKey);
    final storedAdminToken = await store.read(_adminTokenStorageKey);
    final storedHaptics = await store.read(_hapticsStorageKey);
    final storedReminder = await store.read(_reminderStorageKey);
    final storedEnv = await store.read(_envStorageKey);
    final storedStagingToken = await store.read(_stagingTokenStorageKey);

    final defaultUrl = store.defaultBaseUrl;

    // Resolve production base URL with legacy fallback and migration away from generic worker domain
    String prodUrl = (storedProdUrl != null &&
            storedProdUrl.trim().isNotEmpty &&
            storedProdUrl.trim() != _legacyGenericWorkersDevUrl)
        ? storedProdUrl.trim()
        : ((storedUrl != null &&
                storedUrl.trim().isNotEmpty &&
                storedUrl.trim() != _legacyGenericWorkersDevUrl)
            ? storedUrl.trim()
            : defaultUrl);

    if (prodUrl.isEmpty || prodUrl == _legacyGenericWorkersDevUrl) {
      prodUrl = AppConfig.defaultApiBaseUrl;
    }

    final storedProdAdminToken = await store.read(AppConfig.prodAdminTokenKey);
    final storedStagingAdminToken = await store.read(AppConfig.stagingAdminTokenKey);
    final storedProdReminder = await store.read(AppConfig.prodShiftReminderKey);
    final storedStagingReminder = await store.read(AppConfig.stagingShiftReminderKey);
    final storedProdVibrations = await store.read(AppConfig.prodVibrationsKey);
    final storedStagingVibrations = await store.read(AppConfig.stagingVibrationsKey);

    final prodAdminToken = storedProdAdminToken?.trim() ?? storedAdminToken?.trim();
    final stagingAdminToken = storedStagingAdminToken?.trim();

    final prodReminderMinutes =
        int.tryParse(storedProdReminder ?? storedReminder ?? '0') ?? 0;
    final stagingReminderMinutes =
        int.tryParse(storedStagingReminder ?? '0') ?? 0;

    final prodVibrationsEnabled =
        (storedProdVibrations ?? storedHaptics) != 'false';
    final stagingVibrationsEnabled = storedStagingVibrations != 'false';

    final prodToken = (storedProdToken != null && storedProdToken.trim().isNotEmpty)
        ? storedProdToken.trim()
        : (storedToken?.trim() ?? '');

    const stagingUrl = AppConfig.stagingApiBaseUrl;
    final stagingToken = storedStagingToken?.trim() ?? '';
    final environment =
        (storedEnv?.trim() == 'staging') ? 'staging' : 'production';

    final activeUrl = environment == 'staging' ? stagingUrl : prodUrl;
    final activeToken = environment == 'staging' ? stagingToken : prodToken;
    final activeAdminToken =
        environment == 'staging' ? stagingAdminToken : prodAdminToken;
    final activeReminderMinutes =
        environment == 'staging' ? stagingReminderMinutes : prodReminderMinutes;
    final activeVibrationsEnabled =
        environment == 'staging' ? stagingVibrationsEnabled : prodVibrationsEnabled;

    final isConfigured = activeToken.isNotEmpty &&
        (store.isWeb || activeUrl != defaultApiBaseUrl);

    if (isConfigured) {
      await widgetSync.syncCredentials(
        baseUrl: activeUrl,
        deviceToken: activeToken,
        vibrationsEnabled: activeVibrationsEnabled,
      );
    }

    return AppSettings(
      baseUrl: activeUrl,
      deviceToken: activeToken,
      adminToken: activeAdminToken,
      isConfigured: isConfigured,
      vibrationsEnabled: activeVibrationsEnabled,
      shiftReminderMinutes: activeReminderMinutes,
      environment: environment,
      prodUrl: prodUrl,
      prodToken: prodToken,
      prodAdminToken: prodAdminToken,
      prodReminderMinutes: prodReminderMinutes,
      prodVibrationsEnabled: prodVibrationsEnabled,
      stagingUrl: stagingUrl,
      stagingToken: stagingToken,
      stagingAdminToken: stagingAdminToken,
      stagingReminderMinutes: stagingReminderMinutes,
      stagingVibrationsEnabled: stagingVibrationsEnabled,
    );
  }

  Future<void> saveSettings({
    required String prodToken,
    required String stagingToken,
    required String environment,
    String? prodAdminToken,
    String? stagingAdminToken,
    bool prodVibrationsEnabled = true,
    bool stagingVibrationsEnabled = true,
    int prodShiftReminderMinutes = 0,
    int stagingShiftReminderMinutes = 0,
    String? prodUrl,
    String? stagingUrl,
    String? adminToken,
    bool vibrationsEnabled = true,
    int shiftReminderMinutes = 0,
  }) async {
    final store = ref.read(credentialStoreProvider);
    final widgetSync = ref.read(widgetSyncServiceProvider);

    const cleanProdUrl = AppConfig.defaultApiBaseUrl;
    final cleanProdToken = prodToken.trim();
    const cleanStagingUrl = AppConfig.stagingApiBaseUrl;
    final cleanStagingToken = stagingToken.trim();

    final cleanProdAdmin = prodAdminToken?.trim() ?? adminToken?.trim();
    final cleanStagingAdmin = stagingAdminToken?.trim();

    final cleanEnv = (environment == 'staging') ? 'staging' : 'production';
    final activeUrl = cleanEnv == 'staging' ? cleanStagingUrl : cleanProdUrl;
    final activeToken =
        cleanEnv == 'staging' ? cleanStagingToken : cleanProdToken;
    final activeAdmin =
        cleanEnv == 'staging' ? cleanStagingAdmin : cleanProdAdmin;
    final activeReminder = cleanEnv == 'staging'
        ? stagingShiftReminderMinutes
        : (prodShiftReminderMinutes > 0
            ? prodShiftReminderMinutes
            : shiftReminderMinutes);
    final activeVibrations = cleanEnv == 'staging'
        ? stagingVibrationsEnabled
        : prodVibrationsEnabled;

    // Persist discrete environment configurations
    await store.write(_prodUrlStorageKey, cleanProdUrl);
    await store.write(_prodTokenStorageKey, cleanProdToken);
    await store.write(_stagingUrlStorageKey, cleanStagingUrl);
    await store.write(_stagingTokenStorageKey, cleanStagingToken);
    await store.write(_envStorageKey, cleanEnv);

    if (cleanProdAdmin != null && cleanProdAdmin.isNotEmpty) {
      await store.write(AppConfig.prodAdminTokenKey, cleanProdAdmin);
    } else {
      await store.delete(AppConfig.prodAdminTokenKey);
    }

    if (cleanStagingAdmin != null && cleanStagingAdmin.isNotEmpty) {
      await store.write(AppConfig.stagingAdminTokenKey, cleanStagingAdmin);
    } else {
      await store.delete(AppConfig.stagingAdminTokenKey);
    }

    await store.write(
        AppConfig.prodShiftReminderKey, prodShiftReminderMinutes.toString());
    await store.write(AppConfig.stagingShiftReminderKey,
        stagingShiftReminderMinutes.toString());
    await store.write(
        AppConfig.prodVibrationsKey, prodVibrationsEnabled.toString());
    await store.write(
        AppConfig.stagingVibrationsKey, stagingVibrationsEnabled.toString());

    // Also persist active credentials to legacy keys for widget & background readers
    await store.write(_baseUrlStorageKey, activeUrl);
    await store.write(_tokenStorageKey, activeToken);

    if (activeAdmin != null && activeAdmin.isNotEmpty) {
      await store.write(_adminTokenStorageKey, activeAdmin);
    } else {
      await store.delete(_adminTokenStorageKey);
    }
    await store.write(_hapticsStorageKey, activeVibrations.toString());
    await store.write(_reminderStorageKey, activeReminder.toString());

    await widgetSync.syncCredentials(
      baseUrl: activeUrl,
      deviceToken: activeToken,
      vibrationsEnabled: activeVibrations,
    );

    state = AsyncValue.data(
      AppSettings(
        baseUrl: activeUrl,
        deviceToken: activeToken,
        adminToken: activeAdmin,
        isConfigured: activeToken.isNotEmpty &&
            (store.isWeb || activeUrl != defaultApiBaseUrl),
        vibrationsEnabled: activeVibrations,
        shiftReminderMinutes: activeReminder,
        environment: cleanEnv,
        prodUrl: cleanProdUrl,
        prodToken: cleanProdToken,
        prodAdminToken: cleanProdAdmin,
        prodReminderMinutes: prodShiftReminderMinutes,
        prodVibrationsEnabled: prodVibrationsEnabled,
        stagingUrl: cleanStagingUrl,
        stagingToken: cleanStagingToken,
        stagingAdminToken: cleanStagingAdmin,
        stagingReminderMinutes: stagingShiftReminderMinutes,
        stagingVibrationsEnabled: stagingVibrationsEnabled,
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
