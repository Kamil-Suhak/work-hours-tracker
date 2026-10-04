import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:work_hours_mobile/features/clock/widgets/markdown_renderer.dart';
import 'package:work_hours_mobile/features/clock/widgets/shift_notes_card.dart';

void main() {
  group('MarkdownListInputFormatter Tests', () {
    const formatter = MarkdownListInputFormatter();

    test('automatically adds bullet continuation on Enter after list item', () {
      const oldValue = TextEditingValue(
        text: '- First item',
        selection: TextSelection.collapsed(offset: 12),
      );

      const newValue = TextEditingValue(
        text: '- First item\n',
        selection: TextSelection.collapsed(offset: 13),
      );

      final result = formatter.formatEditUpdate(oldValue, newValue);

      expect(result.text, equals('- First item\n- '));
      expect(result.selection.baseOffset, equals(15));
    });

    test('exits list and removes bullet when Enter is pressed on empty bullet', () {
      const oldValue = TextEditingValue(
        text: '- Item 1\n- ',
        selection: TextSelection.collapsed(offset: 11),
      );

      const newValue = TextEditingValue(
        text: '- Item 1\n- \n',
        selection: TextSelection.collapsed(offset: 12),
      );

      final result = formatter.formatEditUpdate(oldValue, newValue);

      expect(result.text, equals('- Item 1\n\n'));
      expect(result.selection.baseOffset, equals(10));
    });

    test('does not interfere with normal non-bullet text newlines', () {
      const oldValue = TextEditingValue(
        text: 'Normal paragraph',
        selection: TextSelection.collapsed(offset: 16),
      );

      const newValue = TextEditingValue(
        text: 'Normal paragraph\n',
        selection: TextSelection.collapsed(offset: 17),
      );

      final result = formatter.formatEditUpdate(oldValue, newValue);

      expect(result.text, equals('Normal paragraph\n'));
      expect(result.selection.baseOffset, equals(17));
    });
  });

  group('ShiftNotesCard Widget & Note Sync Tests', () {
    const channel = MethodChannel('com.workhours.tracker/widget_sync');
    final List<MethodCall> syncCalls = [];

    setUp(() {
      syncCalls.clear();
      FlutterSecureStorage.setMockInitialValues({});
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
        syncCalls.add(call);
        return true;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    testWidgets('renders collapsed header by default and toggles on tap', (WidgetTester tester) async {
      final controller = TextEditingController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ShiftNotesCard(controller: controller),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Shift Notes'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);

      // Tap header to expand
      await tester.tap(find.text('Shift Notes'));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Write'), findsOneWidget);
      expect(find.text('Preview'), findsOneWidget);
    });

    testWidgets('switching between Write and Preview renders MarkdownText', (WidgetTester tester) async {
      final controller = TextEditingController(text: '# Done Tasks\n- Task 1');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ShiftNotesCard(
                controller: controller,
                isInitiallyExpanded: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsOneWidget);

      // Switch to Preview
      await tester.tap(find.text('Preview'));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsNothing);
      expect(find.byType(MarkdownText), findsOneWidget);
      expect(find.text('Done Tasks'), findsOneWidget);

      // Switch back to Write
      await tester.tap(find.text('Write'));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('markdown formatting buttons insert tokens into controller', (WidgetTester tester) async {
      final controller = TextEditingController(text: 'sample');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ShiftNotesCard(
                controller: controller,
                isInitiallyExpanded: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap Bold ('B') button
      await tester.tap(find.text('B'));
      await tester.pumpAndSettle();

      expect(controller.text, contains('**'));
    });

    testWidgets('typing debounces and syncs active note to widget channel', (WidgetTester tester) async {
      final controller = TextEditingController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ShiftNotesCard(
                controller: controller,
                isInitiallyExpanded: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Enter text
      await tester.enterText(find.byType(TextField), 'Working on report');
      await tester.pump();

      // Before 500ms debounce expires, no sync call yet
      expect(syncCalls.where((c) => c.method == 'syncActiveNote'), isEmpty);

      // Fast-forward past 500ms debounce
      await tester.pump(const Duration(milliseconds: 600));

      final noteCalls = syncCalls.where((c) => c.method == 'syncActiveNote').toList();
      expect(noteCalls, isNotEmpty);
      expect(noteCalls.last.arguments, equals({'note': 'Working on report'}));
    });

    test('clearDraft removes draft and sends empty note to widget sync channel', () async {
      await ShiftNotesCard.saveDraft('Existing draft');
      syncCalls.clear();

      await ShiftNotesCard.clearDraft();

      final saved = await ShiftNotesCard.loadSavedDraft();
      expect(saved, isNull);

      final clearSyncCalls = syncCalls.where((c) => c.method == 'syncActiveNote').toList();
      expect(clearSyncCalls, isNotEmpty);
      expect(clearSyncCalls.last.arguments, equals({'note': ''}));
    });
  });
}
