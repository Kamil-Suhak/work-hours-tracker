import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:work_hours_mobile/features/clock/widgets/clock_action_button.dart';

void main() {
  group('ClockActionButton Widget Tests', () {
    testWidgets('triggers normal action with selected planned shift duration on tap', (tester) async {
      int? receivedOffset;
      Duration? receivedDuration;
      bool actionCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: ClockActionButton(
                isClockIn: true,
                isLoading: false,
                isEnabled: true,
                onAction: ({
                  int? offsetMinutes,
                  Duration? plannedDuration,
                  String location = 'remote',
                }) {
                  actionCalled = true;
                  receivedOffset = offsetMinutes;
                  receivedDuration = plannedDuration;
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
      await tester.pumpAndSettle();

      // Planned shift dialog appears
      expect(find.text('Planned Shift Duration'), findsOneWidget);
      expect(find.byKey(const Key('shift_pill_6h')), findsOneWidget);

      // Select 6h
      await tester.tap(find.byKey(const Key('shift_pill_6h')));
      await tester.pumpAndSettle();

      // Tap Clock In to confirm
      await tester.tap(find.byKey(const Key('planned_shift_confirm_button')));
      await tester.pumpAndSettle();

      expect(actionCalled, isTrue);
      expect(receivedOffset, isNull);
      expect(receivedDuration, equals(const Duration(hours: 6)));
    });

    testWidgets('skip target clocks in without duration', (tester) async {
      int? receivedOffset;
      Duration? receivedDuration;
      bool actionCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: ClockActionButton(
                isClockIn: true,
                isLoading: false,
                isEnabled: true,
                onAction: ({
                  int? offsetMinutes,
                  Duration? plannedDuration,
                  String location = 'remote',
                }) {
                  actionCalled = true;
                  receivedOffset = offsetMinutes;
                  receivedDuration = plannedDuration;
                },
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('clock_in_button')));
      await tester.pumpAndSettle();

      // Tap Skip Target
      await tester.tap(find.byKey(const Key('planned_shift_skip_button')));
      await tester.pumpAndSettle();

      expect(actionCalled, isTrue);
      expect(receivedOffset, isNull);
      expect(receivedDuration, isNull);
    });

    testWidgets('long press clock out displays popup menu with options (-5m, Now, +5m, Custom...)', (tester) async {
      int? receivedOffset;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: ClockActionButton(
                isClockIn: false,
                isLoading: false,
                isEnabled: true,
                onAction: ({
                  int? offsetMinutes,
                  Duration? plannedDuration,
                  String location = 'remote',
                }) {
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

    testWidgets('selecting +5m from menu on clock in then confirming target sends +5 offset and duration', (tester) async {
      int? receivedOffset;
      Duration? receivedDuration;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: ClockActionButton(
                isClockIn: true,
                isLoading: false,
                isEnabled: true,
                onAction: ({
                  int? offsetMinutes,
                  Duration? plannedDuration,
                  String location = 'remote',
                }) {
                  receivedOffset = offsetMinutes;
                  receivedDuration = plannedDuration;
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

      // Planned shift dialog should open next
      expect(find.text('Planned Shift Duration'), findsOneWidget);
      await tester.tap(find.byKey(const Key('shift_pill_4h')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('planned_shift_confirm_button')));
      await tester.pumpAndSettle();

      expect(receivedOffset, equals(5));
      expect(receivedDuration, equals(const Duration(hours: 4)));
    });

    testWidgets('selecting Custom... opens custom offset dialog and confirms selection', (tester) async {
      int? receivedOffset;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: ClockActionButton(
                isClockIn: false,
                isLoading: false,
                isEnabled: true,
                onAction: ({
                  int? offsetMinutes,
                  Duration? plannedDuration,
                  String location = 'remote',
                }) {
                  receivedOffset = offsetMinutes;
                },
              ),
            ),
          ),
        ),
      );

      await tester.longPress(find.byKey(const Key('clock_out_button')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Custom...'));
      await tester.pumpAndSettle();

      expect(find.text('Custom Clock Out'), findsOneWidget);
      expect(find.byKey(const Key('custom_offset_input')), findsOneWidget);
      expect(find.text('Allowed range: -120 to +120 min (±2h)'), findsOneWidget);
      expect(find.text('-15m'), findsOneWidget);
      expect(find.text('-10m'), findsNothing);
      expect(find.text('+10m'), findsNothing);

      // Typing an out-of-range value like 150 unselects the +15m chip, shows limit error, and disables Confirm
      await tester.enterText(find.byKey(const Key('custom_offset_input')), '15');
      await tester.pumpAndSettle();
      ChoiceChip chip15 = tester.widget(find.widgetWithText(ChoiceChip, '+15m'));
      expect(chip15.selected, isTrue);

      await tester.enterText(find.byKey(const Key('custom_offset_input')), '150');
      await tester.pumpAndSettle();
      chip15 = tester.widget(find.widgetWithText(ChoiceChip, '+15m'));
      expect(chip15.selected, isFalse);
      expect(find.text('Limit is -120 to +120 min (±2h)'), findsOneWidget);
      expect(find.text('--:--'), findsOneWidget);
      final confirmBtn = tester.widget<ElevatedButton>(
        find.byKey(const Key('confirm_custom_offset_button')),
      );
      expect(confirmBtn.onPressed, isNull);

      // Tap -30m preset chip
      await tester.tap(find.text('-30m'));
      await tester.pumpAndSettle();

      // Confirm dialog
      await tester.tap(find.byKey(const Key('confirm_custom_offset_button')));
      await tester.pumpAndSettle();

      expect(receivedOffset, equals(-30));
    });

    testWidgets('tapping dropdown arrow directly opens options menu without long-press', (tester) async {
      int? receivedOffset;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: ClockActionButton(
                isClockIn: false,
                isLoading: false,
                isEnabled: true,
                onAction: ({
                  int? offsetMinutes,
                  Duration? plannedDuration,
                  String location = 'remote',
                }) {
                  receivedOffset = offsetMinutes;
                },
              ),
            ),
          ),
        ),
      );

      expect(find.byKey(const Key('clock_out_button_options')), findsOneWidget);

      // Single tap the dropdown arrow target
      await tester.tap(find.byKey(const Key('clock_out_button_options')));
      await tester.pumpAndSettle();

      expect(find.text('-5m'), findsOneWidget);
      expect(find.text('+5m'), findsOneWidget);

      await tester.tap(find.text('+5m'));
      await tester.pumpAndSettle();

      expect(receivedOffset, equals(5));
    });
  });
}
