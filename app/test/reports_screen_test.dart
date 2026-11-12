import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:work_hours_mobile/api/api_client.dart';
import 'package:work_hours_mobile/api/models.dart';
import 'package:work_hours_mobile/features/clock/clock_notifier.dart';
import 'package:work_hours_mobile/features/reports/reports_screen.dart';

class _MockApiClient extends ApiClient {
  _MockApiClient({this.contractMonthlyHours = 80, this.events = const []})
      : super(baseUrl: 'https://mock.work.com');

  final int contractMonthlyHours;
  final List<TrackingEvent> events;

  int generateCallCount = 0;
  String? lastFormat;
  String? lastPreset;
  List<Map<String, dynamic>>? lastPlannedShifts;

  @override
  Future<Map<String, dynamic>> getContractProfile() async {
    return {
      'monthlyHours': contractMonthlyHours,
      'contractorName': 'Test Contractor',
      'hourlyRatePln': 50,
    };
  }

  DateTime? lastEventsFrom;
  DateTime? lastEventsTo;

  @override
  Future<List<TrackingEvent>> getEvents({
    required DateTime from,
    required DateTime to,
  }) async {
    lastEventsFrom = from;
    lastEventsTo = to;
    return events;
  }

  @override
  Future<({Uint8List bytes, String filename, double totalHours, int totalShifts})> generateReport({
    DateTime? startDate,
    DateTime? endDate,
    String format = 'xlsx',
    String preset = 'full',
    List<Map<String, dynamic>>? plannedShifts,
  }) async {
    generateCallCount++;
    lastFormat = format;
    lastPreset = preset;
    lastPlannedShifts = plannedShifts;
    return (
      bytes: Uint8List.fromList([0x50, 0x4b, 0x03, 0x04]),
      filename: format == 'docx'
          ? 'zalaczniki-umowa-zlecenie-2026-10.docx'
          : 'work-hours-test.xlsx',
      totalHours: 80.0,
      totalShifts: 15,
    );
  }

  @override
  Future<Map<String, dynamic>?> getLatestReport() async {
    return {
      'filename': 'reports/work-hours-2026-09-full.xlsx',
      'month': '2026-09',
    };
  }

  @override
  Future<Uint8List> downloadReport(String filename) async {
    return Uint8List.fromList([0x50, 0x4b, 0x03, 0x04]);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.workhours.tracker/widget_sync');
  final List<MethodCall> channelCalls = [];

  setUp(() {
    channelCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      channelCalls.add(call);
      if (call.method == 'saveAndOpenReport') {
        final name = call.arguments['filename'] ?? 'work-hours-test.xlsx';
        return '/data/user/0/app/cache/reports/$name';
      }
      if (call.method == 'openReportFile') {
        return true;
      }
      return true;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('ReportsScreen Widget Tests', () {
    testWidgets('renders side-by-side Formal and Excel report cards with strict 3-button architecture',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final mockClient = _MockApiClient();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(mockClient),
          ],
          child: const MaterialApp(
            home: ReportsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Work Hours Reports'), findsOneWidget);

      // Both Formal and Excel Report panels are visible simultaneously
      expect(find.text('FORMAL CONTRACT REPORT'), findsOneWidget);
      expect(find.byKey(const Key('formal_month_dropdown')), findsOneWidget);
      // Button 1: Formal report single function button
      expect(find.text('Generate & Download Formal Report'), findsOneWidget);

      expect(find.text('EXCEL DATA REPORT'), findsOneWidget);
      expect(find.byKey(const Key('excel_month_dropdown')), findsOneWidget);
      // Button 2: Full report manual range button
      expect(find.text('Generate & Download Full Report'), findsOneWidget);
      // Button 3: Auto-generated report download button
      expect(find.textContaining('Download Auto-Generated Report'), findsOneWidget);

      // Verify side-by-side position: Formal card is to the left of Excel card
      final formalPos = tester.getTopLeft(find.text('FORMAL CONTRACT REPORT'));
      final excelPos = tester.getTopLeft(find.text('EXCEL DATA REPORT'));
      expect(formalPos.dx, lessThan(excelPos.dx));

      // Verify no orphaned Open Last Report buttons or helper texts
      expect(find.text('Open Last Report'), findsNothing);
      expect(find.textContaining('Retrieve the scheduled monthly archive'), findsNothing);
    });

    testWidgets('generates full Excel report with custom date range and downloads file',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final mockClient = _MockApiClient();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(mockClient),
          ],
          child: const MaterialApp(
            home: ReportsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Generate & Download Full Report'));
      await tester.tap(find.text('Generate & Download Full Report'));
      await tester.pumpAndSettle();

      expect(mockClient.generateCallCount, equals(1));
      expect(mockClient.lastFormat, equals('xlsx'));
      expect(mockClient.lastPreset, equals('full'));
      expect(channelCalls.any((c) => c.method == 'saveAndOpenReport'), isTrue);
    });

    testWidgets('enforces contract target gating for formal report and enables button when target met',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // Target contract hours = 8 hours (480 minutes)
      final mockClient = _MockApiClient(contractMonthlyHours: 8);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(mockClient),
          ],
          child: const MaterialApp(
            home: ReportsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Initially 0 hours worked and 0 hours planned -> target NOT met -> button is disabled
      final formalButtonFinder = find.byKey(const Key('generate_formal_report_button'));
      expect(formalButtonFinder, findsOneWidget);
      final formalButton = tester.widget<ElevatedButton>(formalButtonFinder);
      expect(formalButton.onPressed, isNull);

      // Tap the forecast status tile to open PlanFutureShiftsDialog
      await tester.tap(find.textContaining('Tap to plan remaining shifts'));
      await tester.pumpAndSettle();

      expect(find.text('Plan Remaining Shifts'), findsOneWidget);

      // In the dialog, set 8h on the first day
      await tester.tap(find.text('8h').first);
      await tester.pumpAndSettle();

      expect(find.text('Target Met'), findsOneWidget);

      // Tap Apply Forecast
      await tester.tap(find.text('Apply Forecast'));
      await tester.pumpAndSettle();

      // Back on the screen, target is met!
      expect(find.textContaining('Contract Target Met'), findsOneWidget);
      final enabledButton = tester.widget<ElevatedButton>(formalButtonFinder);
      expect(enabledButton.onPressed, isNotNull);

      // Tap Generate & Download Formal Report
      await tester.tap(formalButtonFinder);
      await tester.pumpAndSettle();

      expect(mockClient.generateCallCount, equals(1));
      expect(mockClient.lastFormat, equals('docx'));
      expect(mockClient.lastPreset, equals('formal'));
      expect(mockClient.lastPlannedShifts, isNotNull);
      expect(mockClient.lastPlannedShifts!.first['durationMinutes'], equals(480));
    });

    testWidgets('past month with met target: minute truncation handles seconds, forecasting disabled, generate button enabled',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // Create a shift in previous month with second offsets:
      // Clock in at 08:00:50 and clock out at 16:00:10 (8h 0m after minute truncation)
      final now = DateTime.now();
      final prevMonth = DateTime(now.year, now.month - 1, 1);
      final events = [
        TrackingEvent(
          id: 'evt-1',
          requestId: 'req-1',
          userId: 'user-1',
          eventType: 'clock_in',
          source: 'flutter_app',
          occurredAtUtc: DateTime.utc(prevMonth.year, prevMonth.month, 10, 8, 0, 50),
          createdAtUtc: DateTime.utc(prevMonth.year, prevMonth.month, 10, 8, 0, 50),
          location: 'remote',
        ),
        TrackingEvent(
          id: 'evt-2',
          requestId: 'req-2',
          userId: 'user-1',
          eventType: 'clock_out',
          source: 'flutter_app',
          occurredAtUtc: DateTime.utc(prevMonth.year, prevMonth.month, 10, 16, 0, 10),
          createdAtUtc: DateTime.utc(prevMonth.year, prevMonth.month, 10, 16, 0, 10),
          location: 'remote',
        ),
      ];

      final mockClient = _MockApiClient(contractMonthlyHours: 8, events: events);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(mockClient),
          ],
          child: const MaterialApp(
            home: ReportsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Switch dropdown to the previous month
      await tester.tap(find.byKey(const Key('formal_month_dropdown')));
      await tester.pumpAndSettle();

      final prevMonthText = DateFormat('MMMM yyyy').format(prevMonth);
      await tester.tap(find.text(prevMonthText).last);
      await tester.pumpAndSettle();

      // Target is met (8h 0m / 8h) thanks to minute truncation (50s and 10s truncated)
      expect(find.textContaining('Contract Target Met (8h 0m / 8h)'), findsOneWidget);
      expect(find.text('All required contract hours recorded for this month.'), findsOneWidget);
      expect(find.byIcon(Icons.edit_calendar), findsNothing);

      // Tapping the status tile should NOT open PlanFutureShiftsDialog
      await tester.tap(find.textContaining('Contract Target Met'));
      await tester.pumpAndSettle();
      expect(find.text('Plan Remaining Shifts'), findsNothing);

      // Generate button is enabled
      final formalButtonFinder = find.byKey(const Key('generate_formal_report_button'));
      final enabledButton = tester.widget<ElevatedButton>(formalButtonFinder);
      expect(enabledButton.onPressed, isNotNull);

      // Generate report: verify plannedShifts is null for past month
      await tester.tap(formalButtonFinder);
      await tester.pumpAndSettle();

      expect(mockClient.generateCallCount, equals(1));
      expect(mockClient.lastPlannedShifts, isNull);
    });

    testWidgets('past month with unmet target: shows error state, disables forecasting and disables generate button',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // Only 4 hours recorded in previous month against an 8-hour target
      final now = DateTime.now();
      final prevMonth = DateTime(now.year, now.month - 1, 1);
      final events = [
        TrackingEvent(
          id: 'evt-1',
          requestId: 'req-1',
          userId: 'user-1',
          eventType: 'clock_in',
          source: 'flutter_app',
          occurredAtUtc: DateTime.utc(prevMonth.year, prevMonth.month, 10, 8, 0, 0),
          createdAtUtc: DateTime.utc(prevMonth.year, prevMonth.month, 10, 8, 0, 0),
          location: 'remote',
        ),
        TrackingEvent(
          id: 'evt-2',
          requestId: 'req-2',
          userId: 'user-1',
          eventType: 'clock_out',
          source: 'flutter_app',
          occurredAtUtc: DateTime.utc(prevMonth.year, prevMonth.month, 10, 12, 0, 0),
          createdAtUtc: DateTime.utc(prevMonth.year, prevMonth.month, 10, 12, 0, 0),
          location: 'remote',
        ),
      ];

      final mockClient = _MockApiClient(contractMonthlyHours: 8, events: events);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(mockClient),
          ],
          child: const MaterialApp(
            home: ReportsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Switch dropdown to the previous month
      await tester.tap(find.byKey(const Key('formal_month_dropdown')));
      await tester.pumpAndSettle();

      final prevMonthText = DateFormat('MMMM yyyy').format(prevMonth);
      await tester.tap(find.text(prevMonthText).last);
      await tester.pumpAndSettle();

      // Status shows target not met and explains past month cannot be forecasted
      expect(find.textContaining('Contract Target Not Met (4h 0m / 8h)'), findsOneWidget);
      expect(find.text('Past month cannot be forecasted. Check your shift history.'), findsOneWidget);
      expect(find.byIcon(Icons.edit_calendar), findsNothing);

      // Tapping the status tile should NOT open PlanFutureShiftsDialog
      await tester.tap(find.textContaining('Contract Target Not Met'));
      await tester.pumpAndSettle();
      expect(find.text('Plan Remaining Shifts'), findsNothing);

      // Generate button is disabled
      final formalButtonFinder = find.byKey(const Key('generate_formal_report_button'));
      final button = tester.widget<ElevatedButton>(formalButtonFinder);
      expect(button.onPressed, isNull);
    });

    testWidgets('PlanFutureShiftsDialog in current month only lists today and future days',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final mockClient = _MockApiClient(contractMonthlyHours: 8);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(mockClient),
          ],
          child: const MaterialApp(
            home: ReportsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap forecast status tile
      await tester.tap(find.textContaining('Tap to plan remaining shifts'));
      await tester.pumpAndSettle();

      expect(find.text('Plan Remaining Shifts'), findsOneWidget);

      final now = DateTime.now();
      // If today is past day 1, any day strictly before today should NOT appear
      if (now.day > 1) {
        final yesterday = DateTime(now.year, now.month, now.day - 1);
        final yesterdayLabel = DateFormat('EEE, MMM d').format(yesterday);
        expect(find.text(yesterdayLabel), findsNothing);
      }
    });

    testWidgets('omits download auto-generated report button when R2 storage has no reports',
        (WidgetTester tester) async {
      final mockClient = _MockApiClientNullR2();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(mockClient),
          ],
          child: const MaterialApp(
            home: ReportsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('download_latest_storage_report_button')), findsNothing);
    });

    testWidgets('queries Warsaw month UTC bounds plus 24h tail when loading month data',
        (WidgetTester tester) async {
      final mockClient = _MockApiClient(contractMonthlyHours: 8);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(mockClient),
          ],
          child: const MaterialApp(
            home: ReportsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final now = DateTime.now();
      final expectedRange = warsawMonthRangeUtc(now.year, now.month);
      expect(mockClient.lastEventsFrom, equals(expectedRange.startUtc));
      expect(
        mockClient.lastEventsTo,
        equals(expectedRange.endUtc.add(const Duration(hours: 24))),
      );
    });
  });

  group('Warsaw Month Range & Shift Calculation Helpers', () {
    test('warsawMonthRangeUtc computes exact CET/CEST DST boundaries', () {
      // January 2026: CET (UTC+1) -> Jan 1 00:00 CET = Dec 31 23:00 UTC, Feb 1 00:00 CET = Jan 31 23:00 UTC
      final jan = warsawMonthRangeUtc(2026, 1);
      expect(jan.startUtc, equals(DateTime.utc(2025, 12, 31, 23, 0)));
      expect(jan.endUtc, equals(DateTime.utc(2026, 1, 31, 23, 0)));

      // October 2026: starts CEST (UTC+2) and ends CET (UTC+1) after last Sunday of Oct
      final oct = warsawMonthRangeUtc(2026, 10);
      expect(oct.startUtc, equals(DateTime.utc(2026, 9, 30, 22, 0)));
      expect(oct.endUtc, equals(DateTime.utc(2026, 10, 31, 23, 0)));
    });

    test('calculateMonthWorkedMinutes includes overnight month-end shifts and excludes next-month shifts', () {
      final events = [
        // Overnight shift starting 2026-10-31 23:00 CET (22:00 UTC) and ending 2026-11-01 02:00 CET (01:00 UTC): 180 min -> counts in Oct
        TrackingEvent(
          id: 'evt-oct-in',
          requestId: 'r1',
          userId: 'u1',
          eventType: 'clock_in',
          source: 'flutter_app',
          occurredAtUtc: DateTime.utc(2026, 10, 31, 22, 0),
          createdAtUtc: DateTime.utc(2026, 10, 31, 22, 0),
        ),
        TrackingEvent(
          id: 'evt-oct-out',
          requestId: 'r2',
          userId: 'u1',
          eventType: 'clock_out',
          source: 'flutter_app',
          occurredAtUtc: DateTime.utc(2026, 11, 1, 1, 0),
          createdAtUtc: DateTime.utc(2026, 11, 1, 1, 0),
        ),
        // Next-month shift starting 2026-11-01 09:00 CET (08:00 UTC) inside +24h tail -> excluded from Oct
        TrackingEvent(
          id: 'evt-nov-in',
          requestId: 'r3',
          userId: 'u1',
          eventType: 'clock_in',
          source: 'flutter_app',
          occurredAtUtc: DateTime.utc(2026, 11, 1, 8, 0),
          createdAtUtc: DateTime.utc(2026, 11, 1, 8, 0),
        ),
        TrackingEvent(
          id: 'evt-nov-out',
          requestId: 'r4',
          userId: 'u1',
          eventType: 'clock_out',
          source: 'flutter_app',
          occurredAtUtc: DateTime.utc(2026, 11, 1, 10, 0),
          createdAtUtc: DateTime.utc(2026, 11, 1, 10, 0),
        ),
      ];

      expect(calculateMonthWorkedMinutes(events, 2026, 10), equals(180));
      expect(calculateMonthWorkedMinutes(events, 2026, 11), equals(120));
    });

    test('calculateMonthWorkedMinutes uses createdAtUtc tie-breaker for identical occurredAtUtc', () {
      final sameInstant = DateTime.utc(2026, 10, 15, 10, 0);
      final events = [
        // Supplied out of order: clock_out created later at 10:02, clock_in created earlier at 10:01
        TrackingEvent(
          id: 'evt-out',
          requestId: 'r2',
          userId: 'u1',
          eventType: 'clock_out',
          source: 'flutter_app',
          occurredAtUtc: sameInstant,
          createdAtUtc: DateTime.utc(2026, 10, 15, 10, 2),
        ),
        TrackingEvent(
          id: 'evt-in',
          requestId: 'r1',
          userId: 'u1',
          eventType: 'clock_in',
          source: 'flutter_app',
          occurredAtUtc: DateTime.utc(2026, 10, 15, 8, 0),
          createdAtUtc: DateTime.utc(2026, 10, 15, 8, 0),
        ),
        TrackingEvent(
          id: 'evt-in2',
          requestId: 'r3',
          userId: 'u1',
          eventType: 'clock_in',
          source: 'flutter_app',
          occurredAtUtc: sameInstant,
          createdAtUtc: DateTime.utc(2026, 10, 15, 10, 3),
        ),
        TrackingEvent(
          id: 'evt-out2',
          requestId: 'r4',
          userId: 'u1',
          eventType: 'clock_out',
          source: 'flutter_app',
          occurredAtUtc: DateTime.utc(2026, 10, 15, 12, 0),
          createdAtUtc: DateTime.utc(2026, 10, 15, 12, 0),
        ),
      ];

      expect(calculateMonthWorkedMinutes(events, 2026, 10), equals(240));
    });
  });
}

class _MockApiClientNullR2 extends _MockApiClient {
  @override
  Future<Map<String, dynamic>?> getLatestReport() async => null;
}
