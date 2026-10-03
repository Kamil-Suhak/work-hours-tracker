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
  });
}
