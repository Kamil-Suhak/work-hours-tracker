import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'planned_shift_dialog.dart';

class ClockActionButton extends StatefulWidget {
  final bool isClockIn;
  final bool isLoading;
  final bool isEnabled;
  final void Function({
    int? offsetMinutes,
    Duration? plannedDuration,
    String location,
  }) onAction;
  final double? width;
  final EdgeInsetsGeometry? padding;

  const ClockActionButton({
    super.key,
    required this.isClockIn,
    required this.isLoading,
    required this.isEnabled,
    required this.onAction,
    this.width,
    this.padding,
  });

  @override
  State<ClockActionButton> createState() => _ClockActionButtonState();
}

class _ClockActionButtonState extends State<ClockActionButton> {
  Future<void> _triggerAction({int? offsetMinutes}) async {
    if (widget.isClockIn) {
      final planned = await PlannedShiftDialog.show(context);
      if (planned.isCancelled || !mounted) return;
      widget.onAction(
        offsetMinutes: offsetMinutes,
        plannedDuration: planned.duration,
        location: planned.location,
      );
    } else {
      widget.onAction(offsetMinutes: offsetMinutes);
    }
  }

  Future<void> _showOptionsMenu() async {
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final size = renderBox.size;
    final offset = renderBox.localToGlobal(Offset.zero);
    final rect = RelativeRect.fromLTRB(
      offset.dx,
      offset.dy + size.height + 4,
      offset.dx + size.width,
      offset.dy + size.height + 4,
    );

    final selected = await showMenu<String>(
      context: context,
      position: rect,
      color: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFF334155), width: 1.2),
      ),
      items: [
        PopupMenuItem<String>(
          value: '-5',
          child: Row(
            children: [
              const Icon(Icons.history, size: 16, color: Color(0xFF94A3B8)),
              const SizedBox(width: 10),
              const Text('-5m', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              const Spacer(),
              Text('5m ago', style: TextStyle(color: Colors.grey[500], fontSize: 11)),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: '0',
          child: Row(
            children: [
              Icon(
                widget.isClockIn ? Icons.play_arrow : Icons.stop,
                size: 16,
                color: widget.isClockIn ? const Color(0xFF10B981) : const Color(0xFFEF4444),
              ),
              const SizedBox(width: 10),
              const Text('Now', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              const Spacer(),
              Text('Exact time', style: TextStyle(color: Colors.grey[500], fontSize: 11)),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: '+5',
          child: Row(
            children: [
              const Icon(Icons.update, size: 16, color: Color(0xFF94A3B8)),
              const SizedBox(width: 10),
              const Text('+5m', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              const Spacer(),
              Text('In 5m', style: TextStyle(color: Colors.grey[500], fontSize: 11)),
            ],
          ),
        ),
        const PopupMenuDivider(height: 1),
        const PopupMenuItem<String>(
          value: 'custom',
          child: Row(
            children: [
              Icon(Icons.tune, size: 16, color: Color(0xFF38BDF8)),
              SizedBox(width: 10),
              Text('Custom...', style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ],
    );

    if (selected == null || !mounted) return;

    if (selected == 'custom') {
      final customOffset = await _showCustomOffsetDialog();
      if (customOffset != null && mounted) {
        await _triggerAction(offsetMinutes: customOffset);
      }
    } else {
      final offset = int.tryParse(selected);
      if (offset != null && mounted) {
        await _triggerAction(offsetMinutes: offset);
      }
    }
  }

  Future<int?> _showCustomOffsetDialog() async {
    final textController = TextEditingController(text: '-15');
    final timeFormat = DateFormat('HH:mm');

    return showDialog<int>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            final rawText = textController.text.trim();
            final parsedOffset = int.tryParse(rawText);
            final isOutOfRange =
                parsedOffset != null && (parsedOffset < -120 || parsedOffset > 120);
            final isValid =
                parsedOffset != null && parsedOffset >= -120 && parsedOffset <= 120;
            final now = DateTime.now();
            final targetTime =
                isValid ? now.add(Duration(minutes: parsedOffset)) : null;

            return AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: Color(0xFF334155)),
              ),
              title: Row(
                children: [
                  const Icon(Icons.tune, color: Color(0xFF38BDF8), size: 20),
                  const SizedBox(width: 8),
                  Text(
                    widget.isClockIn ? 'Custom Clock In' : 'Custom Clock Out',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    key: const Key('custom_offset_input'),
                    controller: textController,
                    keyboardType: const TextInputType.numberWithOptions(signed: true),
                    autofocus: true,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Offset (minutes)',
                      labelStyle: const TextStyle(color: Color(0xFF94A3B8)),
                      suffixText: 'min',
                      suffixStyle: const TextStyle(color: Color(0xFF64748B)),
                      helperText: 'Allowed range: -120 to +120 min (±2h)',
                      helperStyle: const TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 11,
                      ),
                      errorText: isOutOfRange
                          ? 'Limit is -120 to +120 min (±2h)'
                          : null,
                      errorStyle: const TextStyle(
                        color: Color(0xFFF59E0B),
                        fontSize: 11,
                      ),
                      filled: true,
                      fillColor: const Color(0xFF0F172A),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFF334155)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFF38BDF8)),
                      ),
                      errorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFFF59E0B)),
                      ),
                      focusedErrorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(
                          color: Color(0xFFF59E0B),
                          width: 1.5,
                        ),
                      ),
                    ),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: const [-30, -15, -5, 5, 15, 30].map((val) {
                      final isSelected = isValid && parsedOffset == val;
                      return ChoiceChip(
                        label: Text('${val > 0 ? "+$val" : val}m'),
                        selected: isSelected,
                        onSelected: (selected) {
                          if (selected) {
                            final text = val.toString();
                            textController.value = TextEditingValue(
                              text: text,
                              selection: TextSelection.collapsed(
                                offset: text.length,
                              ),
                            );
                            setDialogState(() {});
                          }
                        },
                        backgroundColor: const Color(0xFF0F172A),
                        selectedColor: const Color(0xFF0284C7),
                        labelStyle: TextStyle(
                          color: isSelected
                              ? Colors.white
                              : const Color(0xFF94A3B8),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF334155)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Target event time:',
                          style: TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 11,
                          ),
                        ),
                        Text(
                          targetTime != null
                              ? timeFormat.format(targetTime)
                              : '--:--',
                          style: TextStyle(
                            color: targetTime != null
                                ? const Color(0xFF38BDF8)
                                : const Color(0xFF64748B),
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(null),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: Color(0xFF94A3B8)),
                  ),
                ),
                ElevatedButton(
                  key: const Key('confirm_custom_offset_button'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF38BDF8),
                    foregroundColor: const Color(0xFF0F172A),
                    disabledBackgroundColor: const Color(0xFF334155),
                    disabledForegroundColor: const Color(0xFF64748B),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: isValid
                      ? () => Navigator.of(ctx).pop(parsedOffset)
                      : null,
                  child: const Text(
                    'Confirm',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.isClockIn ? const Color(0xFF10B981) : const Color(0xFFEF4444);
    final keyName = widget.isClockIn ? 'clock_in_button' : 'clock_out_button';

    return SizedBox(
      width: widget.width,
      child: Tooltip(
        message: 'Tap to ${widget.isClockIn ? "clock in" : "clock out"} • Long-press for time options (-5m, +5m, custom)',
        child: ElevatedButton(
          key: Key(keyName),
          style: ElevatedButton.styleFrom(
            backgroundColor: color,
            foregroundColor: Colors.white,
            padding: widget.padding ?? const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          onPressed: widget.isEnabled && !widget.isLoading
              ? () => _triggerAction()
              : null,
          onLongPress: widget.isEnabled && !widget.isLoading
              ? () => _showOptionsMenu()
              : null,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.isLoading)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              else
                Icon(widget.isClockIn ? Icons.play_arrow : Icons.stop, size: 20),
              const SizedBox(width: 6),
              Text(
                widget.isClockIn ? 'CLOCK IN' : 'CLOCK OUT',
                style: const TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.5),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.arrow_drop_down,
                size: 16,
                color: Colors.white.withValues(alpha: 0.8),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
