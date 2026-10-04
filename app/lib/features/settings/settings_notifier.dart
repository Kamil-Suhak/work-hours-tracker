import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/platform/platform_services.dart';

const String defaultApiBaseUrl = 'https://work-hours-api.workers.dev';

class AppSettings {
  final String baseUrl;
  final String deviceToken;
  final String? adminToken;
  final bool isConfigured;
  final bool vibrationsEnabled;

  const AppSettings({
    required this.baseUrl,
    required this.deviceToken,
    this.adminToken,
    required this.isConfigured,
    this.vibrationsEnabled = true,
  });

  AppSettings copyWith({
    String? baseUrl,
    String? deviceToken,
    String? adminToken,
    bool? isConfigured,
    bool? vibrationsEnabled,
  }) {
    return AppSettings(
      baseUrl: baseUrl ?? this.baseUrl,
      deviceToken: deviceToken ?? this.deviceToken,
      adminToken: adminToken ?? this.adminToken,
      isConfigured: isConfigured ?? this.isConfigured,
      vibrationsEnabled: vibrationsEnabled ?? this.vibrationsEnabled,
    );
  }
}

class SettingsNotifier extends AsyncNotifier<AppSettings> {
  static const String _tokenStorageKey = 'device_auth_token';
  static const String _baseUrlStorageKey = 'api_base_url';
  static const String _adminTokenStorageKey = 'admin_auth_token';
  static const String _hapticsStorageKey = 'vibrations_enabled';

  @override
  Future<AppSettings> build() async {
    final store = ref.read(credentialStoreProvider);
    final widgetSync = ref.read(widgetSyncServiceProvider);

    final storedUrl = await store.read(_baseUrlStorageKey);
    final storedToken = await store.read(_tokenStorageKey);
    final storedAdminToken = await store.read(_adminTokenStorageKey);
    final storedHaptics = await store.read(_hapticsStorageKey);

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
    );
  }

  Future<void> saveSettings({
    required String baseUrl,
    required String deviceToken,
    String? adminToken,
    bool vibrationsEnabled = true,
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
