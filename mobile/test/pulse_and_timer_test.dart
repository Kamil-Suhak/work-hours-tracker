import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:work_hours_mobile/features/clock/widgets/live_shift_timer.dart';
import 'package:work_hours_mobile/features/clock/widgets/pulse_status_badge.dart';

void main() {
  group('PulseStatusBadge Tests', () {
    testWidgets('renders clocked in status with emerald glow badge',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PulseStatusBadge(
              isClockedIn: true,
              enablePulseAnimation: false,
            ),
          ),
        ),
      );

      expect(find.text('CLOCKED IN'), findsOneWidget);
    });

    testWidgets('renders clocked out status', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PulseStatusBadge(
              isClockedIn: false,
              enablePulseAnimation: false,
            ),
          ),
        ),
      );

      expect(find.text('CLOCKED OUT'), findsOneWidget);
    });
  });

  group('LiveShiftTimer Tests', () {
    testWidgets('formats elapsed shift time and shows active since',
        (WidgetTester tester) async {
      final activeSince = DateTime.now().subtract(
        const Duration(hours: 1, minutes: 23, seconds: 45),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LiveShiftTimer(
              activeSince: activeSince,
              enablePeriodicTimer: false,
            ),
          ),
        ),
      );

      expect(find.text('LIVE SHIFT TIMER'), findsOneWidget);
      expect(find.textContaining('01:23:45'), findsOneWidget);
      expect(find.textContaining('Active since'), findsOneWidget);
    });
  });
}
