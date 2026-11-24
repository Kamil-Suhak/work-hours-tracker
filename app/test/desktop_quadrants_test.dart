import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:work_hours_mobile/api/models.dart';
import 'package:work_hours_mobile/features/clock/clock_notifier.dart';
import 'package:work_hours_mobile/features/clock/clock_screen.dart';
import 'package:work_hours_mobile/features/clock/widgets/current_tracker_quadrant.dart';
import 'package:work_hours_mobile/features/history/recent_shifts_view.dart';
import 'package:work_hours_mobile/features/history/shift_model.dart';
import 'package:work_hours_mobile/features/history/shifts_notifier.dart';

class _MockStatusNotifier extends AsyncNotifier<WorkStatus>
    implements CurrentStatusNotifier {
  final AsyncValue<WorkStatus> _initialValue;
  _MockStatusNotifier(this._initialValue);

  @override
  Future<WorkStatus> build() async => _initialValue.value!;

  @override
  Future<void> clockIn({
    int? offsetMinutes,
    String location = 'remote',
    int? targetMinutes,
  }) async {}

  @override
  Future<WorkStatus> updateShiftTarget({
    int? deltaMinutes,
    int? targetMinutes,
    bool clearTarget = false,
  }) async =>
      _initialValue.value!;

  @override
  Future<void> clockOut({int? offsetMinutes}) async {}

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

  group('Desktop Centered Dashboard Tests', () {
    setUp(() {
      FlutterSecureStorage.setMockInitialValues({});
    });

    testWidgets(
        'renders centered tracker above recent shifts on desktop viewport (>= 900px)',
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

      final trackerFinder = find.byType(CurrentTrackerQuadrant);
      final shiftsFinder = find.byType(RecentShiftsView);

      expect(trackerFinder, findsOneWidget);
      expect(find.byKey(const Key('clock_out_button')), findsOneWidget);
      expect(shiftsFinder, findsOneWidget);
      expect(find.text('Recent Shifts'), findsOneWidget);

      // Verify vertical stacking: tracker above recent shifts, horizontally centered
      final trackerRect = tester.getRect(trackerFinder);
      final shiftsRect = tester.getRect(shiftsFinder);
      expect(trackerRect.bottom, lessThan(shiftsRect.top));
      expect(trackerRect.center.dx, closeTo(640, 1));
      expect(shiftsRect.center.dx, closeTo(640, 1));
    });
  });
}
