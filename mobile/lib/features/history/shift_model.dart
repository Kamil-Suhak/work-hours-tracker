import '../../api/models.dart';

class ShiftRecord {
  final TrackingEvent clockIn;
  final TrackingEvent clockOut;
  final Duration duration;

  const ShiftRecord({
    required this.clockIn,
    required this.clockOut,
    required this.duration,
  });

  DateTime get startTime => clockIn.occurredAtUtc.toLocal();
  DateTime get endTime => clockOut.occurredAtUtc.toLocal();

  String get durationFormatted {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    return '${hours}h ${minutes}m';
  }

  String? get note => (clockOut.note?.trim().isNotEmpty == true)
      ? clockOut.note
      : ((clockIn.note?.trim().isNotEmpty == true) ? clockIn.note : null);

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
      final inTime = pendingClockIn.occurredAtUtc;
      final outTime = event.occurredAtUtc;
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
