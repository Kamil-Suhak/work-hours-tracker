import 'package:flutter_test/flutter_test.dart';
import 'package:work_hours_mobile/features/clock/clock_notifier.dart';

void main() {
  group('Duration Formatting', () {
    test('formats zero seconds as 0h 0m', () {
      expect(formatSeconds(0), '0h 0m');
      expect(formatSeconds(-10), '0h 0m');
    });

    test('formats exact hours', () {
      expect(formatSeconds(3600), '1h 0m');
      expect(formatSeconds(28800), '8h 0m');
    });

    test('formats hours and minutes', () {
      expect(formatSeconds(3660), '1h 1m');
      expect(formatSeconds(7500), '2h 5m');
      expect(formatSeconds(30600), '8h 30m');
    });

    test('truncates remainder seconds', () {
      expect(formatSeconds(3659), '1h 0m');
    });
  });
}
