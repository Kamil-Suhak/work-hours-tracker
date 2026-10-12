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
  final String stagingUrl;
  final String stagingToken;

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
    this.stagingUrl = AppConfig.stagingApiBaseUrl,
    this.stagingToken = '',
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
      prodUrl: prodUrl ?? this.prodUrl,
      prodToken: prodToken ?? this.prodToken,
      stagingUrl: stagingUrl ?? this.stagingUrl,
      stagingToken: stagingToken ?? this.stagingToken,
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
    final storedStagingUrl = await store.read(_stagingUrlStorageKey);
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

    final prodToken = (storedProdToken != null && storedProdToken.trim().isNotEmpty)
        ? storedProdToken.trim()
        : (storedToken?.trim() ?? '');

    final stagingUrl = (storedStagingUrl != null &&
            storedStagingUrl.trim().isNotEmpty)
        ? storedStagingUrl.trim()
        : AppConfig.stagingApiBaseUrl;

    final stagingToken = storedStagingToken?.trim() ?? '';
    final environment =
        (storedEnv?.trim() == 'staging') ? 'staging' : 'production';

    final activeUrl = environment == 'staging' ? stagingUrl : prodUrl;
    final activeToken = environment == 'staging' ? stagingToken : prodToken;

    final isConfigured = activeToken.isNotEmpty &&
        (store.isWeb || activeUrl != defaultApiBaseUrl);
    final vibrationsEnabled = storedHaptics != 'false';
    final shiftReminderMinutes = int.tryParse(storedReminder ?? '0') ?? 0;

    if (isConfigured) {
      await widgetSync.syncCredentials(
        baseUrl: activeUrl,
        deviceToken: activeToken,
        vibrationsEnabled: vibrationsEnabled,
      );
    }

    return AppSettings(
      baseUrl: activeUrl,
      deviceToken: activeToken,
      adminToken: storedAdminToken?.trim(),
      isConfigured: isConfigured,
      vibrationsEnabled: vibrationsEnabled,
      shiftReminderMinutes: shiftReminderMinutes,
      environment: environment,
      prodUrl: prodUrl,
      prodToken: prodToken,
      stagingUrl: stagingUrl,
      stagingToken: stagingToken,
    );
  }

  Future<void> saveSettings({
    required String prodUrl,
    required String prodToken,
    required String stagingUrl,
    required String stagingToken,
    required String environment,
    String? adminToken,
    bool vibrationsEnabled = true,
    int shiftReminderMinutes = 0,
  }) async {
    final store = ref.read(credentialStoreProvider);
    final widgetSync = ref.read(widgetSyncServiceProvider);

    var cleanProdUrl = prodUrl.trim();
    if (cleanProdUrl.endsWith('/')) {
      cleanProdUrl = cleanProdUrl.substring(0, cleanProdUrl.length - 1);
    }
    if (cleanProdUrl.isEmpty) {
      cleanProdUrl = AppConfig.defaultApiBaseUrl;
    }
    final cleanProdToken = prodToken.trim();

    var cleanStagingUrl = stagingUrl.trim();
    if (cleanStagingUrl.endsWith('/')) {
      cleanStagingUrl = cleanStagingUrl.substring(0, cleanStagingUrl.length - 1);
    }
    if (cleanStagingUrl.isEmpty) {
      cleanStagingUrl = AppConfig.stagingApiBaseUrl;
    }
    final cleanStagingToken = stagingToken.trim();

    final cleanEnv = (environment == 'staging') ? 'staging' : 'production';
    final activeUrl = cleanEnv == 'staging' ? cleanStagingUrl : cleanProdUrl;
    final activeToken = cleanEnv == 'staging' ? cleanStagingToken : cleanProdToken;

    // Persist discrete environment configurations
    await store.write(_prodUrlStorageKey, cleanProdUrl);
    await store.write(_prodTokenStorageKey, cleanProdToken);
    await store.write(_stagingUrlStorageKey, cleanStagingUrl);
    await store.write(_stagingTokenStorageKey, cleanStagingToken);
    await store.write(_envStorageKey, cleanEnv);

    // Also persist active credentials to legacy keys for widget & background readers
    await store.write(_baseUrlStorageKey, activeUrl);
    await store.write(_tokenStorageKey, activeToken);

    if (adminToken != null && adminToken.trim().isNotEmpty) {
      await store.write(_adminTokenStorageKey, adminToken.trim());
    } else {
      await store.delete(_adminTokenStorageKey);
    }
    await store.write(_hapticsStorageKey, vibrationsEnabled.toString());
    await store.write(_reminderStorageKey, shiftReminderMinutes.toString());

    await widgetSync.syncCredentials(
      baseUrl: activeUrl,
      deviceToken: activeToken,
      vibrationsEnabled: vibrationsEnabled,
    );

    state = AsyncValue.data(
      AppSettings(
        baseUrl: activeUrl,
        deviceToken: activeToken,
        adminToken: adminToken?.trim(),
        isConfigured: activeToken.isNotEmpty &&
            (store.isWeb || activeUrl != defaultApiBaseUrl),
        vibrationsEnabled: vibrationsEnabled,
        shiftReminderMinutes: shiftReminderMinutes,
        environment: cleanEnv,
        prodUrl: cleanProdUrl,
        prodToken: cleanProdToken,
        stagingUrl: cleanStagingUrl,
        stagingToken: cleanStagingToken,
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
