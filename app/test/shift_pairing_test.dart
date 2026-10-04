import 'package:flutter_test/flutter_test.dart';
import 'package:work_hours_mobile/api/models.dart';
import 'package:work_hours_mobile/features/history/shift_model.dart';

void main() {
  group('Shift Pairing Logic', () {
    test('correctly pairs consecutive clock_in and clock_out events', () {
      final events = [
        TrackingEvent(
          id: 'evt-1',
          requestId: 'req-1',
          userId: 'user-1',
          eventType: 'clock_in',
          source: 'flutter_app',
          occurredAtUtc: DateTime.parse('2026-10-01T08:00:00Z'),
          createdAtUtc: DateTime.parse('2026-10-01T08:00:00Z'),
        ),
        TrackingEvent(
          id: 'evt-2',
          requestId: 'req-2',
          userId: 'user-1',
          eventType: 'clock_out',
          source: 'flutter_app',
          occurredAtUtc: DateTime.parse('2026-10-01T16:30:00Z'),
          createdAtUtc: DateTime.parse('2026-10-01T16:30:00Z'),
        ),
      ];

      final shifts = pairEventsIntoShifts(events);

      expect(shifts.length, equals(1));
      expect(shifts[0].duration, equals(const Duration(hours: 8, minutes: 30)));
      expect(shifts[0].durationFormatted, equals('8h 30m'));
    });

    test('ignores trailing clock_in without clock_out', () {
      final events = [
        TrackingEvent(
          id: 'evt-1',
          requestId: 'req-1',
          userId: 'user-1',
          eventType: 'clock_in',
          source: 'flutter_app',
          occurredAtUtc: DateTime.parse('2026-10-01T08:00:00Z'),
          createdAtUtc: DateTime.parse('2026-10-01T08:00:00Z'),
        ),
        TrackingEvent(
          id: 'evt-2',
          requestId: 'req-2',
          userId: 'user-1',
          eventType: 'clock_out',
          source: 'flutter_app',
          occurredAtUtc: DateTime.parse('2026-10-01T12:00:00Z'),
          createdAtUtc: DateTime.parse('2026-10-01T12:00:00Z'),
        ),
        TrackingEvent(
          id: 'evt-3',
          requestId: 'req-3',
          userId: 'user-1',
          eventType: 'clock_in',
          source: 'flutter_app',
          occurredAtUtc: DateTime.parse('2026-10-01T13:00:00Z'),
          createdAtUtc: DateTime.parse('2026-10-01T13:00:00Z'),
        ),
      ];

      final shifts = pairEventsIntoShifts(events);

      expect(shifts.length, equals(1));
      expect(shifts[0].duration, equals(const Duration(hours: 4)));
    });

    test('orders shifts newest first', () {
      final events = [
        TrackingEvent(
          id: 'evt-1',
          requestId: 'req-1',
          userId: 'user-1',
          eventType: 'clock_in',
          source: 'flutter_app',
          occurredAtUtc: DateTime.parse('2026-10-01T08:00:00Z'),
          createdAtUtc: DateTime.parse('2026-10-01T08:00:00Z'),
        ),
        TrackingEvent(
          id: 'evt-2',
          requestId: 'req-2',
          userId: 'user-1',
          eventType: 'clock_out',
          source: 'flutter_app',
          occurredAtUtc: DateTime.parse('2026-10-01T12:00:00Z'),
          createdAtUtc: DateTime.parse('2026-10-01T12:00:00Z'),
        ),
        TrackingEvent(
          id: 'evt-3',
          requestId: 'req-3',
          userId: 'user-1',
          eventType: 'clock_in',
          source: 'flutter_app',
          occurredAtUtc: DateTime.parse('2026-10-02T09:00:00Z'),
          createdAtUtc: DateTime.parse('2026-10-02T09:00:00Z'),
        ),
        TrackingEvent(
          id: 'evt-4',
          requestId: 'req-4',
          userId: 'user-1',
          eventType: 'clock_out',
          source: 'flutter_app',
          occurredAtUtc: DateTime.parse('2026-10-02T17:00:00Z'),
          createdAtUtc: DateTime.parse('2026-10-02T17:00:00Z'),
        ),
      ];

      final shifts = pairEventsIntoShifts(events);

      expect(shifts.length, equals(2));
      // First item should be the Oct 2 shift (8h)
      expect(shifts[0].duration, equals(const Duration(hours: 8)));
      // Second item should be the Oct 1 shift (4h)
      expect(shifts[1].duration, equals(const Duration(hours: 4)));
    });

    test('extracts note from clockOut or clockIn event', () {
      final events = [
        TrackingEvent(
          id: 'evt-1',
          requestId: 'req-1',
          userId: 'user-1',
          eventType: 'clock_in',
          source: 'flutter_app',
          occurredAtUtc: DateTime.parse('2026-10-01T08:00:00Z'),
          createdAtUtc: DateTime.parse('2026-10-01T08:00:00Z'),
        ),
        TrackingEvent(
          id: 'evt-2',
          requestId: 'req-2',
          userId: 'user-1',
          eventType: 'clock_out',
          source: 'flutter_app',
          occurredAtUtc: DateTime.parse('2026-10-01T16:00:00Z'),
          createdAtUtc: DateTime.parse('2026-10-01T16:00:00Z'),
          note: '# Shift Note\n- Done task A',
        ),
      ];

      final shifts = pairEventsIntoShifts(events);
      expect(shifts[0].hasNote, isTrue);
      expect(shifts[0].note, equals('# Shift Note\n- Done task A'));
    });

    test('shift without note returns null and does not bleed notes from other shifts on same day', () {
      final events = [
        // Morning shift with no notes (created before notes were a feature)
        TrackingEvent(
          id: 'evt-1',
          requestId: 'req-1',
          userId: 'user-1',
          eventType: 'clock_in',
          source: 'flutter_app',
          occurredAtUtc: DateTime.parse('2026-10-01T08:00:00Z'),
          createdAtUtc: DateTime.parse('2026-10-01T08:00:00Z'),
        ),
        TrackingEvent(
          id: 'evt-2',
          requestId: 'req-2',
          userId: 'user-1',
          eventType: 'clock_out',
          source: 'flutter_app',
          occurredAtUtc: DateTime.parse('2026-10-01T12:00:00Z'),
          createdAtUtc: DateTime.parse('2026-10-01T12:00:00Z'),
          note: null,
        ),
        // Afternoon shift on the SAME DAY with notes
        TrackingEvent(
          id: 'evt-3',
          requestId: 'req-3',
          userId: 'user-1',
          eventType: 'clock_in',
          source: 'flutter_app',
          occurredAtUtc: DateTime.parse('2026-10-01T13:00:00Z'),
          createdAtUtc: DateTime.parse('2026-10-01T13:00:00Z'),
        ),
        TrackingEvent(
          id: 'evt-4',
          requestId: 'req-4',
          userId: 'user-1',
          eventType: 'clock_out',
          source: 'flutter_app',
          occurredAtUtc: DateTime.parse('2026-10-01T17:00:00Z'),
          createdAtUtc: DateTime.parse('2026-10-01T17:00:00Z'),
          note: 'Afternoon notes only',
        ),
      ];

      final shifts = pairEventsIntoShifts(events);
      expect(shifts.length, equals(2));
      // Afternoon shift has notes
      expect(shifts[0].hasNote, isTrue);
      expect(shifts[0].note, equals('Afternoon notes only'));
      // Morning shift MUST NOT have notes (no bleed across shifts)
      expect(shifts[1].hasNote, isFalse);
      expect(shifts[1].note, isNull);
    });
  });

  group('LatestEventSummary.isWithinGracePeriod', () {
    test('tolerates slight forward server clock skew when device is behind server', () {
      final serverTime = DateTime.parse('2026-10-04T12:00:00Z');
      final event = LatestEventSummary(
        id: 'evt-1',
        eventType: 'clock_in',
        occurredAtUtc: serverTime,
      );

      // Phone clock is 500ms behind server
      final deviceNow500msBehind = serverTime.subtract(const Duration(milliseconds: 500));
      expect(event.isWithinGracePeriod(now: deviceNow500msBehind), isTrue);

      // Phone clock is 30 seconds behind server
      final deviceNow30sBehind = serverTime.subtract(const Duration(seconds: 30));
      expect(event.isWithinGracePeriod(now: deviceNow30sBehind), isTrue);

      // Phone clock is 1 minute behind server
      final deviceNow1mBehind = serverTime.subtract(const Duration(minutes: 1));
      expect(event.isWithinGracePeriod(now: deviceNow1mBehind), isTrue);
    });

    test('returns true within normal 5-minute grace window', () {
      final serverTime = DateTime.parse('2026-10-04T12:00:00Z');
      final event = LatestEventSummary(
        id: 'evt-1',
        eventType: 'clock_out',
        occurredAtUtc: serverTime,
      );

      // 2 minutes after event
      final deviceNow2m = serverTime.add(const Duration(minutes: 2));
      expect(event.isWithinGracePeriod(now: deviceNow2m), isTrue);

      // Exactly 5 minutes after event
      final deviceNow5m = serverTime.add(const Duration(minutes: 5));
      expect(event.isWithinGracePeriod(now: deviceNow5m), isTrue);
    });

    test('returns false when 5-minute grace period has expired', () {
      final serverTime = DateTime.parse('2026-10-04T12:00:00Z');
      final event = LatestEventSummary(
        id: 'evt-1',
        eventType: 'clock_out',
        occurredAtUtc: serverTime,
      );

      // 5 minutes and 1 second after event
      final deviceNowExpired = serverTime.add(const Duration(minutes: 5, seconds: 1));
      expect(event.isWithinGracePeriod(now: deviceNowExpired), isFalse);
    });
  });
}
