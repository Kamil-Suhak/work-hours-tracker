import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:work_hours_mobile/api/models.dart';
import 'package:work_hours_mobile/features/clock/clock_notifier.dart';
import 'package:work_hours_mobile/features/clock/clock_screen.dart';

void main() {
  testWidgets('ClockScreen displays status and action buttons', (WidgetTester tester) async {
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
            () => _MockStatusNotifier(mockStatus),
          ),
        ],
        child: const MaterialApp(
          home: ClockScreen(),
        ),
      ),
    );

    // Initial frame
    await tester.pump();

    // Verify presence of buttons and state
    expect(find.text('Work Hours Tracker'), findsOneWidget);
    expect(find.text('CLOCKED OUT'), findsOneWidget);
    expect(find.text('4h 0m'), findsOneWidget);
    expect(find.byKey(const Key('clock_in_button')), findsOneWidget);
    expect(find.byKey(const Key('clock_out_button')), findsOneWidget);
  });
}

class _MockStatusNotifier extends CurrentStatusNotifier {
  final WorkStatus _status;
  _MockStatusNotifier(this._status);

  @override
  Future<WorkStatus> build() async {
    return _status;
  }
}
