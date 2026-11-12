import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../../api/models.dart';

/// Result returned from [ShiftTargetDialog].
class ShiftTargetDialogResult {
  final int? targetMinutes;
  final bool clearTarget;

  const ShiftTargetDialogResult._({
    this.targetMinutes,
    this.clearTarget = false,
  });

  const ShiftTargetDialogResult.setMinutes(int minutes)
      : this._(targetMinutes: minutes, clearTarget: false);

  const ShiftTargetDialogResult.clear()
      : this._(targetMinutes: null, clearTarget: true);
}

/// Modal dialog for setting a custom total shift target duration or removing
/// auto-stop for an active shift.
class ShiftTargetDialog extends StatefulWidget {
  final DateTime activeSince;
  final DateTime? currentTargetUtc;

  const ShiftTargetDialog({
    super.key,
    required this.activeSince,
    this.currentTargetUtc,
  });

  static Future<ShiftTargetDialogResult?> show(
    BuildContext context, {
    required DateTime activeSince,
    DateTime? currentTargetUtc,
  }) {
    return showDialog<ShiftTargetDialogResult>(
      context: context,
      builder: (ctx) => ShiftTargetDialog(
        activeSince: activeSince,
        currentTargetUtc: currentTargetUtc,
      ),
    );
  }

  @override
  State<ShiftTargetDialog> createState() => _ShiftTargetDialogState();
}

class _ShiftTargetDialogState extends State<ShiftTargetDialog> {
  static const List<int> _presetMinutes = [60, 120, 240, 360, 480];
  late final TextEditingController _hoursController;
  late final TextEditingController _minutesController;

  @override
  void initState() {
    super.initState();
    final initialTotalMinutes = _deriveInitialMinutes();
    _hoursController = TextEditingController(
      text: (initialTotalMinutes ~/ 60).toString(),
    );
    _minutesController = TextEditingController(
      text: (initialTotalMinutes % 60).toString(),
    );
  }

  int _deriveInitialMinutes() {
    if (widget.currentTargetUtc != null) {
      final diff = widget.currentTargetUtc!
          .difference(widget.activeSince)
          .inMinutes
          .clamp(1, 1440);
      return diff;
    }
    final elapsedMinutes = DateTime.now()
        .difference(widget.activeSince.toLocal())
        .inMinutes;
    final defaultMinutes = (elapsedMinutes + 60).clamp(60, 480);
    return defaultMinutes;
  }

  @override
  void dispose() {
    _hoursController.dispose();
    _minutesController.dispose();
    super.dispose();
  }

  int? get _parsedTotalMinutes {
    final hText = _hoursController.text.trim();
    final mText = _minutesController.text.trim();
    final hours = hText.isEmpty ? 0 : int.tryParse(hText);
    final minutes = mText.isEmpty ? 0 : int.tryParse(mText);
    if (hours == null || minutes == null || hours < 0 || minutes < 0 || minutes > 59) {
      return null;
    }
    return hours * 60 + minutes;
  }

  String? _validationError(int? totalMinutes, DateTime startMinute, DateTime nowMinute) {
    if (totalMinutes == null) {
      return 'Enter whole hours (0-24) and minutes (0-59).';
    }
    if (totalMinutes < 1) {
      return 'Target duration must be at least 1 minute.';
    }
    if (totalMinutes > 1440) {
      return 'Maximum shift target duration is 24 hours.';
    }
    final proposedEnd = startMinute.add(Duration(minutes: totalMinutes));
    if (!proposedEnd.isAfter(nowMinute)) {
      return 'Target end time must be in the future.';
    }
    return null;
  }

  void _applyPreset(int totalMinutes) {
    setState(() {
      _hoursController.text = (totalMinutes ~/ 60).toString();
      _minutesController.text = (totalMinutes % 60).toString();
    });
  }

  String _formatTargetDayLabel(DateTime startLocal, DateTime endLocal) {
    final startDay = DateTime(startLocal.year, startLocal.month, startLocal.day);
    final endDay = DateTime(endLocal.year, endLocal.month, endLocal.day);
    final timeStr = DateFormat('HH:mm').format(endLocal);
    if (endDay.isAfter(startDay)) {
      return 'Auto-stops tomorrow at $timeStr';
    }
    return 'Auto-stops at $timeStr';
  }

  @override
  Widget build(BuildContext context) {
    const surfaceDark = Color(0xFF0F172A);
    const cardDark = Color(0xFF1E293B);
    const emerald = Color(0xFF10B981);
    const borderSlate = Color(0xFF334155);

    final startLocal = truncateToMinute(widget.activeSince.toLocal());
    final nowLocal = truncateToMinute(DateTime.now());
    final totalMinutes = _parsedTotalMinutes;
    final error = _validationError(totalMinutes, startLocal, nowLocal);
    final proposedEndLocal =
        totalMinutes != null ? startLocal.add(Duration(minutes: totalMinutes)) : null;
    final inputsBlank = _hoursController.text.trim().isEmpty &&
        _minutesController.text.trim().isEmpty;

    return AlertDialog(
      backgroundColor: surfaceDark,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: borderSlate, width: 1.2),
      ),
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
      contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      actionsPadding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      title: const Row(
        children: [
          Icon(Icons.tune_rounded, color: emerald, size: 20),
          SizedBox(width: 8),
          Flexible(
            child: Text(
              'Shift Auto-Stop Target',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    error != null && !inputsBlank
                        ? Icons.warning_amber_rounded
                        : Icons.schedule_rounded,
                    size: 14,
                    color: error != null && !inputsBlank
                        ? const Color(0xFFFBBF24)
                        : const Color(0xFF94A3B8),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      inputsBlank
                          ? 'Started ${DateFormat('HH:mm').format(startLocal)}  •  Enter duration'
                          : (error ??
                              'Started ${DateFormat('HH:mm').format(startLocal)}  •  ${_formatTargetDayLabel(startLocal, proposedEndLocal!)}'),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: error != null && !inputsBlank
                            ? const Color(0xFFFBBF24)
                            : const Color(0xFF94A3B8),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _presetMinutes.map((mins) {
                  final hours = mins ~/ 60;
                  final isSelected = totalMinutes == mins;
                  final isPast =
                      !startLocal.add(Duration(minutes: mins)).isAfter(nowLocal);
                  return ChoiceChip(
                    key: Key('target_preset_${hours}h'),
                    label: Text('${hours}h'),
                    showCheckmark: false,
                    selected: isSelected,
                    onSelected: isPast ? null : (_) => _applyPreset(mins),
                    selectedColor: emerald.withValues(alpha: 0.25),
                    backgroundColor: cardDark,
                    disabledColor: cardDark.withValues(alpha: 0.45),
                    side: BorderSide(
                      color: isSelected ? emerald : borderSlate,
                      width: 1.2,
                    ),
                    labelStyle: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: isPast
                          ? const Color(0xFF64748B)
                          : (isSelected ? const Color(0xFF34D399) : Colors.white),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('target_hours_field'),
                      controller: _hoursController,
                      maxLength: 2,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Hours',
                        counterText: '',
                        labelStyle: const TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 12,
                        ),
                        filled: true,
                        fillColor: cardDark,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      key: const Key('target_minutes_field'),
                      controller: _minutesController,
                      maxLength: 2,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Minutes',
                        counterText: '',
                        labelStyle: const TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 12,
                        ),
                        filled: true,
                        fillColor: cardDark,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actionsAlignment: widget.currentTargetUtc != null
          ? MainAxisAlignment.spaceBetween
          : MainAxisAlignment.end,
      actions: [
        if (widget.currentTargetUtc != null)
          TextButton.icon(
            key: const Key('remove_target_button'),
            icon: const Icon(Icons.timer_off_outlined, size: 16),
            label: const Text('Remove Target'),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF94A3B8),
            ),
            onPressed: () => Navigator.of(context).pop(
              const ShiftTargetDialogResult.clear(),
            ),
          ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'Cancel',
                style: TextStyle(color: Color(0xFF94A3B8)),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              key: const Key('save_target_button'),
              style: FilledButton.styleFrom(
                backgroundColor: emerald,
                foregroundColor: Colors.black,
                disabledBackgroundColor: borderSlate,
                disabledForegroundColor:
                    const Color(0xFF94A3B8).withValues(alpha: 0.65),
                textStyle: const TextStyle(fontWeight: FontWeight.w700),
              ),
              onPressed: error == null && totalMinutes != null
                  ? () => Navigator.of(context).pop(
                        ShiftTargetDialogResult.setMinutes(totalMinutes),
                      )
                  : null,
              child: const Text('Save Target'),
            ),
          ],
        ),
      ],
    );
  }
}
