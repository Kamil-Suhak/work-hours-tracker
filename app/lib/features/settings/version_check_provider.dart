import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../../config/app_config.dart';

final httpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(() => client.close());
  return client;
});

class VersionInfo {
  final String currentVersion;
  final String? latestVersion;
  final bool isChecking;
  final bool hasUpdate;
  final bool isError;

  const VersionInfo({
    required this.currentVersion,
    this.latestVersion,
    this.isChecking = false,
    this.hasUpdate = false,
    this.isError = false,
  });

  String get currentDisplay =>
      currentVersion.startsWith('v') ? currentVersion : 'v$currentVersion';

  String get latestDisplay {
    if (isChecking) return 'checking...';
    if (isError || latestVersion == null) return 'unavailable';
    return latestVersion!.startsWith('v') ? latestVersion! : 'v$latestVersion';
  }

  bool get isUpToDate =>
      !isChecking && !isError && latestVersion != null && !hasUpdate;

  String get displayText =>
      'Latest version: $latestDisplay | Current version: $currentDisplay';
}

final versionCheckProvider =
    FutureProvider.autoDispose<VersionInfo>((ref) async {
  const current = AppConfig.appVersion;
  final client = ref.watch(httpClientProvider);

  try {
    final response = await client.get(
      Uri.parse(
          'https://api.github.com/repos/Kamil-Suhak/work-hours-tracker/releases/latest'),
      headers: {
        'Accept': 'application/vnd.github.v3+json',
        'User-Agent': 'WorkHoursTracker-App',
      },
    ).timeout(const Duration(seconds: 4));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final latestTag = data['tag_name'] as String?;
      if (latestTag != null && latestTag.isNotEmpty) {
        final cleanCurrent = current.replaceFirst(RegExp(r'^v'), '');
        final cleanLatest = latestTag.replaceFirst(RegExp(r'^v'), '');
        final hasUpdate = cleanLatest != cleanCurrent;

        return VersionInfo(
          currentVersion: current,
          latestVersion: latestTag,
          hasUpdate: hasUpdate,
        );
      }
    }
    return VersionInfo(
      currentVersion: current,
      isError: true,
    );
  } catch (_) {
    return VersionInfo(
      currentVersion: current,
      isError: true,
    );
  }
});
