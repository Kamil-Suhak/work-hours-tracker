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
        'renders shifts without source tags and displays location badges',
        (WidgetTester tester) async {
      final remoteShift = ShiftRecord(
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

      final inOfficeShift = ShiftRecord(
        clockIn: TrackingEvent(
          id: 'evt-3',
          requestId: 'req-3',
          userId: 'user-1',
          eventType: 'clock_in',
          source: 'flutter_app',
          occurredAtUtc: DateTime.parse('2026-10-02T09:00:00Z'),
          createdAtUtc: DateTime.parse('2026-10-02T09:00:00Z'),
          location: 'in-office',
        ),
        clockOut: TrackingEvent(
          id: 'evt-4',
          requestId: 'req-4',
          userId: 'user-1',
          eventType: 'clock_out',
          source: 'flutter_app',
          occurredAtUtc: DateTime.parse('2026-10-02T17:30:00Z'),
          createdAtUtc: DateTime.parse('2026-10-02T17:30:00Z'),
        ),
        duration: const Duration(hours: 8, minutes: 30),
      );

      final septemberShift = ShiftRecord(
        clockIn: TrackingEvent(
          id: 'evt-5',
          requestId: 'req-5',
          userId: 'user-1',
          eventType: 'clock_in',
          source: 'flutter_app',
          occurredAtUtc: DateTime.parse('2026-09-15T08:00:00Z'),
          createdAtUtc: DateTime.parse('2026-09-15T08:00:00Z'),
        ),
        clockOut: TrackingEvent(
          id: 'evt-6',
          requestId: 'req-6',
          userId: 'user-1',
          eventType: 'clock_out',
          source: 'flutter_app',
          occurredAtUtc: DateTime.parse('2026-09-15T14:00:00Z'),
          createdAtUtc: DateTime.parse('2026-09-15T14:00:00Z'),
        ),
        duration: const Duration(hours: 6),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            shiftsProvider.overrideWith(
              () => _MockShiftsNotifier(
                [inOfficeShift, remoteShift, septemberShift],
              ),
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

      // Ensure headers and monthly groups render
      expect(find.text('Recent Shifts'), findsOneWidget);
      expect(find.text('October 2026'), findsOneWidget);
      expect(find.text('September 2026'), findsOneWidget);

      // Latest month (October 2026) is expanded by default; September is collapsed
      expect(find.text('8h 30m'), findsOneWidget);
      expect(find.text('8h 0m'), findsOneWidget);
      expect(find.text('6h 0m'), findsNothing);

      // Verify that source labels are NOT rendered in the app
      expect(find.text('flutter_app'), findsNothing);
      expect(find.text('android_widget'), findsNothing);

      // Verify location badges render
      expect(find.text('In-Office'), findsOneWidget);
      expect(find.text('Remote'), findsOneWidget);

      // Expanding September 2026 leaves October 2026 expanded independently
      await tester.tap(find.byKey(const Key('month_header_2026-09')));
      await tester.pumpAndSettle();
      expect(find.text('6h 0m'), findsOneWidget);
      expect(find.text('8h 30m'), findsOneWidget);
      expect(find.text('8h 0m'), findsOneWidget);
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
