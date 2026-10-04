import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:work_hours_mobile/api/models.dart';
import 'package:work_hours_mobile/features/clock/clock_notifier.dart';
import 'package:work_hours_mobile/features/clock/clock_screen.dart';
import 'package:work_hours_mobile/features/clock/widgets/current_tracker_quadrant.dart';
import 'package:work_hours_mobile/features/clock/widgets/note_editor_quadrant.dart';
import 'package:work_hours_mobile/features/clock/widgets/note_preview_quadrant.dart';
import 'package:work_hours_mobile/features/history/recent_shifts_view.dart';
import 'package:work_hours_mobile/features/history/shift_model.dart';
import 'package:work_hours_mobile/features/history/shifts_notifier.dart';

class _MockStatusNotifier extends AsyncNotifier<WorkStatus>
    implements CurrentStatusNotifier {
  final AsyncValue<WorkStatus> _initialValue;
  _MockStatusNotifier(this._initialValue);

  @override
  Future<WorkStatus> build() async {
    return _initialValue.value!;
  }

  @override
  Future<void> clockIn() async {}

  @override
  Future<void> clockOut({String? note}) async {}

  @override
  Future<void> refreshStatus() async {}

  @override
  Future<void> undo(String eventId) async {}
}

class _MockShiftsNotifier extends AsyncNotifier<List<ShiftRecord>>
    implements ShiftsNotifier {
  @override
  Future<List<ShiftRecord>> build() async => [];

  @override
  Future<void> refresh() async {}
}

void main() {
  group('Desktop 4-Quadrant Dashboard Tests', () {
    testWidgets(
        'renders all 4 quadrants in clockwise order on desktop viewport (>= 900px)',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final mockStatus = WorkStatus(
        state: WorkState.clockedIn,
        activeSince: DateTime.parse('2026-10-04T08:00:00Z'),
        serverTime: DateTime.parse('2026-10-04T12:00:00Z'),
        todaySeconds: 14400,
        monthSeconds: 57600,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentStatusProvider.overrideWith(
              () => _MockStatusNotifier(AsyncValue.data(mockStatus)),
            ),
            shiftsProvider.overrideWith(
              () => _MockShiftsNotifier(),
            ),
          ],
          child: const MaterialApp(
            home: ClockScreen(enableAnimations: false),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Top Right: CurrentTrackerQuadrant
      expect(find.byType(CurrentTrackerQuadrant), findsOneWidget);
      expect(find.byKey(const Key('clock_out_button')), findsOneWidget);

      // Bottom Right: RecentShiftsView
      expect(find.byType(RecentShiftsView), findsOneWidget);
      expect(find.text('Recent Shifts'), findsOneWidget);

      // Top Left: NoteEditorQuadrant
      expect(find.byType(NoteEditorQuadrant), findsOneWidget);
      expect(find.text('Current Shift Note'), findsOneWidget);

      // Bottom Left: NotePreviewQuadrant
      expect(find.byType(NotePreviewQuadrant), findsOneWidget);
      expect(find.text('Live Markdown Preview'), findsOneWidget);

      // Live typing updates preview in real time
      await tester.enterText(
        find.byType(TextField),
        '# Accomplished\n- Deployed 4-quadrant web dashboard',
      );
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(NotePreviewQuadrant),
          matching: find.textContaining('Deployed 4-quadrant web dashboard'),
        ),
        findsOneWidget,
      );
    });
  });
}
