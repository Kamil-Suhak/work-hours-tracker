import 'package:flutter/material.dart';

class PlannedShiftResult {
  final bool isCancelled;
  final Duration? duration;
  final String location;

  const PlannedShiftResult.cancelled()
      : isCancelled = true,
        duration = null,
        location = 'remote';

  const PlannedShiftResult.skipped({this.location = 'remote'})
      : isCancelled = false,
        duration = null;

  const PlannedShiftResult.selected(Duration d, {this.location = 'remote'})
      : isCancelled = false,
        duration = d;
}

class PlannedShiftDialog extends StatefulWidget {
  const PlannedShiftDialog({super.key});

  static Future<PlannedShiftResult> show(BuildContext context) async {
    final result = await showDialog<PlannedShiftResult>(
      context: context,
      barrierDismissible: true,
      builder: (_) => const PlannedShiftDialog(),
    );
    return result ?? const PlannedShiftResult.cancelled();
  }

  @override
  State<PlannedShiftDialog> createState() => _PlannedShiftDialogState();
}

class _PlannedShiftDialogState extends State<PlannedShiftDialog> {
  int? _selectedHours = 8;
  bool _isCustom = false;
  String _selectedLocation = 'remote';
  final _customController = TextEditingController();

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
  }

  Duration? _resolveDuration() {
    if (_isCustom) {
      final hours = double.tryParse(_customController.text.trim());
      if (hours != null && hours > 0 && hours <= 24) {
        return Duration(minutes: (hours * 60).round());
      }
      return null;
    }
    if (_selectedHours != null) {
      return Duration(hours: _selectedHours!);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    const emerald = Color(0xFF10B981);
    const slateBg = Color(0xFF1E293B);
    const slateBorder = Color(0xFF334155);

    final resolvedDuration = _resolveDuration();

    return AlertDialog(
      backgroundColor: slateBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: slateBorder, width: 1.2),
      ),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      actionsPadding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      title: const Row(
        children: [
          Icon(Icons.flag_outlined, color: emerald, size: 22),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Planned Shift Duration',
              style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Work Location',
              style: TextStyle(
                color: Colors.grey[400],
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                ('remote', 'Remote', Icons.home_work_outlined),
                ('in-office', 'In-Office', Icons.business_outlined),
              ].map((entry) {
                final (value, label, icon) = entry;
                final isSelected = _selectedLocation == value;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: InkWell(
                      key: Key('shift_location_$value'),
                      borderRadius: BorderRadius.circular(10),
                      onTap: () {
                        setState(() {
                          _selectedLocation = value;
                        });
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? emerald.withValues(alpha: 0.2)
                              : const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isSelected ? emerald : slateBorder,
                            width: isSelected ? 1.5 : 1.0,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              icon,
                              size: 16,
                              color: isSelected ? emerald : Colors.grey[400],
                            ),
                            const SizedBox(width: 6),
                            Text(
                              label,
                              style: TextStyle(
                                color: isSelected ? Colors.white : Colors.grey[400],
                                fontWeight:
                                    isSelected ? FontWeight.bold : FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            Text(
              'Select planned length for this shift to track countdown and notifications:',
              style: TextStyle(
                color: Colors.grey[400],
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),

            // Preset Pills: 4h, 6h, 8h
            Row(
              children: [4, 6, 8].map((hours) {
                final isSelected = !_isCustom && _selectedHours == hours;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: InkWell(
                      key: Key('shift_pill_${hours}h'),
                      borderRadius: BorderRadius.circular(10),
                      onTap: () {
                        setState(() {
                          _isCustom = false;
                          _selectedHours = hours;
                        });
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? emerald.withValues(alpha: 0.2)
                              : const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isSelected ? emerald : slateBorder,
                            width: isSelected ? 1.5 : 1.0,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            '${hours}h',
                            style: TextStyle(
                              color: isSelected ? Colors.white : Colors.grey[400],
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 12),

            // Custom Option
            InkWell(
              key: const Key('shift_pill_custom'),
              borderRadius: BorderRadius.circular(10),
              onTap: () {
                setState(() {
                  _isCustom = true;
                  _selectedHours = null;
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: _isCustom
                      ? const Color(0xFF0284C7).withValues(alpha: 0.15)
                      : const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _isCustom ? const Color(0xFF38BDF8) : slateBorder,
                    width: _isCustom ? 1.5 : 1.0,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.tune,
                      size: 16,
                      color: _isCustom ? const Color(0xFF38BDF8) : Colors.grey[500],
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Custom duration',
                      style: TextStyle(
                        color: _isCustom ? const Color(0xFF38BDF8) : Colors.grey[400],
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    if (_isCustom)
                      SizedBox(
                        width: 70,
                        height: 32,
                        child: TextField(
                          key: const Key('custom_shift_hours_input'),
                          controller: _customController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          autofocus: true,
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                          decoration: InputDecoration(
                            hintText: 'Hours',
                            hintStyle: TextStyle(color: Colors.grey[600], fontSize: 11),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            isDense: true,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                              borderSide: const BorderSide(color: Color(0xFF38BDF8)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                              borderSide: const BorderSide(color: Color(0xFF38BDF8)),
                            ),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        // Cancel (Aborts clock-in)
        TextButton(
          key: const Key('planned_shift_cancel_button'),
          onPressed: () => Navigator.of(context).pop(const PlannedShiftResult.cancelled()),
          child: const Text('Cancel', style: TextStyle(color: Color(0xFF94A3B8))),
        ),

        // Skip (Clocks in without a target)
        TextButton(
          key: const Key('planned_shift_skip_button'),
          onPressed: () => Navigator.of(context).pop(
            PlannedShiftResult.skipped(location: _selectedLocation),
          ),
          child: const Text('Skip Target', style: TextStyle(color: Color(0xFF38BDF8))),
        ),

        // Confirm
        ElevatedButton(
          key: const Key('planned_shift_confirm_button'),
          style: ElevatedButton.styleFrom(
            backgroundColor: emerald,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          ),
          onPressed: resolvedDuration != null
              ? () => Navigator.of(context).pop(
                    PlannedShiftResult.selected(
                      resolvedDuration,
                      location: _selectedLocation,
                    ),
                  )
              : null,
          child: const Text(
            'Clock In',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}
