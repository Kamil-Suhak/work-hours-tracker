import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'widget_sync_service.dart';

const String defaultApiBaseUrl = 'https://work-hours-api.workers.dev';

class AppSettings {
  final String baseUrl;
  final String deviceToken;
  final bool isConfigured;
  final bool vibrationsEnabled;

  const AppSettings({
    required this.baseUrl,
    required this.deviceToken,
    required this.isConfigured,
    this.vibrationsEnabled = true,
  });

  AppSettings copyWith({
    String? baseUrl,
    String? deviceToken,
    bool? isConfigured,
    bool? vibrationsEnabled,
  }) {
    return AppSettings(
      baseUrl: baseUrl ?? this.baseUrl,
      deviceToken: deviceToken ?? this.deviceToken,
      isConfigured: isConfigured ?? this.isConfigured,
      vibrationsEnabled: vibrationsEnabled ?? this.vibrationsEnabled,
    );
  }
}

class SettingsNotifier extends AsyncNotifier<AppSettings> {
  static const String _tokenStorageKey = 'device_auth_token';
  static const String _baseUrlStorageKey = 'api_base_url';
  static const String _hapticsStorageKey = 'vibrations_enabled';
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  @override
  Future<AppSettings> build() async {
    final storedUrl = await _storage.read(key: _baseUrlStorageKey);
    final storedToken = await _storage.read(key: _tokenStorageKey);
    final storedHaptics = await _storage.read(key: _hapticsStorageKey);

    final baseUrl = (storedUrl != null && storedUrl.trim().isNotEmpty)
        ? storedUrl.trim()
        : const String.fromEnvironment('API_BASE_URL', defaultValue: defaultApiBaseUrl);

    final deviceToken = storedToken?.trim() ?? '';
    final isConfigured = deviceToken.isNotEmpty && baseUrl != defaultApiBaseUrl;
    final vibrationsEnabled = storedHaptics != 'false';

    if (isConfigured) {
      await WidgetSyncService.syncCredentials(
        baseUrl: baseUrl,
        deviceToken: deviceToken,
        vibrationsEnabled: vibrationsEnabled,
      );
    }

    return AppSettings(
      baseUrl: baseUrl,
      deviceToken: deviceToken,
      isConfigured: isConfigured,
      vibrationsEnabled: vibrationsEnabled,
    );
  }

  Future<void> saveSettings({
    required String baseUrl,
    required String deviceToken,
    bool vibrationsEnabled = true,
  }) async {
    var cleanedUrl = baseUrl.trim();
    if (cleanedUrl.endsWith('/')) {
      cleanedUrl = cleanedUrl.substring(0, cleanedUrl.length - 1);
    }
    final cleanedToken = deviceToken.trim();

    await _storage.write(key: _baseUrlStorageKey, value: cleanedUrl);
    await _storage.write(key: _tokenStorageKey, value: cleanedToken);
    await _storage.write(key: _hapticsStorageKey, value: vibrationsEnabled.toString());

    await WidgetSyncService.syncCredentials(
      baseUrl: cleanedUrl,
      deviceToken: cleanedToken,
      vibrationsEnabled: vibrationsEnabled,
    );

    state = AsyncValue.data(
      AppSettings(
        baseUrl: cleanedUrl,
        deviceToken: cleanedToken,
        isConfigured: cleanedToken.isNotEmpty && cleanedUrl != defaultApiBaseUrl,
        vibrationsEnabled: vibrationsEnabled,
      ),
    );
  }
}

final settingsProvider =
    AsyncNotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);
