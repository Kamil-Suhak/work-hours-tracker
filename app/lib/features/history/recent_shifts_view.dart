import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../clock/clock_notifier.dart';
import '../clock/widgets/markdown_renderer.dart';
import 'manual_shift_dialog.dart';
import 'shift_model.dart';
import 'shifts_notifier.dart';

class RecentShiftsView extends ConsumerStatefulWidget {
  final ScrollController? scrollController;
  final bool showHeader;
  final bool showDragHandle;
  final EdgeInsetsGeometry? padding;

  const RecentShiftsView({
    super.key,
    this.scrollController,
    this.showHeader = true,
    this.showDragHandle = false,
    this.padding,
  });

  @override
  ConsumerState<RecentShiftsView> createState() => _RecentShiftsViewState();
}

class _RecentShiftsViewState extends ConsumerState<RecentShiftsView> {
  ScrollController? _internalController;

  ScrollController get _effectiveController =>
      widget.scrollController ?? (_internalController ??= ScrollController());

  @override
  void dispose() {
    _internalController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shiftsAsync = ref.watch(shiftsProvider);
    const activeEmerald = Color(0xFF10B981);

    return Column(
      children: [
        if (widget.showDragHandle)
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFF334155),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        if (widget.showHeader) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.history, color: activeEmerald),
                    SizedBox(width: 8),
                    Text(
                      'Recent Shifts',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFF8FAFC),
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      tooltip: 'Record Past Shift',
                      color: activeEmerald,
                      onPressed: () => ManualShiftDialog.show(context),
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      tooltip: 'Refresh History',
                      color: const Color(0xFF94A3B8),
                      onPressed: () =>
                          ref.read(shiftsProvider.notifier).refresh(),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(color: Color(0xFF1E293B), height: 1),
        ],
        Expanded(
          child: RefreshIndicator(
            color: activeEmerald,
            backgroundColor: const Color(0xFF1E293B),
            onRefresh: () => ref.read(shiftsProvider.notifier).refresh(),
            child: shiftsAsync.when(
              data: (shifts) {
                if (shifts.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.calendar_today_outlined,
                          size: 48,
                          color: Color(0xFF475569),
                        ),
                        SizedBox(height: 12),
                        Text(
                          'No completed shifts found',
                          style: TextStyle(
                            fontSize: 16,
                            color: Color(0xFF94A3B8),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Clock in and out to record your working hours',
                          style: TextStyle(
                            fontSize: 13,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return Scrollbar(
                  controller: _effectiveController,
                  thumbVisibility: true,
                  thickness: 6,
                  radius: const Radius.circular(4),
                  child: ListView.separated(
                    controller: _effectiveController,
                    padding: widget.padding ??
                        const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 16,
                        ),
                    itemCount: shifts.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final shift = shifts[index];
                      return _buildShiftCard(context, shift);
                    },
                  ),
                );
              },
              loading: () => const Center(
                child: CircularProgressIndicator(color: activeEmerald),
              ),
              error: (err, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline,
                          color: Colors.amber, size: 40),
                      const SizedBox(height: 8),
                      const Text(
                        'Failed to load shifts',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFF8FAFC),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        err.toString(),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () =>
                            ref.read(shiftsProvider.notifier).refresh(),
                        icon: const Icon(Icons.refresh, size: 16),
                        label: const Text('Try Again'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: activeEmerald,
                          side: const BorderSide(color: activeEmerald),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildShiftCard(BuildContext context, ShiftRecord shift) {
    final dateFormat = DateFormat('EEE, MMM d, yyyy');
    final timeFormat = DateFormat('HH:mm');

    final dateLabel = dateFormat.format(shift.startTime);
    final inTime = timeFormat.format(shift.startTime);
    final outTime = timeFormat.format(shift.endTime);
    final isManual = shift.clockIn.source == 'admin_manual' ||
        shift.clockIn.reason != null;
    final hasNote = shift.hasNote;
    const activeEmerald = Color(0xFF10B981);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _showShiftNoteDialog(context, shift),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: hasNote
                  ? activeEmerald.withValues(alpha: 0.35)
                  : const Color(0xFF334155),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    dateLabel,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: Color(0xFFF8FAFC),
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: activeEmerald.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      shift.durationFormatted,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                        color: Color(0xFF34D399),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.schedule, size: 15, color: Color(0xFF64748B)),
                  const SizedBox(width: 6),
                  Text(
                    '$inTime - $outTime',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF94A3B8),
                    ),
                  ),
                  const Spacer(),
                  if (hasNote) ...[
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: activeEmerald.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.notes, size: 13, color: activeEmerald),
                          SizedBox(width: 4),
                          Text(
                            'Notes',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: activeEmerald,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  if (isManual)
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'Manual backfill',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFFBBF24),
                        ),
                      ),
                    ),
                ],
              ),
              if (shift.clockIn.reason != null &&
                  shift.clockIn.reason!.trim().isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  'Reason: ${shift.clockIn.reason}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                    color: Color(0xFF94A3B8),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showShiftNoteDialog(BuildContext context, ShiftRecord shift) {
    showDialog<void>(
      context: context,
      builder: (ctx) => _ShiftNoteDialog(shift: shift),
    );
  }
}

class _ShiftNoteDialog extends ConsumerStatefulWidget {
  final ShiftRecord shift;

  const _ShiftNoteDialog({required this.shift});

  @override
  ConsumerState<_ShiftNoteDialog> createState() => _ShiftNoteDialogState();
}

class _ShiftNoteDialogState extends ConsumerState<_ShiftNoteDialog> {
  late bool _isEditing;
  late final TextEditingController _controller;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _isEditing = false;
    _controller = TextEditingController(text: widget.shift.note ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    final noteText = _controller.text.trim();
    setState(() => _isSaving = true);

    try {
      final targetEventId = widget.shift.clockOut.id;
      final apiClient = ref.read(apiClientProvider);
      await apiClient.updateEventNote(
        eventId: targetEventId,
        note: noteText.isNotEmpty ? noteText : null,
      );
      ref.invalidate(shiftsProvider);

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Shift note saved'),
            backgroundColor: Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save note: $e'),
            backgroundColor: const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('EEEE, MMMM d, yyyy');
    final timeFormat = DateFormat('HH:mm');
    final shift = widget.shift;

    return AlertDialog(
      backgroundColor: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Color(0xFF334155)),
      ),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              _isEditing ? Icons.edit_note : Icons.description,
              color: const Color(0xFF10B981),
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isEditing ? 'Edit Shift Notes' : 'Shift Notes',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFF8FAFC),
                  ),
                ),
                Text(
                  '${dateFormat.format(shift.startTime)} (${timeFormat.format(shift.startTime)} - ${timeFormat.format(shift.endTime)})',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF94A3B8),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      content: Container(
        constraints: const BoxConstraints(maxHeight: 340),
        width: 480,
        child: SingleChildScrollView(
          child: _isEditing
              ? TextField(
                  key: const Key('shift_note_edit_field'),
                  controller: _controller,
                  maxLines: 9,
                  minLines: 5,
                  maxLength: 4000,
                  autofocus: true,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFFE2E8F0),
                    height: 1.4,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Enter Markdown notes for this shift...',
                    hintStyle: const TextStyle(color: Color(0xFF64748B)),
                    filled: true,
                    fillColor: const Color(0xFF0F172A),
                    counterStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 10),
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
                      borderSide: const BorderSide(color: Color(0xFF10B981), width: 1.5),
                    ),
                  ),
                )
              : (shift.hasNote
                  ? MarkdownText(
                      markdown: shift.note!,
                      baseStyle: const TextStyle(
                        fontSize: 13,
                        height: 1.5,
                        color: Color(0xFFE2E8F0),
                      ),
                    )
                  : Container(
                      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                      alignment: Alignment.center,
                      child: const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.note_add_outlined,
                            size: 38,
                            color: Color(0xFF64748B),
                          ),
                          SizedBox(height: 10),
                          Text(
                            'No notes from this shift.',
                            style: TextStyle(
                              fontSize: 13,
                              color: Color(0xFF94A3B8),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Tap Edit to write or backfill notes.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    )),
        ),
      ),
      actions: _isEditing
          ? [
              TextButton(
                onPressed: _isSaving ? null : () => setState(() => _isEditing = false),
                child: const Text('Cancel', style: TextStyle(color: Color(0xFF94A3B8))),
              ),
              ElevatedButton.icon(
                key: const Key('save_shift_note_button'),
                icon: _isSaving
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.check, size: 16),
                label: const Text('Save & Close'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: _isSaving ? null : _handleSave,
              ),
            ]
          : [
              OutlinedButton.icon(
                key: const Key('edit_shift_note_button'),
                icon: const Icon(Icons.edit, size: 14),
                label: Text(shift.hasNote ? 'Edit' : 'Add Note'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF10B981),
                  side: const BorderSide(color: Color(0xFF10B981)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: () => setState(() => _isEditing = true),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close', style: TextStyle(color: Color(0xFF94A3B8))),
              ),
            ],
    );
  }
}
