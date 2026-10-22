import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:work_hours_mobile/api/api_client.dart';
import 'package:work_hours_mobile/features/clock/clock_notifier.dart';
import 'package:work_hours_mobile/features/reports/reports_screen.dart';

class _MockApiClient extends ApiClient {
  _MockApiClient() : super(baseUrl: 'https://mock.work.com');

  int generateCallCount = 0;
  String? lastFormat;
  String? lastPreset;
  List<Map<String, dynamic>>? lastPlannedShifts;

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
      totalHours: 12.5,
      totalShifts: 2,
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
    testWidgets('renders separated Formal and Excel tabs without format extensions',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
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
      expect(find.text('Formal Report'), findsOneWidget);
      expect(find.text('Excel Report'), findsOneWidget);

      // Formal Tab contents (initial)
      expect(find.text('FORMAL CONTRACT REPORT'), findsOneWidget);
      expect(find.byKey(const Key('formal_month_dropdown')), findsOneWidget);
      expect(find.text('Start Date'), findsOneWidget);
      expect(find.text('End Date'), findsOneWidget);
      expect(find.text('Generate Formal Report'), findsOneWidget);

      // Switch to Excel Tab
      await tester.tap(find.text('Excel Report'));
      await tester.pumpAndSettle();

      expect(find.text('EXCEL DATA REPORT'), findsOneWidget);
      expect(find.byKey(const Key('excel_month_dropdown')), findsOneWidget);
      expect(find.text('Generate Excel Report'), findsOneWidget);
      expect(find.text('Download Latest Automated Report'), findsOneWidget);
    });

    testWidgets('generates full Excel report with custom date range and opens file',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
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

      // Switch to Excel Tab
      await tester.tap(find.text('Excel Report'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Generate Excel Report'));
      await tester.tap(find.text('Generate Excel Report'));
      await tester.pumpAndSettle();

      expect(mockClient.generateCallCount, equals(1));
      expect(mockClient.lastFormat, equals('xlsx'));
      expect(mockClient.lastPreset, equals('full'));

      expect(find.text('Open Last Report'), findsOneWidget);
      expect(channelCalls.any((c) => c.method == 'saveAndOpenReport'), isTrue);

      await tester.ensureVisible(find.text('Open Last Report'));
      await tester.tap(find.text('Open Last Report'));
      await tester.pumpAndSettle();

      expect(channelCalls.any((c) => c.method == 'openReportFile'), isTrue);
    });

    testWidgets('opens PlanFutureShiftsDialog and sends plannedShifts for Formal report',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
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

      await tester.tap(find.text('Generate Formal Report'));
      await tester.pumpAndSettle();

      expect(find.text('Plan Remaining Shifts'), findsOneWidget);
      expect(find.text('Projected Total'), findsOneWidget);

      // Tap "+30m" on the first day row to guarantee at least one planned shift even on the 31st
      await tester.tap(find.byTooltip('+30m').first);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Generate Report'));
      await tester.pumpAndSettle();

      expect(mockClient.generateCallCount, equals(1));
      expect(mockClient.lastFormat, equals('docx'));
      expect(mockClient.lastPreset, equals('formal'));
      expect(mockClient.lastPlannedShifts, isNotNull);
      expect(mockClient.lastPlannedShifts!.length, equals(1));
      expect(mockClient.lastPlannedShifts!.first['durationMinutes'], equals(30));
    });
  });
}
