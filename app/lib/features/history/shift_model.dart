import '../../api/models.dart';
import '../clock/clock_notifier.dart';

class ShiftRecord {
  final TrackingEvent clockIn;
  final TrackingEvent clockOut;
  final Duration duration;

  const ShiftRecord({
    required this.clockIn,
    required this.clockOut,
    required this.duration,
  });

  DateTime get startTime => truncateToMinute(clockIn.occurredAtUtc.toLocal());
  DateTime get endTime => truncateToMinute(clockOut.occurredAtUtc.toLocal());

  String get durationFormatted => formatSeconds(duration.inSeconds);

  String? get note {
    if (clockOut.note?.trim().isNotEmpty == true) return clockOut.note!.trim();
    if (clockIn.note?.trim().isNotEmpty == true) return clockIn.note!.trim();
    return null;
  }

  bool get hasNote => note != null && note!.trim().isNotEmpty;
}

List<ShiftRecord> pairEventsIntoShifts(List<TrackingEvent> events) {
  final sorted = List<TrackingEvent>.from(events)
    ..sort((a, b) => a.occurredAtUtc.compareTo(b.occurredAtUtc));

  final shifts = <ShiftRecord>[];
  TrackingEvent? pendingClockIn;

  for (final event in sorted) {
    if (event.eventType == 'clock_in') {
      pendingClockIn = event;
    } else if (event.eventType == 'clock_out' && pendingClockIn != null) {
      final inTime = truncateToMinute(pendingClockIn.occurredAtUtc);
      final outTime = truncateToMinute(event.occurredAtUtc);
      final diff = outTime.difference(inTime);
      final duration = diff.isNegative ? Duration.zero : diff;

      shifts.add(
        ShiftRecord(
          clockIn: pendingClockIn,
          clockOut: event,
          duration: duration,
        ),
      );
      pendingClockIn = null;
    }
  }

  // Return newest shifts first for UI presentation
  return shifts.reversed.toList();
}
