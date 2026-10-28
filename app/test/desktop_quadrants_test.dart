import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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
  Future<void> clockIn({int? offsetMinutes, String location = 'remote'}) async {}

  @override
  Future<void> clockOut({String? note, int? offsetMinutes}) async {}

  @override
  Future<void> refreshStatus() async {}

  @override
  Future<void> resetAndRefresh() async {}

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
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Desktop 4-Quadrant Dashboard Tests', () {
    setUp(() {
      FlutterSecureStorage.setMockInitialValues({});
    });
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
      expect(find.text('Notes | Current Shift'), findsOneWidget);

      // Bottom Left: NotePreviewQuadrant
      expect(find.byType(NotePreviewQuadrant), findsOneWidget);
      expect(find.text('Markdown Preview'), findsOneWidget);

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

    testWidgets('toolbar buttons position cursor between or after markers and retain focus',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final controller = TextEditingController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NoteEditorQuadrant(controller: controller),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap Bold 'B' button
      await tester.tap(find.text('B'));
      await tester.pumpAndSettle();

      expect(controller.text, '****');
      expect(controller.selection.baseOffset, 2);
      expect(controller.selection.extentOffset, 2);

      // Clear and tap H2 button
      controller.clear();
      await tester.tap(find.text('H2'));
      await tester.pumpAndSettle();

      expect(controller.text, '## ');
      expect(controller.selection.baseOffset, 3);
      expect(controller.selection.extentOffset, 3);
    });

    testWidgets(
        'renders gracefully and vertically centered on 1373x944 viewport without overflow',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1373, 944);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final mockStatus = WorkStatus(
        state: WorkState.clockedIn,
        activeSince: DateTime.parse('2026-10-04T08:00:00Z'),
        serverTime: DateTime.parse('2026-10-04T12:00:00Z'),
        todaySeconds: 7200,
        monthSeconds: 28800,
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

      expect(tester.takeException(), isNull);
      expect(find.byType(CurrentTrackerQuadrant), findsOneWidget);
      expect(find.byKey(const Key('clock_out_button')), findsOneWidget);
      expect(find.byKey(const Key('clock_in_button')), findsOneWidget);
    });

    testWidgets('allows clicking past shift to edit its note and returning to current shift',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final mockStatus = WorkStatus(
        state: WorkState.clockedOut,
        activeSince: null,
        serverTime: DateTime.parse('2026-10-20T17:00:00Z'),
        todaySeconds: 0,
        monthSeconds: 0,
      );

      final pastShift = ShiftRecord(
        clockIn: TrackingEvent(
          id: 'evt-in-1',
          requestId: 'req-1',
          userId: 'user-1',
          eventType: 'clock_in',
          source: 'manual',
          occurredAtUtc: DateTime.parse('2026-10-20T08:00:00Z'),
          createdAtUtc: DateTime.parse('2026-10-20T08:00:00Z'),
        ),
        clockOut: TrackingEvent(
          id: 'evt-out-1',
          requestId: 'req-2',
          userId: 'user-1',
          eventType: 'clock_out',
          source: 'manual',
          occurredAtUtc: DateTime.parse('2026-10-20T16:00:00Z'),
          createdAtUtc: DateTime.parse('2026-10-20T16:00:00Z'),
          note: 'Completed database migration',
        ),
        duration: const Duration(hours: 8),
      );

      await tester.pumpWidget(
        ProviderScope(
          key: UniqueKey(),
          overrides: [
            currentStatusProvider.overrideWith(
              () => _MockStatusNotifier(AsyncValue.data(mockStatus)),
            ),
            shiftsProvider.overrideWith(
              () => _MockShiftsWithDataNotifier([pastShift]),
            ),
          ],
          child: const MaterialApp(
            home: ClockScreen(enableAnimations: false),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // When clocked out and no past shift selected, editor is read-only
      final editorFinder = find.byType(TextField);
      final initialTextField = tester.widget<TextField>(editorFinder);
      expect(initialTextField.readOnly, isTrue);
      expect(find.text('Notes | Current Shift'), findsOneWidget);

      // Tap the past shift in Recent Shifts
      expect(find.textContaining('Oct 20, 2026'), findsOneWidget);
      await tester.tap(find.textContaining('Oct 20, 2026'));
      await tester.pumpAndSettle();

      // Verify that the note is loaded into the editor and preview
      expect(find.text('Completed database migration'), findsWidgets);

      // Verify that header changed to Notes | Shift on Oct 20, 2026
      expect(find.textContaining('Notes | Shift on'), findsOneWidget);
      expect(find.text('Current Shift'), findsWidgets);

      // And editor is now editable even though user is clocked out!
      final activeTextField = tester.widget<TextField>(find.byType(TextField));
      expect(activeTextField.readOnly, isFalse);

      // Tap 'Current Shift' to return
      await tester.tap(find.text('Current Shift').first);
      await tester.pumpAndSettle();

      // Header restored to Current Shift and becomes read-only again
      expect(find.text('Notes | Current Shift'), findsOneWidget);
      final returnedTextField = tester.widget<TextField>(find.byType(TextField));
      expect(returnedTextField.readOnly, isTrue);
    });
  });
}

class _MockShiftsWithDataNotifier extends AsyncNotifier<List<ShiftRecord>>
    implements ShiftsNotifier {
  final List<ShiftRecord> _shifts;
  _MockShiftsWithDataNotifier(this._shifts);

  @override
  Future<List<ShiftRecord>> build() async => _shifts;

  @override
  Future<void> refresh() async {}
}
