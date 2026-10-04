import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../clock/clock_notifier.dart';
import '../settings/settings_notifier.dart';
import '../settings/widget_sync_service.dart';
import 'shifts_notifier.dart';

class ManualShiftDialog extends ConsumerStatefulWidget {
  const ManualShiftDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const ManualShiftDialog(),
    );
  }

  @override
  ConsumerState<ManualShiftDialog> createState() => _ManualShiftDialogState();
}

class _ManualShiftDialogState extends ConsumerState<ManualShiftDialog> {
  final _formKey = GlobalKey<FormState>();

  DateTime _selectedDate = DateTime.now();
  TimeOfDay _startTime = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 17, minute: 0);

  late final TextEditingController _reasonController;
  late final TextEditingController _adminTokenController;
  bool _obscureAdminToken = true;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsProvider).value;
    _reasonController = TextEditingController();
    _adminTokenController = TextEditingController(
      text: settings?.adminToken ?? '',
    );
  }

  @override
  void dispose() {
    _reasonController.dispose();
    _adminTokenController.dispose();
    super.dispose();
  }

  DateTime _buildDateTime(DateTime date, TimeOfDay time) {
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Duration get _calculatedDuration {
    final start = _buildDateTime(_selectedDate, _startTime);
    final end = _buildDateTime(_selectedDate, _endTime);
    final diff = end.difference(start);
    return diff.isNegative ? Duration.zero : diff;
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 90)),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _selectStartTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _startTime,
    );
    if (picked != null) {
      setState(() => _startTime = picked);
    }
  }

  Future<void> _selectEndTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _endTime,
    );
    if (picked != null) {
      setState(() => _endTime = picked);
    }
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    final start = _buildDateTime(_selectedDate, _startTime);
    final end = _buildDateTime(_selectedDate, _endTime);

    if (!end.isAfter(start)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Clock-out time must be after clock-in time.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (end.difference(start).inHours > 24) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Shift duration cannot exceed 24 hours.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final repository = ref.read(timeTrackingRepositoryProvider);
      final adminToken = _adminTokenController.text.trim();

      await repository.submitManualShift(
        clockInAt: start.toUtc(),
        clockOutAt: end.toUtc(),
        reason: _reasonController.text.trim(),
        adminToken: adminToken.isNotEmpty ? adminToken : null,
      );

      final haptics =
          ref.read(settingsProvider).value?.vibrationsEnabled ?? true;
      if (haptics) {
        WidgetSyncService.vibrate();
      }

      if (mounted) {
        // Refresh both status and shift list
        ref.read(currentStatusProvider.notifier).refreshStatus();
        ref.read(shiftsProvider.notifier).refresh();

        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Past shift recorded successfully!'),
            backgroundColor: Color(0xFF0F766E),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to record shift: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('EEE, MMM d, yyyy');
    final duration = _calculatedDuration;
    final durationHours = duration.inHours;
    final durationMinutes = duration.inMinutes % 60;

    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.more_time, color: Color(0xFF0F766E)),
          SizedBox(width: 8),
          Text('Record Past Shift'),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Backfill a completed shift or repair missed clock actions.',
                  style: TextStyle(fontSize: 13, color: Colors.grey),
                ),
                const SizedBox(height: 16),

                // Date Selector Tile
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.calendar_today, color: Color(0xFF0F766E)),
                  title: const Text('Shift Date', style: TextStyle(fontSize: 13)),
                  subtitle: Text(
                    dateFormat.format(_selectedDate),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  trailing: const Icon(Icons.edit_calendar, size: 20),
                  onTap: _selectDate,
                ),
                const Divider(),

                // Start and End Time Pickers
                Row(
                  children: [
                    Expanded(
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Clock In', style: TextStyle(fontSize: 12)),
                        subtitle: Text(
                          _startTime.format(context),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        trailing: const Icon(Icons.access_time, size: 18),
                        onTap: _selectStartTime,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Clock Out', style: TextStyle(fontSize: 12)),
                        subtitle: Text(
                          _endTime.format(context),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        trailing: const Icon(Icons.access_time, size: 18),
                        onTap: _selectEndTime,
                      ),
                    ),
                  ],
                ),

                // Duration preview chip
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F766E).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Total Shift Duration:',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                      ),
                      Text(
                        '${durationHours}h ${durationMinutes}m',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F766E),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Reason input
                TextFormField(
                  controller: _reasonController,
                  decoration: const InputDecoration(
                    labelText: 'Reason for manual backfill',
                    hintText: 'e.g. Forgot phone at home, network failure',
                    border: OutlineInputBorder(),
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'Reason is required for audit logs';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Admin Token input
                TextFormField(
                  controller: _adminTokenController,
                  obscureText: _obscureAdminToken,
                  decoration: InputDecoration(
                    labelText: 'Admin API Token',
                    hintText: 'Bearer token with admin permissions',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureAdminToken
                            ? Icons.visibility
                            : Icons.visibility_off,
                      ),
                      onPressed: () => setState(
                        () => _obscureAdminToken = !_obscureAdminToken,
                      ),
                    ),
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'Admin token is required';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0F766E),
            foregroundColor: Colors.white,
          ),
          onPressed: _isSubmitting ? null : _handleSubmit,
          child: _isSubmitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Record Shift'),
        ),
      ],
    );
  }
}
