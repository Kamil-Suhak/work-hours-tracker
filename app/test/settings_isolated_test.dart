import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:work_hours_mobile/config/app_config.dart';
import 'package:work_hours_mobile/features/settings/settings_dialog.dart';
import 'package:work_hours_mobile/features/settings/settings_notifier.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Isolated Settings Tests', () {
    setUp(() {
      FlutterSecureStorage.setMockInitialValues({
        AppConfig.environmentKey: 'production',
        AppConfig.prodDeviceTokenKey: 'prod-token-1234',
        AppConfig.stagingTokenKey: 'staging-token-5678',
        AppConfig.prodAdminTokenKey: 'prod-admin-token',
        AppConfig.stagingAdminTokenKey: 'staging-admin-token',
        AppConfig.prodShiftReminderKey: '10',
        AppConfig.stagingShiftReminderKey: '5',
        AppConfig.prodVibrationsKey: 'true',
        AppConfig.stagingVibrationsKey: 'false',
      });
    });

    test('SettingsNotifier loads and persists isolated per-environment settings', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final AppSettings initial =
          (await container.read(settingsProvider.future))!;

      expect(initial.environment, 'production');
      expect(initial.deviceToken, 'prod-token-1234');
      expect(initial.adminToken, 'prod-admin-token');
      expect(initial.shiftReminderMinutes, 10);
      expect(initial.vibrationsEnabled, isTrue);

      // Now save changes
      await container.read(settingsProvider.notifier).saveSettings(
            prodToken: 'updated-prod-token',
            stagingToken: 'updated-staging-token',
            environment: 'staging',
            prodAdminToken: 'prod-admin-2',
            stagingAdminToken: 'staging-admin-2',
            prodShiftReminderMinutes: 15,
            stagingShiftReminderMinutes: 0,
            prodVibrationsEnabled: false,
            stagingVibrationsEnabled: true,
          );

      final AppSettings updated = container.read(settingsProvider).value!;
      expect(updated.environment, 'staging');
      expect(updated.deviceToken, 'updated-staging-token');
      expect(updated.adminToken, 'staging-admin-2');
      expect(updated.shiftReminderMinutes, 0);
      expect(updated.vibrationsEnabled, isTrue);
      expect(updated.baseUrl, AppConfig.stagingApiBaseUrl);

      // Verify Production values were preserved in the state
      expect(updated.prodToken, 'updated-prod-token');
      expect(updated.prodAdminToken, 'prod-admin-2');
      expect(updated.prodReminderMinutes, 15);
      expect(updated.prodVibrationsEnabled, isFalse);

      // Switch environment back to production
      await container.read(settingsProvider.notifier).saveSettings(
            prodToken: updated.prodToken,
            stagingToken: updated.stagingToken,
            environment: 'production',
            prodAdminToken: updated.prodAdminToken,
            stagingAdminToken: updated.stagingAdminToken,
            prodShiftReminderMinutes: updated.prodReminderMinutes,
            stagingShiftReminderMinutes: updated.stagingReminderMinutes,
            prodVibrationsEnabled: updated.prodVibrationsEnabled,
            stagingVibrationsEnabled: updated.stagingVibrationsEnabled,
          );

      final AppSettings prodActive = container.read(settingsProvider).value!;
      expect(prodActive.environment, 'production');
      expect(prodActive.deviceToken, 'updated-prod-token');
      expect(prodActive.shiftReminderMinutes, 15);
      expect(prodActive.vibrationsEnabled, isFalse);
      expect(prodActive.baseUrl, AppConfig.defaultApiBaseUrl);
    });

    testWidgets('SettingsDialog renders locked API Base URL and isolates environment inputs', (tester) async {
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

      // Check that "API Base URL" is present as a label, not an editable text input with hint
      expect(find.text('API Base URL'), findsOneWidget);
      expect(find.text(AppConfig.defaultApiBaseUrl), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
      expect(find.byTooltip('Copy API URL'), findsOneWidget);

      // Switch to Staging
      await tester.tap(find.text('Staging'));
      await tester.pumpAndSettle();

      expect(find.text('Staging API Base URL'), findsOneWidget);
      expect(find.text(AppConfig.stagingApiBaseUrl), findsOneWidget);
      expect(find.byKey(const Key('staging_web_link')), findsOneWidget);
    });
  });
}
