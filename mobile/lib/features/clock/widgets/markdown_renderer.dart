import 'package:flutter/material.dart';

/// Lightweight, dependency-free Markdown renderer for shift notes.
/// Supports:
/// - # Heading 1
/// - ## Heading 2
/// - ### Heading 3
/// - - Bullet list or * Bullet list
/// - **bold** inline
/// - *italic* or _italic_ inline
/// - `code` inline
class MarkdownText extends StatelessWidget {
  final String markdown;
  final TextStyle? baseStyle;
  final Color? accentColor;

  const MarkdownText({
    super.key,
    required this.markdown,
    this.baseStyle,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final defaultStyle = baseStyle ??
        const TextStyle(
          fontSize: 14,
          height: 1.5,
          color: Color(0xFFE2E8F0),
        );
    final accent = accentColor ?? const Color(0xFF10B981);

    final lines = markdown.split('\n');
    final widgets = <Widget>[];

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final trimmed = line.trim();

      if (trimmed.isEmpty) {
        widgets.add(const SizedBox(height: 8));
        continue;
      }

      if (trimmed.startsWith('# ')) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: Text(
            trimmed.substring(2).trim(),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: accent,
              letterSpacing: -0.3,
            ),
          ),
        ));
      } else if (trimmed.startsWith('## ')) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 3),
          child: Text(
            trimmed.substring(3).trim(),
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Color(0xFFF8FAFC),
            ),
          ),
        ));
      } else if (trimmed.startsWith('### ')) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 2),
          child: Text(
            trimmed.substring(4).trim(),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF94A3B8),
            ),
          ),
        ));
      } else if (trimmed.startsWith('- ') || trimmed.startsWith('* ')) {
        final content = trimmed.substring(2).trim();
        widgets.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 7, right: 8),
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent,
                ),
              ),
              Expanded(
                child: Text.rich(
                  _parseInline(content, defaultStyle, accent),
                ),
              ),
            ],
          ),
        ));
      } else {
        widgets.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Text.rich(
            _parseInline(trimmed, defaultStyle, accent),
          ),
        ));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: widgets,
    );
  }

  TextSpan _parseInline(String text, TextStyle base, Color accent) {
    final spans = <TextSpan>[];
    final regex = RegExp(r'(\*\*[^*]+\*\*|\*[^*]+\*|_[^_]+_|`[^`]+`)');

    int lastIndex = 0;
    for (final match in regex.allMatches(text)) {
      if (match.start > lastIndex) {
        spans.add(TextSpan(
          text: text.substring(lastIndex, match.start),
          style: base,
        ));
      }

      final matchedText = match.group(0)!;
      if (matchedText.startsWith('**') && matchedText.endsWith('**')) {
        spans.add(TextSpan(
          text: matchedText.substring(2, matchedText.length - 2),
          style: base.copyWith(
            fontWeight: FontWeight.bold,
            color: const Color(0xFFF8FAFC),
          ),
        ));
      } else if ((matchedText.startsWith('*') && matchedText.endsWith('*')) ||
          (matchedText.startsWith('_') && matchedText.endsWith('_'))) {
        spans.add(TextSpan(
          text: matchedText.substring(1, matchedText.length - 1),
          style: base.copyWith(fontStyle: FontStyle.italic),
        ));
      } else if (matchedText.startsWith('`') && matchedText.endsWith('`')) {
        spans.add(TextSpan(
          text: ' ${matchedText.substring(1, matchedText.length - 1)} ',
          style: base.copyWith(
            fontFamily: 'monospace',
            backgroundColor: const Color(0xFF334155),
            color: const Color(0xFF38BDF8),
            fontSize: (base.fontSize ?? 14) * 0.9,
          ),
        ));
      }

      lastIndex = match.end;
    }

    if (lastIndex < text.length) {
      spans.add(TextSpan(
        text: text.substring(lastIndex),
        style: base,
      ));
    }

    return TextSpan(children: spans);
  }
}
