import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'widget_sync_service.dart';

const String defaultApiBaseUrl = 'https://work-hours-api.workers.dev';

class AppSettings {
  final String baseUrl;
  final String deviceToken;
  final bool isConfigured;

  const AppSettings({
    required this.baseUrl,
    required this.deviceToken,
    required this.isConfigured,
  });

  AppSettings copyWith({
    String? baseUrl,
    String? deviceToken,
    bool? isConfigured,
  }) {
    return AppSettings(
      baseUrl: baseUrl ?? this.baseUrl,
      deviceToken: deviceToken ?? this.deviceToken,
      isConfigured: isConfigured ?? this.isConfigured,
    );
  }
}

class SettingsNotifier extends AsyncNotifier<AppSettings> {
  static const String _tokenStorageKey = 'device_auth_token';
  static const String _baseUrlStorageKey = 'api_base_url';
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  @override
  Future<AppSettings> build() async {
    final storedUrl = await _storage.read(key: _baseUrlStorageKey);
    final storedToken = await _storage.read(key: _tokenStorageKey);

    final baseUrl = (storedUrl != null && storedUrl.trim().isNotEmpty)
        ? storedUrl.trim()
        : const String.fromEnvironment('API_BASE_URL', defaultValue: defaultApiBaseUrl);

    final deviceToken = storedToken?.trim() ?? '';
    final isConfigured = deviceToken.isNotEmpty && baseUrl != defaultApiBaseUrl;

    if (isConfigured) {
      await WidgetSyncService.syncCredentials(
        baseUrl: baseUrl,
        deviceToken: deviceToken,
      );
    }

    return AppSettings(
      baseUrl: baseUrl,
      deviceToken: deviceToken,
      isConfigured: isConfigured,
    );
  }

  Future<void> saveSettings({
    required String baseUrl,
    required String deviceToken,
  }) async {
    var cleanedUrl = baseUrl.trim();
    if (cleanedUrl.endsWith('/')) {
      cleanedUrl = cleanedUrl.substring(0, cleanedUrl.length - 1);
    }
    final cleanedToken = deviceToken.trim();

    await _storage.write(key: _baseUrlStorageKey, value: cleanedUrl);
    await _storage.write(key: _tokenStorageKey, value: cleanedToken);

    await WidgetSyncService.syncCredentials(
      baseUrl: cleanedUrl,
      deviceToken: cleanedToken,
    );

    state = AsyncValue.data(
      AppSettings(
        baseUrl: cleanedUrl,
        deviceToken: cleanedToken,
        isConfigured: cleanedToken.isNotEmpty && cleanedUrl != defaultApiBaseUrl,
      ),
    );
  }
}

final settingsProvider =
    AsyncNotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);
