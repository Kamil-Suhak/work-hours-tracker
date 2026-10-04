import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
}
