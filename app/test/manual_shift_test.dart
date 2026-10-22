import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:work_hours_mobile/features/history/manual_shift_dialog.dart';

void main() {
  group('ManualShiftDialog Tests', () {
    testWidgets('renders all form inputs and validation errors when empty',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: ManualShiftDialog(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Record Past Shift'), findsOneWidget);
      expect(find.text('Shift Date'), findsOneWidget);
      expect(find.text('Clock In'), findsOneWidget);
      expect(find.text('Clock Out'), findsOneWidget);
      expect(find.text('Total Shift Duration:'), findsOneWidget);
      expect(find.text('8h 0m'), findsOneWidget); // 9:00 to 17:00 default
      expect(find.text('Work Location'), findsOneWidget);
      expect(find.byKey(const Key('manual_location_remote')), findsOneWidget);
      expect(find.byKey(const Key('manual_location_in-office')), findsOneWidget);
      expect(find.text('Record Shift'), findsOneWidget);

      // Select In-Office chip
      await tester.tap(find.byKey(const Key('manual_location_in-office')));
      await tester.pumpAndSettle();

      // Tap Record Shift with empty fields
      await tester.tap(find.text('Record Shift'));
      await tester.pumpAndSettle();

      expect(find.text('Reason is required for audit logs'), findsOneWidget);
      expect(find.text('Admin token is required'), findsOneWidget);
    });
  });
}
