import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:work_hours_mobile/api/models.dart';
import 'package:work_hours_mobile/features/clock/clock_notifier.dart';
import 'package:work_hours_mobile/features/clock/clock_screen.dart';

void main() {
  group('ClockScreen Widget Tests', () {
    testWidgets(
        'displays clocked-out state with clock-in enabled and clock-out disabled',
        (WidgetTester tester) async {
      final mockStatus = WorkStatus(
        state: WorkState.clockedOut,
        activeSince: null,
        serverTime: DateTime.parse('2026-10-03T10:00:00Z'),
        todaySeconds: 14400, // 4 hours
        monthSeconds: 72000, // 20 hours
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentStatusProvider.overrideWith(
              () => _MockStatusNotifier(AsyncValue.data(mockStatus)),
            ),
          ],
          child: const MaterialApp(home: ClockScreen()),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Work Hours Tracker'), findsOneWidget);
      expect(find.text('CLOCKED OUT'), findsOneWidget);
      expect(find.text('4h 0m'), findsOneWidget);

      final clockInBtn = tester
          .widget<ElevatedButton>(find.byKey(const Key('clock_in_button')));
      final clockOutBtn = tester
          .widget<ElevatedButton>(find.byKey(const Key('clock_out_button')));

      expect(clockInBtn.enabled, isTrue);
      expect(clockOutBtn.enabled, isFalse);
    });

    testWidgets(
        'displays clocked-in state with clock-in disabled and clock-out enabled',
        (WidgetTester tester) async {
      final mockStatus = WorkStatus(
        state: WorkState.clockedIn,
        activeSince: DateTime.parse('2026-10-03T08:00:00Z'),
        serverTime: DateTime.parse('2026-10-03T10:00:00Z'),
        todaySeconds: 7200,
        monthSeconds: 7200,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentStatusProvider.overrideWith(
              () => _MockStatusNotifier(AsyncValue.data(mockStatus)),
            ),
          ],
          child: const MaterialApp(
            home: ClockScreen(enableAnimations: false),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('CLOCKED IN'), findsOneWidget);
      expect(find.textContaining('Active since'), findsOneWidget);

      final clockInBtn = tester
          .widget<ElevatedButton>(find.byKey(const Key('clock_in_button')));
      final clockOutBtn = tester
          .widget<ElevatedButton>(find.byKey(const Key('clock_out_button')));

      expect(clockInBtn.enabled, isFalse);
      expect(clockOutBtn.enabled, isTrue);
    });

    testWidgets('renders error view with retry button on failure',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentStatusProvider.overrideWith(
              () => _MockStatusNotifier(
                AsyncValue.error(
                    Exception('Network unreachable'), StackTrace.current),
              ),
            ),
          ],
          child: const MaterialApp(
            home: ClockScreen(enableAnimations: false),
          ),
        ),
      );

      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('Connection or Server Error'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets(
        'displays undo button and opens confirmation dialog when within grace period',
        (WidgetTester tester) async {
      final now = DateTime.now().toUtc();
      final mockStatus = WorkStatus(
        state: WorkState.clockedIn,
        activeSince: now,
        serverTime: now,
        todaySeconds: 0,
        monthSeconds: 0,
        latestEvent: LatestEventSummary(
          id: 'evt-12345678-abcd',
          eventType: 'clock_in',
          occurredAtUtc: now.subtract(const Duration(minutes: 1)),
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentStatusProvider.overrideWith(
              () => _MockStatusNotifier(AsyncValue.data(mockStatus)),
            ),
          ],
          child: const MaterialApp(
            home: ClockScreen(enableAnimations: false),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byKey(const Key('undo_button')), findsOneWidget);
      expect(find.text('Undo Clock In'), findsOneWidget);

      await tester.ensureVisible(find.byKey(const Key('undo_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('undo_button')));
      await tester.pumpAndSettle();

      expect(find.text('Revert Action'), findsOneWidget);
      expect(find.text('Confirm Undo'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    });
  });
}

class _MockStatusNotifier extends CurrentStatusNotifier {
  final AsyncValue<WorkStatus> _initialState;
  _MockStatusNotifier(this._initialState);

  @override
  Future<WorkStatus> build() {
    if (_initialState.hasError) {
      return Future<WorkStatus>.error(
        _initialState.error!,
        _initialState.stackTrace,
      );
    }
    if (_initialState.isLoading) {
      return Completer<WorkStatus>().future;
    }
    return Future<WorkStatus>.value(_initialState.value!);
  }
}
