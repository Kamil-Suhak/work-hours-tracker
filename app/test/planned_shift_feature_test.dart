import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:work_hours_mobile/features/clock/widgets/current_shift_timer_card.dart';
import 'package:work_hours_mobile/features/clock/widgets/planned_shift_dialog.dart';
import 'package:work_hours_mobile/features/clock/widgets/shift_target_dialog.dart';
import 'package:work_hours_mobile/features/settings/settings_dialog.dart';

void main() {
  group('Planned Shift & Progress Bar Tests', () {
    testWidgets('PlannedShiftDialog allows selecting 4h pill and confirms', (tester) async {
      PlannedShiftResult? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                key: const Key('open_dialog'),
                onPressed: () async {
                  result = await PlannedShiftDialog.show(ctx);
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('open_dialog')));
      await tester.pumpAndSettle();

      expect(find.text('Planned Shift Duration'), findsOneWidget);
      expect(find.byKey(const Key('shift_pill_4h')), findsOneWidget);

      await tester.tap(find.byKey(const Key('shift_pill_4h')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('planned_shift_confirm_button')));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.isCancelled, isFalse);
      expect(result!.duration, equals(const Duration(hours: 4)));
      expect(result!.location, equals('remote'));
    });

    testWidgets('PlannedShiftDialog allows selecting In-Office location and skipping target', (tester) async {
      PlannedShiftResult? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                key: const Key('open_dialog'),
                onPressed: () async {
                  result = await PlannedShiftDialog.show(ctx);
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('open_dialog')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('shift_location_remote')), findsOneWidget);
      expect(find.byKey(const Key('shift_location_in-office')), findsOneWidget);

      await tester.tap(find.byKey(const Key('shift_location_in-office')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('planned_shift_skip_button')));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.isCancelled, isFalse);
      expect(result!.duration, isNull);
      expect(result!.location, equals('in-office'));
    });

    testWidgets('PlannedShiftDialog cancel returns cancelled result', (tester) async {
      PlannedShiftResult? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                key: const Key('open_dialog'),
                onPressed: () async {
                  result = await PlannedShiftDialog.show(ctx);
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('open_dialog')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('planned_shift_cancel_button')));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.isCancelled, isTrue);
      expect(result!.duration, isNull);
    });

    testWidgets('CurrentShiftTimerCard renders glowing progress bar and adjustment controls when targetClockOutUtc is set', (tester) async {
      final activeSince = DateTime.now().subtract(const Duration(hours: 2));
      final targetUtc = activeSince.add(const Duration(hours: 8)).toUtc();
      int? lastDelta;
      bool openedCustom = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CurrentShiftTimerCard(
              isClockedIn: true,
              activeSince: activeSince,
              targetClockOutUtc: targetUtc,
              todaySeconds: 7200,
              monthSeconds: 7200,
              enablePeriodicTimer: false,
              onAdjustTargetDelta: (delta) => lastDelta = delta,
              onOpenCustomTarget: () => openedCustom = true,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byKey(const Key('shift_progress_bar')), findsOneWidget);
      expect(find.textContaining('Target: 8h'), findsOneWidget);
      expect(find.textContaining('Remaining:'), findsOneWidget);
      expect(find.byKey(const Key('target_minus_10_button')), findsOneWidget);
      expect(find.byKey(const Key('target_plus_10_button')), findsOneWidget);
      expect(find.byKey(const Key('target_custom_button')), findsOneWidget);

      await tester.tap(find.byKey(const Key('target_minus_10_button')));
      expect(lastDelta, -10);

      await tester.tap(find.byKey(const Key('target_plus_10_button')));
      expect(lastDelta, 10);

      await tester.tap(find.byKey(const Key('target_custom_button')));
      expect(openedCustom, isTrue);
    });

    testWidgets('CurrentShiftTimerCard displays set target chip when clocked in without target', (tester) async {
      bool openedCustom = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CurrentShiftTimerCard(
              isClockedIn: true,
              activeSince: DateTime.now().subtract(const Duration(hours: 1)),
              targetClockOutUtc: null,
              todaySeconds: 3600,
              monthSeconds: 3600,
              enablePeriodicTimer: false,
              onOpenCustomTarget: () => openedCustom = true,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byKey(const Key('shift_progress_bar')), findsNothing);
      expect(find.byKey(const Key('set_target_button')), findsOneWidget);
      await tester.tap(find.byKey(const Key('set_target_button')));
      expect(openedCustom, isTrue);
    });

    testWidgets('CurrentShiftTimerCard displays overtime indicator when elapsed exceeds target', (tester) async {
      final activeSince = DateTime.now().subtract(const Duration(hours: 9));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CurrentShiftTimerCard(
              isClockedIn: true,
              activeSince: activeSince,
              targetClockOutUtc: activeSince.add(const Duration(hours: 8)).toUtc(),
              todaySeconds: 32400,
              monthSeconds: 32400,
              enablePeriodicTimer: false,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byKey(const Key('shift_progress_bar')), findsOneWidget);
      expect(find.textContaining('Target reached • Overtime:'), findsOneWidget);
    });

    testWidgets('ShiftTargetDialog allows setting custom hours/minutes and clearing active target', (tester) async {
      ShiftTargetDialogResult? result;
      final activeSince = DateTime.now().subtract(const Duration(minutes: 45));
      final existingTarget = activeSince.add(const Duration(hours: 2)).toUtc();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                key: const Key('open_target_dialog'),
                onPressed: () async {
                  result = await ShiftTargetDialog.show(
                    ctx,
                    activeSince: activeSince,
                    currentTargetUtc: existingTarget,
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('open_target_dialog')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('target_hours_field')), '3');
      await tester.enterText(find.byKey(const Key('target_minutes_field')), '15');
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('save_target_button')));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.clearTarget, isFalse);
      expect(result!.targetMinutes, 195);

      // Reopen and remove target
      await tester.tap(find.byKey(const Key('open_target_dialog')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('remove_target_button')));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.clearTarget, isTrue);
      expect(result!.targetMinutes, isNull);
    });
  });

  group('SettingsDialog Environment & Reminder Tests', () {
    testWidgets('SettingsDialog renders environment selector and reminder dropdown', (tester) async {
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

      expect(find.byKey(const Key('environment_selector')), findsOneWidget);
      expect(find.text('Production'), findsOneWidget);
      expect(find.text('Staging'), findsOneWidget);
      expect(find.byKey(const Key('shift_reminder_dropdown')), findsOneWidget);

      // Select Staging
      await tester.tap(find.text('Staging'));
      await tester.pumpAndSettle();

      expect(find.textContaining('work-hours-api-staging'), findsOneWidget);
      expect(find.byKey(const Key('staging_web_link')), findsOneWidget);
      expect(find.text('Open Staging Web in Browser'), findsOneWidget);

      // Select Production back
      await tester.tap(find.text('Production'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('staging_web_link')), findsNothing);
    });
  });
}
