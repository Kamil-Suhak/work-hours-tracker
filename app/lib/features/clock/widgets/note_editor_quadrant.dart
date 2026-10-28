import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../settings/widget_sync_service.dart';
import 'shift_notes_card.dart';

class NoteEditorQuadrant extends StatefulWidget {
  final TextEditingController controller;
  final String title;
  final VoidCallback? onReturnToCurrentShift;
  final bool isEditingPastShift;
  final bool isReadOnly;
  final String? syncStatusText;
  final ValueChanged<String>? onChanged;

  const NoteEditorQuadrant({
    super.key,
    required this.controller,
    this.title = 'Notes | Current Shift',
    this.onReturnToCurrentShift,
    this.isEditingPastShift = false,
    this.isReadOnly = false,
    this.syncStatusText,
    this.onChanged,
  });

  @override
  State<NoteEditorQuadrant> createState() => _NoteEditorQuadrantState();
}

class _NoteEditorQuadrantState extends State<NoteEditorQuadrant> {
  Timer? _syncDebounce;
  final FocusNode _focusNode = FocusNode();
  TextSelection _lastSelection = const TextSelection.collapsed(offset: 0);

  @override
  void initState() {
    super.initState();
    _loadDraft();
    widget.controller.addListener(_handleTextChange);
  }

  Future<void> _loadDraft() async {
    final saved = await ShiftNotesCard.loadSavedDraft();
    if (saved != null &&
        saved.isNotEmpty &&
        mounted &&
        widget.controller.text.isEmpty) {
      setState(() {
        widget.controller.text = saved;
      });
      unawaited(WidgetSyncService.syncActiveNote(saved));
    } else if (widget.controller.text.isNotEmpty) {
      unawaited(WidgetSyncService.syncActiveNote(widget.controller.text));
    }
  }

  void _handleTextChange() {
    if (widget.controller.selection.isValid &&
        widget.controller.selection.baseOffset >= 0) {
      _lastSelection = widget.controller.selection;
    }
    if (!widget.isEditingPastShift) {
      ShiftNotesCard.saveDraft(widget.controller.text);
      _syncDebounce?.cancel();
      _syncDebounce = Timer(const Duration(milliseconds: 500), () {
        WidgetSyncService.syncActiveNote(widget.controller.text);
      });
    }
    widget.onChanged?.call(widget.controller.text);
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    if (!widget.isEditingPastShift && (_syncDebounce?.isActive ?? false)) {
      _syncDebounce?.cancel();
      WidgetSyncService.syncActiveNote(widget.controller.text);
    }
    widget.controller.removeListener(_handleTextChange);
    _focusNode.dispose();
    super.dispose();
  }

  void _insertMarkdown(String prefix, [String suffix = '']) {
    final text = widget.controller.text;
    final currentSelection = widget.controller.selection;
    final selection = (currentSelection.isValid && currentSelection.baseOffset >= 0)
        ? currentSelection
        : ((_lastSelection.isValid &&
                _lastSelection.baseOffset >= 0 &&
                _lastSelection.end <= text.length)
            ? _lastSelection
            : TextSelection.collapsed(offset: text.length));

    if (selection.isCollapsed) {
      final cursor = selection.baseOffset.clamp(0, text.length);
      final needsNewline =
          (prefix.startsWith('- ') ||
              prefix.startsWith('- [ ] ') ||
              prefix.startsWith('#')) &&
              cursor > 0 &&
              text[cursor - 1] != '\n';
      final actualPrefix = needsNewline ? '\n$prefix' : prefix;
      final newText = text.replaceRange(cursor, cursor, '$actualPrefix$suffix');
      final newCursorOffset = cursor + actualPrefix.length;

      widget.controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: newCursorOffset),
      );
      _lastSelection = TextSelection.collapsed(offset: newCursorOffset);
      _focusNode.requestFocus();
    } else {
      final start = selection.start.clamp(0, text.length);
      final end = selection.end.clamp(0, text.length);
      final selectedText = text.substring(start, end);
      final replacement = '$prefix$selectedText$suffix';
      final newText = text.replaceRange(start, end, replacement);
      final newSelection = suffix.isNotEmpty
          ? TextSelection(
              baseOffset: start + prefix.length,
              extentOffset: start + prefix.length + selectedText.length,
            )
          : TextSelection.collapsed(offset: start + replacement.length);

      widget.controller.value = TextEditingValue(
        text: newText,
        selection: newSelection,
      );
      _lastSelection = newSelection;
      _focusNode.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    const activeColor = Color(0xFF10B981);
    const slateDark = Color(0xFF1E293B);
    final text = widget.controller.text;
    final hasContent = text.trim().isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: slateDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hasContent
              ? activeColor.withValues(alpha: 0.3)
              : const Color(0xFF334155),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(
                  widget.isEditingPastShift ? Icons.history_edu : Icons.edit_note,
                  color: widget.isEditingPastShift
                      ? const Color(0xFF38BDF8)
                      : activeColor,
                  size: 22,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    widget.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: Color(0xFFF8FAFC),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (widget.syncStatusText != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF334155),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      widget.syncStatusText!,
                      style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFF94A3B8),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                if (widget.isEditingPastShift &&
                    widget.onReturnToCurrentShift != null) ...[
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      foregroundColor: const Color(0xFF38BDF8),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    icon: const Icon(Icons.arrow_back, size: 14),
                    label: const Text(
                      'Current Shift',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                    onPressed: widget.onReturnToCurrentShift,
                  ),
                  const SizedBox(width: 4),
                ],
                if (hasContent && !widget.isReadOnly)
                  IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    tooltip: 'Clear Note',
                    color: const Color(0xFF94A3B8),
                    onPressed: () {
                      widget.controller.clear();
                      if (!widget.isEditingPastShift) {
                        ShiftNotesCard.clearDraft();
                      }
                    },
                  ),
              ],
            ),
          ),
          const Divider(color: Color(0xFF334155), height: 1),

          // Toolbar
          Container(
            color: const Color(0xFF0F172A).withValues(alpha: 0.5),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _ToolbarButton(
                    label: 'B',
                    tooltip: 'Bold (**text**)',
                    isBold: true,
                    onTap: widget.isReadOnly
                        ? () {}
                        : () => _insertMarkdown('**', '**'),
                  ),
                  _ToolbarButton(
                    label: 'I',
                    tooltip: 'Italic (*text*)',
                    isItalic: true,
                    onTap: widget.isReadOnly
                        ? () {}
                        : () => _insertMarkdown('*', '*'),
                  ),
                  _ToolbarButton(
                    label: 'H1',
                    tooltip: 'Heading (# Title)',
                    onTap: widget.isReadOnly
                        ? () {}
                        : () => _insertMarkdown('# '),
                  ),
                  _ToolbarButton(
                    label: 'H2',
                    tooltip: 'Subheading (## Title)',
                    onTap: widget.isReadOnly
                        ? () {}
                        : () => _insertMarkdown('## '),
                  ),
                  _ToolbarButton(
                    icon: Icons.format_list_bulleted,
                    tooltip: 'Bullet List (- Item)',
                    onTap: widget.isReadOnly
                        ? () {}
                        : () => _insertMarkdown('- '),
                  ),
                  _ToolbarButton(
                    icon: Icons.check_box_outlined,
                    tooltip: 'Task Checklist (- [ ] Task)',
                    onTap: widget.isReadOnly
                        ? () {}
                        : () => _insertMarkdown('- [ ] '),
                  ),
                  _ToolbarButton(
                    icon: Icons.code,
                    tooltip: 'Code Block (```)',
                    onTap: widget.isReadOnly
                        ? () {}
                        : () => _insertMarkdown('```\n', '\n```'),
                  ),
                ],
              ),
            ),
          ),
          const Divider(color: Color(0xFF334155), height: 1),

          // Multi-line editor body
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: TextField(
                controller: widget.controller,
                focusNode: _focusNode,
                readOnly: widget.isReadOnly,
                maxLines: null,
                expands: true,
                maxLength: 4000,
                maxLengthEnforcement: MaxLengthEnforcement.enforced,
                inputFormatters: const [
                  MarkdownListInputFormatter(),
                ],
                textAlignVertical: TextAlignVertical.top,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  fontFamily: 'monospace',
                  color: Color(0xFFF1F5F9),
                ),
                cursorColor: activeColor,
                decoration: InputDecoration(
                  hintText: widget.isReadOnly
                      ? 'Clock in to start notes for your shift, or select a past shift to view and edit notes.'
                      : '# Shift Objectives\n- Document tasks completed\n- Record milestones and blockers\n- Format notes in Markdown...',
                  hintStyle: const TextStyle(
                    fontSize: 13,
                    fontFamily: 'monospace',
                    color: Color(0xFF475569),
                    height: 1.5,
                  ),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  final String? label;
  final IconData? icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool isBold;
  final bool isItalic;

  const _ToolbarButton({
    this.label,
    this.icon,
    required this.tooltip,
    required this.onTap,
    this.isBold = false,
    this.isItalic = false,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          margin: const EdgeInsets.symmetric(horizontal: 2),
          child: icon != null
              ? Icon(icon, size: 16, color: const Color(0xFFCBD5E1))
              : Text(
                  label!,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
                    fontStyle: isItalic ? FontStyle.italic : FontStyle.normal,
                    color: const Color(0xFFCBD5E1),
                  ),
                ),
        ),
      ),
    );
  }
}
