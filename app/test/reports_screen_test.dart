import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:work_hours_mobile/api/api_client.dart';
import 'package:work_hours_mobile/api/models.dart';
import 'package:work_hours_mobile/features/clock/clock_notifier.dart';
import 'package:work_hours_mobile/features/reports/reports_screen.dart';

class _MockApiClient extends ApiClient {
  _MockApiClient({this.contractMonthlyHours = 80})
      : super(baseUrl: 'https://mock.work.com');

  final int contractMonthlyHours;

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

  @override
  Future<List<TrackingEvent>> getEvents({
    required DateTime from,
    required DateTime to,
  }) async {
    return const [];
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
  });
}

class _MockApiClientNullR2 extends _MockApiClient {
  @override
  Future<Map<String, dynamic>?> getLatestReport() async => null;
}
