import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:work_hours_mobile/features/clock/widgets/markdown_renderer.dart';

void main() {
  group('MarkdownText Tests', () {
    testWidgets('renders headers correctly', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MarkdownText(
              markdown: '# Big Header\n## Sub Header\n### Small Header',
            ),
          ),
        ),
      );

      expect(find.text('Big Header'), findsOneWidget);
      expect(find.text('Sub Header'), findsOneWidget);
      expect(find.text('Small Header'), findsOneWidget);
    });

    testWidgets('renders bullet points correctly', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MarkdownText(
              markdown: '- First item\n* Second item',
            ),
          ),
        ),
      );

      expect(find.textContaining('First item'), findsOneWidget);
      expect(find.textContaining('Second item'), findsOneWidget);
    });

    testWidgets('renders inline bold, italic, and code formatted spans', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MarkdownText(
              markdown: 'Normal text with **bold part** and *italic part* and `code part`.',
            ),
          ),
        ),
      );

      expect(find.byType(MarkdownText), findsOneWidget);
      expect(find.textContaining('bold part'), findsOneWidget);
    });
  });
}
