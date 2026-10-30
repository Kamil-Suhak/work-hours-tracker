import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:work_hours_mobile/config/app_config.dart';
import 'package:work_hours_mobile/features/settings/settings_dialog.dart';
import 'package:work_hours_mobile/features/settings/version_check_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('VersionInfo unit tests', () {
    test('formats checking state correctly', () {
      const info = VersionInfo(
        currentVersion: '1.2.3',
        isChecking: true,
      );
      expect(
        info.displayText,
        'Latest version: checking... | Current version: v1.2.3',
      );
    });

    test('formats error / unavailable state correctly', () {
      const info = VersionInfo(
        currentVersion: '1.2.3',
        isError: true,
      );
      expect(
        info.displayText,
        'Latest version: unavailable | Current version: v1.2.3',
      );
    });

    test('formats up-to-date version correctly', () {
      const info = VersionInfo(
        currentVersion: '1.2.3',
        latestVersion: 'v1.2.3',
        hasUpdate: false,
      );
      expect(
        info.displayText,
        'Latest version: v1.2.3 | Current version: v1.2.3',
      );
      expect(info.hasUpdate, isFalse);
    });

    test('formats update available version correctly', () {
      const info = VersionInfo(
        currentVersion: '1.2.3',
        latestVersion: 'v1.2.4',
        hasUpdate: true,
      );
      expect(
        info.displayText,
        'Latest version: v1.2.4 | Current version: v1.2.3',
      );
      expect(info.hasUpdate, isTrue);
    });
  });

  group('versionCheckProvider integration tests', () {
    test('fetches latest version and detects available update', () async {
      final mockClient = MockClient((request) async {
        expect(
          request.url.toString(),
          'https://api.github.com/repos/Kamil-Suhak/work-hours-tracker/releases/latest',
        );
        return http.Response(
          '{"tag_name": "v99.0.0", "name": "Work Hours Tracker v99.0.0"}',
          200,
        );
      });

      final container = ProviderContainer(
        overrides: [
          httpClientProvider.overrideWithValue(mockClient),
        ],
      );
      addTearDown(container.dispose);

      final result = await container.read(versionCheckProvider.future);
      expect(result.latestVersion, 'v99.0.0');
      expect(result.hasUpdate, isTrue);
      expect(result.isError, isFalse);
    });

    test('fetches latest version and detects match (no update)', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          '{"tag_name": "v${AppConfig.appVersion}"}',
          200,
        );
      });

      final container = ProviderContainer(
        overrides: [
          httpClientProvider.overrideWithValue(mockClient),
        ],
      );
      addTearDown(container.dispose);

      final result = await container.read(versionCheckProvider.future);
      expect(result.latestVersion, 'v${AppConfig.appVersion}');
      expect(result.hasUpdate, isFalse);
      expect(result.isError, isFalse);
    });

    test('handles HTTP errors gracefully', () async {
      final mockClient = MockClient((request) async {
        return http.Response('Rate limit exceeded', 403);
      });

      final container = ProviderContainer(
        overrides: [
          httpClientProvider.overrideWithValue(mockClient),
        ],
      );
      addTearDown(container.dispose);

      final result = await container.read(versionCheckProvider.future);
      expect(result.isError, isTrue);
      expect(result.latestVersion, isNull);
    });
  });

  group('SettingsDialog Android Version Badge Widget Test', () {
    setUp(() {
      FlutterSecureStorage.setMockInitialValues({
        AppConfig.environmentKey: 'production',
        AppConfig.prodDeviceTokenKey: 'test-token',
        AppConfig.stagingTokenKey: 'test-staging',
      });
    });

    testWidgets('renders version badge on Android platform with update indicator',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;

      try {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              versionCheckProvider.overrideWith((ref) => const VersionInfo(
                    currentVersion: '1.2.3',
                    latestVersion: 'v1.2.4',
                    hasUpdate: true,
                  )),
            ],
            child: const MaterialApp(
              home: Scaffold(
                body: SettingsDialog(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final badgeFinder = find.byKey(const Key('android_version_badge'));
        expect(badgeFinder, findsOneWidget);
        expect(
          find.text('Latest version: v1.2.4 | Current version: v1.2.3'),
          findsOneWidget,
        );
        expect(find.text('UPDATE'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('does not render badge on iOS platform', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

      try {
        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: SettingsDialog(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final badgeFinder = find.byKey(const Key('android_version_badge'));
        expect(badgeFinder, findsNothing);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });
}
