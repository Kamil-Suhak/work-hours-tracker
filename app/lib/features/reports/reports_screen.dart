import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../clock/clock_notifier.dart';
import '../../services/platform/platform_services.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  late DateTime _startDate;
  late DateTime _endDate;

  bool _isGeneratingFormal = false;
  bool _isGeneratingExcel = false;
  bool _isDownloadingLatest = false;
  String? _lastGeneratedPath;
  String? _statusMessage;

  final DateFormat _displayFormat = DateFormat('MMM d, yyyy');

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _startDate = DateTime(now.year, now.month, 1);
    _endDate = now;
  }

  void _setThisMonth() {
    final now = DateTime.now();
    setState(() {
      _startDate = DateTime(now.year, now.month, 1);
      _endDate = now;
    });
  }

  void _setLastMonth() {
    final now = DateTime.now();
    setState(() {
      _startDate = DateTime(now.year, now.month - 1, 1);
      _endDate = DateTime(now.year, now.month, 0);
    });
  }

  Future<void> _selectStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() {
        _startDate = picked;
        if (_endDate.isBefore(_startDate)) {
          _endDate = _startDate;
        }
      });
    }
  }

  Future<void> _selectEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate.isBefore(_startDate) ? _startDate : _endDate,
      firstDate: _startDate,
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() {
        _endDate = picked;
      });
    }
  }

  Future<void> _promptAndGenerateFormalReport() async {
    final clockState = ref.read(currentStatusProvider).value;
    final recordedMinutes = (clockState?.monthSeconds ?? 0) ~/ 60;

    final plannedShifts = await showDialog<List<Map<String, dynamic>>>(
      context: context,
      builder: (ctx) => PlanFutureShiftsDialog(
        now: DateTime.now(),
        recordedMonthMinutes: recordedMinutes,
      ),
    );

    if (plannedShifts == null || !mounted) return;

    setState(() {
      _isGeneratingFormal = true;
      _statusMessage = null;
    });

    try {
      final apiClient = ref.read(apiClientProvider);
      final result = await apiClient.generateReport(
        format: 'docx',
        preset: 'formal',
        plannedShifts: plannedShifts,
      );

      final path = await ref.read(reportFileServiceProvider).saveAndOpenReport(
        bytes: result.bytes,
        filename: result.filename,
      );

      final totalMinutes = (result.totalHours * 60).round();
      final h = totalMinutes ~/ 60;
      final m = totalMinutes % 60;

      setState(() {
        _lastGeneratedPath = path;
        _statusMessage = 'Generated formal report: ${h}h ${m}m (${result.totalShifts} days)';
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Formal report generated: ${result.filename}'),
            backgroundColor: const Color(0xFF0F766E),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to generate formal report: $e'),
            backgroundColor: Colors.red[800],
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isGeneratingFormal = false);
      }
    }
  }

  Future<void> _generateExcelReport() async {
    setState(() {
      _isGeneratingExcel = true;
      _statusMessage = null;
    });

    try {
      final apiClient = ref.read(apiClientProvider);
      final result = await apiClient.generateReport(
        startDate: _startDate,
        endDate: _endDate,
        format: 'xlsx',
        preset: 'full',
      );

      final path = await ref.read(reportFileServiceProvider).saveAndOpenReport(
        bytes: result.bytes,
        filename: result.filename,
      );

      final totalMinutes = (result.totalHours * 60).round();
      final h = totalMinutes ~/ 60;
      final m = totalMinutes % 60;

      setState(() {
        _lastGeneratedPath = path;
        _statusMessage = 'Generated Excel report: ${h}h ${m}m (${result.totalShifts} shifts)';
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Report generated: ${result.filename}'),
            backgroundColor: const Color(0xFF0F766E),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to generate report: $e'),
            backgroundColor: Colors.red[800],
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isGeneratingExcel = false);
      }
    }
  }

  Future<void> _openLastReport() async {
    if (_lastGeneratedPath != null) {
      final opened =
          await ref.read(reportFileServiceProvider).openReportFile(_lastGeneratedPath!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(opened
                ? 'Opening report...'
                : 'Could not open report file.'),
            backgroundColor: opened ? const Color(0xFF0F766E) : Colors.amber[800],
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _downloadLatestMonth() async {
    setState(() {
      _isDownloadingLatest = true;
      _statusMessage = null;
    });

    try {
      final apiClient = ref.read(apiClientProvider);
      final latest = await apiClient.getLatestReport();

      if (latest == null || latest['filename'] == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No automated monthly report available in storage yet.'),
              backgroundColor: Colors.amber,
            ),
          );
        }
        return;
      }

      final filename = latest['filename'] as String;
      final bytes = await apiClient.downloadReport(filename);

      final cleanName = filename.split('/').last;
      final path = await ref.read(reportFileServiceProvider).saveAndOpenReport(
        bytes: bytes,
        filename: cleanName,
      );

      setState(() {
        _lastGeneratedPath = path;
        _statusMessage = 'Downloaded automated archive: ${latest['month'] ?? cleanName}';
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Downloaded: $cleanName'),
            backgroundColor: const Color(0xFF0F766E),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to download latest report: $e'),
            backgroundColor: Colors.red[800],
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isDownloadingLatest = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const activeColor = Color(0xFF10B981); // Emerald
    const indigoAccent = Color(0xFF6366F1); // Indigo for Formal .docx
    const slateDark = Color(0xFF1E293B);
    const slateBackground = Color(0xFF0F172A);

    final now = DateTime.now();
    final monthFirstDay = DateTime(now.year, now.month, 1);
    final monthLastDay = DateTime(now.year, now.month + 1, 0);
    final lockedMonthLabel =
        '${_displayFormat.format(monthFirstDay)} – ${_displayFormat.format(monthLastDay)}';
    final isBusy = _isGeneratingFormal || _isGeneratingExcel;

    return Scaffold(
      backgroundColor: slateBackground,
      appBar: AppBar(
        backgroundColor: slateDark,
        elevation: 0,
        title: const Text(
          'Work Hours Reports',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Formal Monthly Contract Report (.docx) Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: slateDark,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.description_outlined, size: 18, color: indigoAccent),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'FORMAL CONTRACT REPORT (.DOCX)',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF94A3B8),
                            letterSpacing: 1.1,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: indigoAccent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'Umowa Zlecenie',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFA5B4FC),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Populates the contract annex & invoice with your signature, recorded shifts, and planned shifts for the rest of the month.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8), height: 1.4),
                  ),
                  const SizedBox(height: 12),

                  // Locked full-current-month indicator
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF334155)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.lock_outline, size: 15, color: Color(0xFF94A3B8)),
                        const SizedBox(width: 8),
                        const Text(
                          'Full Month:',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF94A3B8),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            lockedMonthLabel,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFFF8FAFC),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: indigoAccent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: isBusy ? null : _promptAndGenerateFormalReport,
                      icon: _isGeneratingFormal
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.assignment_turned_in_outlined, size: 20),
                      label: const Text(
                        'Generate Formal Report (.docx)',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // 2. Personal Excel Data Report (.xlsx) Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: slateDark,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Expanded(
                        child: Row(
                          children: [
                            Icon(Icons.table_chart_outlined, size: 18, color: activeColor),
                            SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                'EXCEL DATA REPORT (.XLSX)',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF94A3B8),
                                  letterSpacing: 1.1,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          ActionChip(
                            visualDensity: VisualDensity.compact,
                            label: const Text('This Month'),
                            backgroundColor: const Color(0xFF0F172A),
                            side: const BorderSide(color: Color(0xFF334155)),
                            labelStyle: const TextStyle(fontSize: 11, color: Colors.white),
                            onPressed: _setThisMonth,
                          ),
                          ActionChip(
                            visualDensity: VisualDensity.compact,
                            label: const Text('Last Month'),
                            backgroundColor: const Color(0xFF0F172A),
                            side: const BorderSide(color: Color(0xFF334155)),
                            labelStyle: const TextStyle(fontSize: 11, color: Colors.white),
                            onPressed: _setLastMonth,
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Full breakdown with timestamps, durations, locations, sources, shift notes & summary statistics.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                  ),
                  const SizedBox(height: 14),

                  // Side-by-side Start and End Date Pickers
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: _selectStartDate,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F172A),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFF334155)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Row(
                                  children: [
                                    Icon(Icons.calendar_today, size: 14, color: activeColor),
                                    SizedBox(width: 6),
                                    Text(
                                      'Start Date',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                        color: Color(0xFF94A3B8),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _displayFormat.format(_startDate),
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFFF8FAFC),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: _selectEndDate,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F172A),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFF334155)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Row(
                                  children: [
                                    Icon(Icons.event, size: 14, color: activeColor),
                                    SizedBox(width: 6),
                                    Text(
                                      'End Date',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                        color: Color(0xFF94A3B8),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _displayFormat.format(_endDate),
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFFF8FAFC),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: activeColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: isBusy ? null : _generateExcelReport,
                      icon: _isGeneratingExcel
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.table_view, size: 20),
                      label: const Text(
                        'Generate Excel Report (.xlsx)',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            if (_lastGeneratedPath != null) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: activeColor,
                  side: const BorderSide(color: activeColor, width: 1.5),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _openLastReport,
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text(
                  'Open Last Report',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
              ),
            ],

            if (_statusMessage != null) ...[
              const SizedBox(height: 12),
              Center(
                child: Text(
                  _statusMessage!,
                  style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                ),
              ),
            ],

            const SizedBox(height: 20),
            const Divider(color: Color(0xFF334155)),
            const SizedBox(height: 8),

            // Automated Storage Archive section
            Center(
              child: TextButton.icon(
                onPressed: _isDownloadingLatest ? null : _downloadLatestMonth,
                icon: _isDownloadingLatest
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: activeColor),
                      )
                    : const Icon(Icons.cloud_download_outlined, color: activeColor),
                label: const Text(
                  'Download Latest Month (.xlsx)',
                  style: TextStyle(color: activeColor, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Dialog for planning remaining shifts in the current month before generating
/// the formal `.docx` contract report.
class PlanFutureShiftsDialog extends StatefulWidget {
  final DateTime now;
  final int recordedMonthMinutes;

  const PlanFutureShiftsDialog({
    super.key,
    required this.now,
    required this.recordedMonthMinutes,
  });

  @override
  State<PlanFutureShiftsDialog> createState() => _PlanFutureShiftsDialogState();
}

class _PlanFutureShiftsDialogState extends State<PlanFutureShiftsDialog> {
  late final List<DateTime> _remainingDays;
  late final Map<String, int> _minutesByDate;
  final DateFormat _dayLabelFormat = DateFormat('EEE, MMM d');

  @override
  void initState() {
    super.initState();
    final year = widget.now.year;
    final month = widget.now.month;
    final lastDay = DateTime(year, month + 1, 0).day;

    // Include today through the last day of the current month so the user can
    // plan today's upcoming shift as well as remaining days (e.g. 26th–31st).
    _remainingDays = [
      for (int d = widget.now.day; d <= lastDay; d++) DateTime(year, month, d),
    ];
    _minutesByDate = {
      for (final day in _remainingDays) _formatYmd(day): 0,
    };
  }

  static String _formatYmd(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  static String _formatHoursMinutes(int totalMinutes) {
    final h = totalMinutes ~/ 60;
    final m = totalMinutes % 60;
    return '${h}h ${m}m';
  }

  int get _plannedTotalMinutes =>
      _minutesByDate.values.fold(0, (sum, mins) => sum + mins);

  void _fillWeekdays(int minutes) {
    setState(() {
      for (final day in _remainingDays) {
        final key = _formatYmd(day);
        final isWeekday =
            day.weekday >= DateTime.monday && day.weekday <= DateTime.friday;
        _minutesByDate[key] = isWeekday ? minutes : 0;
      }
    });
  }

  void _clearAll() {
    setState(() {
      for (final key in _minutesByDate.keys.toList()) {
        _minutesByDate[key] = 0;
      }
    });
  }

  void _adjustDayMinutes(String key, int delta) {
    setState(() {
      final next = (_minutesByDate[key] ?? 0) + delta;
      _minutesByDate[key] = next.clamp(0, 1440);
    });
  }

  void _setDayMinutes(String key, int minutes) {
    setState(() {
      _minutesByDate[key] = minutes.clamp(0, 1440);
    });
  }

  void _submit() {
    final result = <Map<String, dynamic>>[];
    for (final day in _remainingDays) {
      final key = _formatYmd(day);
      final mins = _minutesByDate[key] ?? 0;
      if (mins > 0) {
        result.add({
          'date': key,
          'durationMinutes': mins,
        });
      }
    }
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    const indigoAccent = Color(0xFF6366F1);
    const activeColor = Color(0xFF10B981);
    const slateDark = Color(0xFF1E293B);
    const slateBg = Color(0xFF0F172A);

    final plannedMins = _plannedTotalMinutes;
    final projectedMins = widget.recordedMonthMinutes + plannedMins;

    return Dialog(
      backgroundColor: slateDark,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFF334155)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 620),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Row(
                children: [
                  Icon(Icons.event_available, color: indigoAccent, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Plan Remaining Shifts',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                'Add planned hours for the remaining days of this month to include in your formal report.',
                style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
              ),
              const SizedBox(height: 12),

              // Live Totals Bar
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: slateBg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF334155)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildStatColumn(
                      label: 'Recorded',
                      value: _formatHoursMinutes(widget.recordedMonthMinutes),
                      color: const Color(0xFF94A3B8),
                    ),
                    const Text('+', style: TextStyle(color: Color(0xFF64748B))),
                    _buildStatColumn(
                      label: 'Planned',
                      value: _formatHoursMinutes(plannedMins),
                      color: const Color(0xFFA5B4FC),
                    ),
                    const Text('=', style: TextStyle(color: Color(0xFF64748B))),
                    _buildStatColumn(
                      label: 'Projected Total',
                      value: _formatHoursMinutes(projectedMins),
                      color: activeColor,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // Quick fill presets
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  ActionChip(
                    visualDensity: VisualDensity.compact,
                    label: const Text('Weekdays 8h'),
                    backgroundColor: slateBg,
                    side: const BorderSide(color: Color(0xFF334155)),
                    labelStyle: const TextStyle(fontSize: 11, color: Colors.white),
                    onPressed: () => _fillWeekdays(480),
                  ),
                  ActionChip(
                    visualDensity: VisualDensity.compact,
                    label: const Text('Weekdays 6h'),
                    backgroundColor: slateBg,
                    side: const BorderSide(color: Color(0xFF334155)),
                    labelStyle: const TextStyle(fontSize: 11, color: Colors.white),
                    onPressed: () => _fillWeekdays(360),
                  ),
                  ActionChip(
                    visualDensity: VisualDensity.compact,
                    label: const Text('Clear All'),
                    backgroundColor: slateBg,
                    side: const BorderSide(color: Color(0xFF334155)),
                    labelStyle: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                    onPressed: _clearAll,
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Day list
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _remainingDays.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    final day = _remainingDays[index];
                    final key = _formatYmd(day);
                    final mins = _minutesByDate[key] ?? 0;
                    final isWeekend = day.weekday == DateTime.saturday ||
                        day.weekday == DateTime.sunday;

                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: slateBg,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: mins > 0 ? indigoAccent : const Color(0xFF334155),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _dayLabelFormat.format(day),
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: isWeekend
                                        ? const Color(0xFF94A3B8)
                                        : Colors.white,
                                  ),
                                ),
                                Text(
                                  mins > 0 ? _formatHoursMinutes(mins) : 'Off',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: mins > 0
                                        ? const Color(0xFFA5B4FC)
                                        : const Color(0xFF64748B),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          _buildDurationChip(key, 'Off', 0, mins == 0),
                          const SizedBox(width: 4),
                          _buildDurationChip(key, '4h', 240, mins == 240),
                          const SizedBox(width: 4),
                          _buildDurationChip(key, '6h', 360, mins == 360),
                          const SizedBox(width: 4),
                          _buildDurationChip(key, '8h', 480, mins == 480),
                          const SizedBox(width: 4),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                            icon: const Icon(Icons.remove_circle_outline,
                                size: 18, color: Color(0xFF94A3B8)),
                            tooltip: '-30m',
                            onPressed: mins > 0 ? () => _adjustDayMinutes(key, -30) : null,
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                            icon: const Icon(Icons.add_circle_outline,
                                size: 18, color: Color(0xFF94A3B8)),
                            tooltip: '+30m',
                            onPressed: () => _adjustDayMinutes(key, 30),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 14),

              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(null),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(color: Color(0xFF94A3B8)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: indigoAccent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: _submit,
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text(
                      'Generate .docx',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatColumn({
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: Color(0xFF64748B)),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildDurationChip(String key, String label, int minutes, bool selected) {
    const indigoAccent = Color(0xFF6366F1);
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => _setDayMinutes(key, minutes),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? indigoAccent : const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected ? indigoAccent : const Color(0xFF334155),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : const Color(0xFF94A3B8),
          ),
        ),
      ),
    );
  }
}
