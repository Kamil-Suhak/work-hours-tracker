import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:work_hours_mobile/features/clock/widgets/clock_action_button.dart';

void main() {
  group('ClockActionButton Widget Tests', () {
    testWidgets('triggers normal action without offset on simple tap', (tester) async {
      int? receivedOffset;
      bool actionCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: ClockActionButton(
                isClockIn: true,
                isLoading: false,
                isEnabled: true,
                onAction: ({int? offsetMinutes}) {
                  actionCalled = true;
                  receivedOffset = offsetMinutes;
                },
              ),
            ),
          ),
        ),
      );

      expect(find.byKey(const Key('clock_in_button')), findsOneWidget);
      expect(find.text('CLOCK IN'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_drop_down), findsOneWidget);

      await tester.tap(find.byKey(const Key('clock_in_button')));
      await tester.pump();

      expect(actionCalled, isTrue);
      expect(receivedOffset, isNull);
    });

    testWidgets('long press displays popup menu with options (-5m, Now, +5m, Custom...)', (tester) async {
      int? receivedOffset;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: ClockActionButton(
                isClockIn: false,
                isLoading: false,
                isEnabled: true,
                onAction: ({int? offsetMinutes}) {
                  receivedOffset = offsetMinutes;
                },
              ),
            ),
          ),
        ),
      );

      expect(find.byKey(const Key('clock_out_button')), findsOneWidget);
      expect(find.text('CLOCK OUT'), findsOneWidget);

      // Long press the button
      await tester.longPress(find.byKey(const Key('clock_out_button')));
      await tester.pumpAndSettle();

      // Check menu items
      expect(find.text('-5m'), findsOneWidget);
      expect(find.text('Now'), findsOneWidget);
      expect(find.text('+5m'), findsOneWidget);
      expect(find.text('Custom...'), findsOneWidget);

      // Tap -5m
      await tester.tap(find.text('-5m'));
      await tester.pumpAndSettle();

      expect(receivedOffset, equals(-5));
    });

    testWidgets('selecting +5m from menu sends +5 offset', (tester) async {
      int? receivedOffset;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: ClockActionButton(
                isClockIn: true,
                isLoading: false,
                isEnabled: true,
                onAction: ({int? offsetMinutes}) {
                  receivedOffset = offsetMinutes;
                },
              ),
            ),
          ),
        ),
      );

      await tester.longPress(find.byKey(const Key('clock_in_button')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('+5m'));
      await tester.pumpAndSettle();

      expect(receivedOffset, equals(5));
    });

    testWidgets('selecting Custom... opens custom offset dialog and confirms selection', (tester) async {
      int? receivedOffset;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: ClockActionButton(
                isClockIn: true,
                isLoading: false,
                isEnabled: true,
                onAction: ({int? offsetMinutes}) {
                  receivedOffset = offsetMinutes;
                },
              ),
            ),
          ),
        ),
      );

      await tester.longPress(find.byKey(const Key('clock_in_button')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Custom...'));
      await tester.pumpAndSettle();

      expect(find.text('Custom Clock In'), findsOneWidget);
      expect(find.byKey(const Key('custom_offset_input')), findsOneWidget);
      expect(find.text('-15m'), findsOneWidget);

      // Tap -15m preset chip
      await tester.tap(find.text('-15m'));
      await tester.pumpAndSettle();

      // Confirm dialog
      await tester.tap(find.byKey(const Key('confirm_custom_offset_button')));
      await tester.pumpAndSettle();

      expect(receivedOffset, equals(-15));
    });
  });
}
