import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:work_hours_mobile/api/models.dart';
import 'package:work_hours_mobile/features/history/recent_shifts_sheet.dart';
import 'package:work_hours_mobile/features/history/shift_model.dart';
import 'package:work_hours_mobile/features/history/shifts_notifier.dart';

void main() {
  group('RecentShiftsSheet Tests', () {
    testWidgets(
        'renders shifts without source tags, and responds to shift taps',
        (WidgetTester tester) async {
      final shiftWithoutNote = ShiftRecord(
        clockIn: TrackingEvent(
          id: 'evt-1',
          requestId: 'req-1',
          userId: 'user-1',
          eventType: 'clock_in',
          source: 'flutter_app',
          occurredAtUtc: DateTime.parse('2026-10-01T08:00:00Z'),
          createdAtUtc: DateTime.parse('2026-10-01T08:00:00Z'),
        ),
        clockOut: TrackingEvent(
          id: 'evt-2',
          requestId: 'req-2',
          userId: 'user-1',
          eventType: 'clock_out',
          source: 'android_widget',
          occurredAtUtc: DateTime.parse('2026-10-01T16:00:00Z'),
          createdAtUtc: DateTime.parse('2026-10-01T16:00:00Z'),
        ),
        duration: const Duration(hours: 8),
      );

      final shiftWithNote = ShiftRecord(
        clockIn: TrackingEvent(
          id: 'evt-3',
          requestId: 'req-3',
          userId: 'user-1',
          eventType: 'clock_in',
          source: 'flutter_app',
          occurredAtUtc: DateTime.parse('2026-10-02T09:00:00Z'),
          createdAtUtc: DateTime.parse('2026-10-02T09:00:00Z'),
        ),
        clockOut: TrackingEvent(
          id: 'evt-4',
          requestId: 'req-4',
          userId: 'user-1',
          eventType: 'clock_out',
          source: 'flutter_app',
          occurredAtUtc: DateTime.parse('2026-10-02T17:30:00Z'),
          createdAtUtc: DateTime.parse('2026-10-02T17:30:00Z'),
          note: '# Work Accomplished\n- Built new UI features',
        ),
        duration: const Duration(hours: 8, minutes: 30),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            shiftsProvider.overrideWith(
              () => _MockShiftsNotifier([shiftWithNote, shiftWithoutNote]),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: RecentShiftsSheet(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Ensure headers and durations render
      expect(find.text('Recent Shifts'), findsOneWidget);
      expect(find.text('8h 30m'), findsOneWidget);
      expect(find.text('8h 0m'), findsOneWidget);

      // Verify that source labels are NOT rendered in the app
      expect(find.text('flutter_app'), findsNothing);
      expect(find.text('android_widget'), findsNothing);

      // Verify shift with note shows 'Notes' tag
      expect(find.text('Notes'), findsOneWidget);

      // Tap shift without note -> triggers "No notes from this day"
      await tester.tap(find.text('8h 0m'));
      await tester.pumpAndSettle();
      expect(find.text('No notes from this day'), findsOneWidget);

      // Tap shift with note -> opens dialog
      await tester.tap(find.text('8h 30m'));
      await tester.pumpAndSettle();
      expect(find.text('Shift Notes'), findsOneWidget);
      expect(find.text('Work Accomplished'), findsOneWidget);
      expect(find.textContaining('Built new UI features'), findsOneWidget);
    });
  });
}

class _MockShiftsNotifier extends ShiftsNotifier {
  final List<ShiftRecord> _mockShifts;
  _MockShiftsNotifier(this._mockShifts);

  @override
  Future<List<ShiftRecord>> build() async {
    return _mockShifts;
  }
}
