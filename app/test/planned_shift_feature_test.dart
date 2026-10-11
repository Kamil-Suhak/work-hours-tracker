import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:work_hours_mobile/features/clock/widgets/current_shift_timer_card.dart';
import 'package:work_hours_mobile/features/clock/widgets/planned_shift_dialog.dart';
import 'package:work_hours_mobile/features/settings/settings_dialog.dart';
import 'package:work_hours_mobile/features/settings/settings_notifier.dart';

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

    testWidgets('CurrentShiftTimerCard renders glowing progress bar when plannedDuration is set', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CurrentShiftTimerCard(
              isClockedIn: true,
              activeSince: DateTime.now().subtract(const Duration(hours: 2)),
              todaySeconds: 7200,
              monthSeconds: 7200,
              enablePeriodicTimer: false,
              plannedDuration: const Duration(hours: 8),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byKey(const Key('shift_progress_bar')), findsOneWidget);
      expect(find.textContaining('Target: 8h'), findsOneWidget);
      expect(find.textContaining('Remaining:'), findsOneWidget);
    });

    testWidgets('CurrentShiftTimerCard displays overtime indicator when elapsed exceeds target', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CurrentShiftTimerCard(
              isClockedIn: true,
              activeSince: DateTime.now().subtract(const Duration(hours: 9)),
              todaySeconds: 32400,
              monthSeconds: 32400,
              enablePeriodicTimer: false,
              plannedDuration: const Duration(hours: 8),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byKey(const Key('shift_progress_bar')), findsOneWidget);
      expect(find.textContaining('Target reached • Overtime:'), findsOneWidget);
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
    });
  });
}
