import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:work_hours_mobile/features/clock/widgets/current_shift_timer_card.dart';
import 'package:work_hours_mobile/features/clock/widgets/cyber_orbit_badge.dart';

void main() {
  group('CyberOrbitBadge Tests', () {
    testWidgets('renders clocked in status with glowing beacon',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CyberOrbitBadge(
              isClockedIn: true,
              enableAnimation: false,
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
            body: CyberOrbitBadge(
              isClockedIn: false,
              enableAnimation: false,
            ),
          ),
        ),
      );

      expect(find.text('CLOCKED OUT'), findsOneWidget);
    });
  });

  group('CurrentShiftTimerCard Tests', () {
    testWidgets('formats elapsed shift time and shows month total',
        (WidgetTester tester) async {
      final activeSince = DateTime.now().subtract(
        const Duration(hours: 1, minutes: 23, seconds: 45),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CurrentShiftTimerCard(
              isClockedIn: true,
              activeSince: activeSince,
              todaySeconds: 5025,
              monthSeconds: 36000,
              enablePeriodicTimer: false,
            ),
          ),
        ),
      );

      expect(find.text('CURRENT SHIFT TIMER'), findsOneWidget);
      expect(find.textContaining('01:23:45'), findsOneWidget);
      expect(find.textContaining('Started at'), findsOneWidget);
      expect(find.textContaining('Month to date: 10h 0m'), findsOneWidget);
    });

    testWidgets('shows greyed out timer when clocked out',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CurrentShiftTimerCard(
              isClockedIn: false,
              activeSince: null,
              todaySeconds: 0,
              monthSeconds: 7200,
              enablePeriodicTimer: false,
            ),
          ),
        ),
      );

      expect(find.text('--:--:--'), findsOneWidget);
      expect(find.textContaining("Today's total: 0h 0m"), findsOneWidget);
      expect(find.textContaining('Month to date: 2h 0m'), findsOneWidget);
    });
  });
}
