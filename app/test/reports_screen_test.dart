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
  String? lastPreset;
  bool? lastNotes;

  @override
  Future<({Uint8List bytes, String filename, double totalHours, int totalShifts})> generateReport({
    required DateTime startDate,
    required DateTime endDate,
    required String preset,
    bool includeNotes = false,
    bool includeStats = false,
    bool includeSource = false,
  }) async {
    generateCallCount++;
    lastPreset = preset;
    lastNotes = includeNotes;
    return (
      bytes: Uint8List.fromList([0x50, 0x4b, 0x03, 0x04]),
      filename: 'work-hours-test.xlsx',
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
        return '/data/user/0/app/cache/reports/work-hours-test.xlsx';
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
    testWidgets('renders MTD date range and Formal preset by default', (WidgetTester tester) async {
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
      expect(find.text('This Month'), findsOneWidget);
      expect(find.text('Last Month'), findsOneWidget);
      expect(find.text('Start Date'), findsOneWidget);
      expect(find.text('End Date'), findsOneWidget);
      expect(find.text('Formal'), findsOneWidget);
      expect(find.text('Full'), findsOneWidget);
      expect(find.text('Generate'), findsOneWidget);
      expect(find.text('Download Latest Month'), findsOneWidget);
    });

    testWidgets('toggling Full preset activates all checklist options', (WidgetTester tester) async {
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

      // Tap 'Full' preset
      await tester.ensureVisible(find.text('Full'));
      await tester.tap(find.text('Full'));
      await tester.pumpAndSettle();

      // Tap 'Generate'
      await tester.ensureVisible(find.text('Generate'));
      await tester.tap(find.text('Generate'));
      await tester.pumpAndSettle();

      expect(mockClient.generateCallCount, equals(1));
      expect(mockClient.lastPreset, equals('full'));
      expect(mockClient.lastNotes, isTrue);

      // 'Open' button appears after generation
      expect(find.text('Open'), findsOneWidget);
      expect(channelCalls.any((c) => c.method == 'saveAndOpenReport'), isTrue);

      // Tap 'Open' button
      await tester.ensureVisible(find.text('Open'));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(channelCalls.any((c) => c.method == 'openReportFile'), isTrue);
    });

    testWidgets('toggling Full preset and then Formal resets checklist options to false', (WidgetTester tester) async {
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

      // Tap 'Full'
      await tester.ensureVisible(find.text('Full'));
      await tester.tap(find.text('Full'));
      await tester.pumpAndSettle();

      // Verify all checkboxes are checked
      final checkboxesFull = tester.widgetList<Checkbox>(find.byType(Checkbox)).toList();
      for (final cb in checkboxesFull) {
        expect(cb.value, isTrue);
      }

      // Tap 'Formal'
      await tester.ensureVisible(find.text('Formal'));
      await tester.tap(find.text('Formal'));
      await tester.pumpAndSettle();

      // Verify all checkboxes reset to false
      final checkboxesFormal = tester.widgetList<Checkbox>(find.byType(Checkbox)).toList();
      for (final cb in checkboxesFormal) {
        expect(cb.value, isFalse);
      }
    });
  });
}
