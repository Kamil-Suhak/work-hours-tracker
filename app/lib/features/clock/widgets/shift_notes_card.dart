import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../settings/widget_sync_service.dart';
import 'markdown_renderer.dart';

class ShiftNotesCard extends StatefulWidget {
  final TextEditingController controller;
  final bool isInitiallyExpanded;

  const ShiftNotesCard({
    super.key,
    required this.controller,
    this.isInitiallyExpanded = false,
  });

  static const String storageKey = 'active_shift_note';
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  static Future<String?> loadSavedDraft() async {
    return await _storage.read(key: storageKey);
  }

  static Future<void> saveDraft(String note) async {
    if (note.trim().isEmpty) {
      await _storage.delete(key: storageKey);
    } else {
      await _storage.write(key: storageKey, value: note);
    }
  }

  static Future<void> clearDraft() async {
    await _storage.delete(key: storageKey);
    await WidgetSyncService.syncActiveNote('');
  }

  @override
  State<ShiftNotesCard> createState() => _ShiftNotesCardState();
}

class _ShiftNotesCardState extends State<ShiftNotesCard> {
  late bool _isExpanded;
  bool _isPreviewMode = false;
  Timer? _syncDebounce;

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.isInitiallyExpanded;
    _loadDraft();
    widget.controller.addListener(_handleTextChange);
  }

  Future<void> _loadDraft() async {
    final saved = await ShiftNotesCard.loadSavedDraft();
    if (saved != null && saved.isNotEmpty && mounted && widget.controller.text.isEmpty) {
      setState(() {
        widget.controller.text = saved;
        // If there's an existing draft, expand automatically
        _isExpanded = true;
      });
      unawaited(WidgetSyncService.syncActiveNote(saved));
    } else if (widget.controller.text.isNotEmpty) {
      unawaited(WidgetSyncService.syncActiveNote(widget.controller.text));
    }
  }

  void _handleTextChange() {
    ShiftNotesCard.saveDraft(widget.controller.text);
    _syncDebounce?.cancel();
    _syncDebounce = Timer(const Duration(milliseconds: 500), () {
      WidgetSyncService.syncActiveNote(widget.controller.text);
    });
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    if (_syncDebounce?.isActive ?? false) {
      _syncDebounce?.cancel();
      WidgetSyncService.syncActiveNote(widget.controller.text);
    }
    widget.controller.removeListener(_handleTextChange);
    super.dispose();
  }

  void _insertMarkdown(String prefix, [String suffix = '']) {
    final text = widget.controller.text;
    final selection = widget.controller.selection;

    if (!selection.isValid || selection.isCollapsed) {
      final cursor = selection.isValid ? selection.baseOffset : text.length;
      final needsNewline = (prefix.startsWith('- ') || prefix.startsWith('#')) &&
          cursor > 0 &&
          text[cursor - 1] != '\n';
      final actualPrefix = needsNewline ? '\n$prefix' : prefix;
      final newText = text.replaceRange(cursor, cursor, '$actualPrefix$suffix');
      widget.controller.text = newText;
      widget.controller.selection =
          TextSelection.collapsed(offset: cursor + actualPrefix.length);
    } else {
      final selectedText = text.substring(selection.start, selection.end);
      final replacement = '$prefix$selectedText$suffix';
      final newText = text.replaceRange(selection.start, selection.end, replacement);
      widget.controller.text = newText;
      widget.controller.selection = TextSelection(
        baseOffset: selection.start + prefix.length,
        extentOffset: selection.start + prefix.length + selectedText.length,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasContent = widget.controller.text.trim().isNotEmpty;
    const activeColor = Color(0xFF10B981); // Emerald
    const slateDark = Color(0xFF1E293B);

    return Container(
      decoration: BoxDecoration(
        color: slateDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hasContent ? activeColor.withValues(alpha: 0.3) : const Color(0xFF334155),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header / Collapsible trigger
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () {
              setState(() => _isExpanded = !_isExpanded);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  const Icon(
                    Icons.edit_note,
                    color: activeColor,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'Shift Notes',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: Color(0xFFF8FAFC),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (hasContent)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: activeColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        'Draft saved',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: activeColor,
                        ),
                      ),
                    ),
                  const Spacer(),
                  Icon(
                    _isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    color: const Color(0xFF94A3B8),
                  ),
                ],
              ),
            ),
          ),

          // Collapsible Body
          if (_isExpanded) ...[
            const Divider(color: Color(0xFF334155), height: 1),
            Padding(
              padding: const EdgeInsets.all(14.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Tab toggle & quick markdown formatting tools
                  Row(
                    children: [
                      // Write / Preview toggle
                      Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF334155)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildTabButton('Write', !_isPreviewMode, () {
                              setState(() => _isPreviewMode = false);
                            }),
                            _buildTabButton('Preview', _isPreviewMode, () {
                              setState(() => _isPreviewMode = true);
                            }),
                          ],
                        ),
                      ),
                      const Spacer(),

                      // Markdown quick formatting buttons (only in Write mode)
                      if (!_isPreviewMode) ...[
                        _buildFormatButton('B', 'Bold', () => _insertMarkdown('**', '**')),
                        const SizedBox(width: 4),
                        _buildFormatButton('I', 'Italic', () => _insertMarkdown('*', '*')),
                        const SizedBox(width: 4),
                        _buildFormatButton('H1', 'Heading 1', () => _insertMarkdown('# ')),
                        const SizedBox(width: 4),
                        _buildFormatButton('H2', 'Heading 2', () => _insertMarkdown('## ')),
                        const SizedBox(width: 4),
                        _buildFormatButton('•', 'Bullet', () => _insertMarkdown('- ')),
                      ],
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Editor or Preview
                  if (!_isPreviewMode)
                    TextField(
                      controller: widget.controller,
                      maxLines: 5,
                      minLines: 3,
                      inputFormatters: const [
                        MarkdownListInputFormatter(),
                      ],
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFFF8FAFC),
                        height: 1.4,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Notes for this shift (tasks, reminders). Supports # H1, ## H2, **bold**, *italic*, - bullets...',
                        hintStyle: const TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 12,
                        ),
                        filled: true,
                        fillColor: const Color(0xFF0F172A),
                        contentPadding: const EdgeInsets.all(12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: Color(0xFF334155)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: Color(0xFF334155)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: activeColor),
                        ),
                      ),
                    )
                  else
                    Container(
                      constraints: const BoxConstraints(minHeight: 80),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF334155)),
                      ),
                      child: widget.controller.text.trim().isEmpty
                          ? const Text(
                              'Nothing to preview yet. Switch to Write to add notes.',
                              style: TextStyle(
                                color: Color(0xFF64748B),
                                fontSize: 12,
                                fontStyle: FontStyle.italic,
                              ),
                            )
                          : MarkdownText(
                              markdown: widget.controller.text,
                              baseStyle: const TextStyle(
                                fontSize: 13,
                                height: 1.4,
                                color: Color(0xFFE2E8F0),
                              ),
                            ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTabButton(String label, bool isSelected, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF334155) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? Colors.white : const Color(0xFF94A3B8),
          ),
        ),
      ),
    );
  }

  Widget _buildFormatButton(String symbol, String tooltip, VoidCallback onTap) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFF334155)),
          ),
          child: Text(
            symbol,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Color(0xFF94A3B8),
            ),
          ),
        ),
      ),
    );
  }
}

/// Automatically continues bullet list ("- ") on Enter or exits on empty bullet.
class MarkdownListInputFormatter extends TextInputFormatter {
  const MarkdownListInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.length == oldValue.text.length + 1 &&
        newValue.selection.isCollapsed &&
        newValue.selection.baseOffset > 0 &&
        newValue.text[newValue.selection.baseOffset - 1] == '\n') {
      final cursor = newValue.selection.baseOffset;
      final textBefore = newValue.text.substring(0, cursor - 1);
      final lastNewline = textBefore.lastIndexOf('\n');
      final currentLine = (lastNewline == -1)
          ? textBefore
          : textBefore.substring(lastNewline + 1);

      final bulletMatch = RegExp(r'^(\s*[-*]\s+)').firstMatch(currentLine);
      if (bulletMatch != null) {
        final prefix = bulletMatch.group(1)!;
        final content = currentLine.substring(prefix.length).trim();

        if (content.isEmpty) {
          // Empty bullet line: remove prefix and exit list
          final lineStart = (lastNewline == -1) ? 0 : lastNewline + 1;
          final updatedText = newValue.text.replaceRange(lineStart, cursor, '\n');
          return TextEditingValue(
            text: updatedText,
            selection: TextSelection.collapsed(offset: lineStart + 1),
          );
        } else {
          // Auto-insert bullet continuation on next line
          final continuation = prefix.startsWith(' ') ? prefix : '- ';
          final updatedText = newValue.text.replaceRange(cursor, cursor, continuation);
          return TextEditingValue(
            text: updatedText,
            selection: TextSelection.collapsed(offset: cursor + continuation.length),
          );
        }
      }
    }

    return newValue;
  }
}
