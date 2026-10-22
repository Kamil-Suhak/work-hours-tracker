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
  late DateTime _formalMonth;
  late DateTime _startDate;
  late DateTime _endDate;
  DateTime? _selectedExcelMonth;

  bool _isGeneratingFormal = false;
  bool _isGeneratingExcel = false;
  bool _isDownloadingLatest = false;
  String? _lastFormalReportPath;
  String? _lastExcelReportPath;
  String? _statusMessage;

  final DateFormat _displayFormat = DateFormat('MMM d, yyyy');
  final DateFormat _monthFormat = DateFormat('MMMM yyyy');

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _formalMonth = DateTime(now.year, now.month, 1);
    _selectedExcelMonth = DateTime(now.year, now.month, 1);
    _startDate = DateTime(now.year, now.month, 1);
    _endDate = DateTime(now.year, now.month + 1, 0);
  }

  List<DateTime> _getLast6Months() {
    final now = DateTime.now();
    return List.generate(6, (index) {
      return DateTime(now.year, now.month - index, 1);
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
        _selectedExcelMonth = null;
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
        _selectedExcelMonth = null;
      });
    }
  }

  Future<void> _promptAndGenerateFormalReport() async {
    final now = DateTime.now();
    final isCurrentMonth =
        _formalMonth.year == now.year && _formalMonth.month == now.month;

    List<Map<String, dynamic>>? plannedShifts;
    if (isCurrentMonth) {
      final clockState = ref.read(currentStatusProvider).value;
      final recordedMinutes = (clockState?.monthSeconds ?? 0) ~/ 60;

      plannedShifts = await showDialog<List<Map<String, dynamic>>>(
        context: context,
        builder: (ctx) => PlanFutureShiftsDialog(
          now: now,
          recordedMonthMinutes: recordedMinutes,
        ),
      );

      if (plannedShifts == null || !mounted) return;
    }

    setState(() {
      _isGeneratingFormal = true;
      _statusMessage = null;
    });

    try {
      final apiClient = ref.read(apiClientProvider);
      final formalStart = DateTime(_formalMonth.year, _formalMonth.month, 1);
      final formalEnd = DateTime(_formalMonth.year, _formalMonth.month + 1, 0);

      final result = await apiClient.generateReport(
        startDate: formalStart,
        endDate: formalEnd,
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
        _lastFormalReportPath = path;
        _statusMessage =
            'Generated formal report: ${h}h ${m}m (${result.totalShifts} days)';
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
        _lastExcelReportPath = path;
        _statusMessage =
            'Generated Excel report: ${h}h ${m}m (${result.totalShifts} shifts)';
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

  Future<void> _openReport(String path) async {
    final opened =
        await ref.read(reportFileServiceProvider).openReportFile(path);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(opened ? 'Opening report...' : 'Could not open report file.'),
          backgroundColor:
              opened ? const Color(0xFF0F766E) : Colors.amber[800],
          duration: const Duration(seconds: 2),
        ),
      );
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
              content:
                  Text('No automated monthly report available in storage yet.'),
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
        _lastExcelReportPath = path;
        _statusMessage =
            'Downloaded automated archive: ${latest['month'] ?? cleanName}';
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
    const slateDark = Color(0xFF1E293B);
    const slateBackground = Color(0xFF0F172A);

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
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1300),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 768;
                if (isWide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _buildFormalReportCard(context)),
                      const SizedBox(width: 20),
                      Expanded(child: _buildExcelReportCard(context)),
                    ],
                  );
                } else {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildFormalReportCard(context),
                      const SizedBox(height: 20),
                      _buildExcelReportCard(context),
                    ],
                  );
                }
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFormalReportCard(BuildContext context) {
    const indigoAccent = Color(0xFF6366F1);
    const slateDark = Color(0xFF1E293B);
    final isBusy = _isGeneratingFormal || _isGeneratingExcel;

    final formalStart = DateTime(_formalMonth.year, _formalMonth.month, 1);
    final formalEnd = DateTime(_formalMonth.year, _formalMonth.month + 1, 0);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: slateDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.description_outlined,
                  size: 20, color: indigoAccent),
              SizedBox(width: 8),
              Text(
                'FORMAL CONTRACT REPORT',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF94A3B8),
                  letterSpacing: 1.1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Populates the contract annex & invoice with your signature, recorded shifts, and planned shifts for the rest of the month.',
            style: TextStyle(
                fontSize: 13, color: Color(0xFF94A3B8), height: 1.4),
          ),
          const SizedBox(height: 20),

          // Month Dropdown
          DropdownButtonFormField<DateTime>(
            key: const Key('formal_month_dropdown'),
            initialValue: _formalMonth,
            decoration: InputDecoration(
              labelText: 'Select Month',
              labelStyle: const TextStyle(
                  color: Color(0xFF94A3B8), fontSize: 13),
              prefixIcon: const Icon(Icons.calendar_month,
                  size: 18, color: indigoAccent),
              filled: true,
              fillColor: const Color(0xFF0F172A),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFF334155)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFF334155)),
              ),
            ),
            dropdownColor: const Color(0xFF1E293B),
            items: _getLast6Months().map((m) {
              return DropdownMenuItem<DateTime>(
                value: m,
                child: Text(
                  _monthFormat.format(m),
                  style:
                      const TextStyle(color: Colors.white, fontSize: 14),
                ),
              );
            }).toList(),
            onChanged: isBusy
                ? null
                : (val) {
                    if (val != null) {
                      setState(() {
                        _formalMonth = val;
                      });
                    }
                  },
          ),
          const SizedBox(height: 16),

          // Consistent Side-by-side Start & End Date Display (Locked)
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
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
                          Icon(Icons.calendar_today,
                              size: 14, color: indigoAccent),
                          SizedBox(width: 6),
                          Text(
                            'Start Date',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF94A3B8),
                            ),
                          ),
                          Spacer(),
                          Icon(Icons.lock_outline,
                              size: 13, color: Color(0xFF64748B)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _displayFormat.format(formalStart),
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
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
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
                          Icon(Icons.event,
                              size: 14, color: indigoAccent),
                          SizedBox(width: 6),
                          Text(
                            'End Date',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF94A3B8),
                            ),
                          ),
                          Spacer(),
                          Icon(Icons.lock_outline,
                              size: 13, color: Color(0xFF64748B)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _displayFormat.format(formalEnd),
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
            ],
          ),
          const SizedBox(height: 24),

          // Reasonably Sized Generate Button Centered
          Center(
            child: SizedBox(
              width: 280,
              child: ElevatedButton.icon(
                key: const Key('generate_formal_report_button'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: indigoAccent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: isBusy ? null : _promptAndGenerateFormalReport,
                icon: _isGeneratingFormal
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.assignment_turned_in_outlined,
                        size: 20),
                label: const Text(
                  'Generate Formal Report',
                  style: TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 14),
                ),
              ),
            ),
          ),

          if (_lastFormalReportPath != null) ...[
            const SizedBox(height: 12),
            Center(
              child: SizedBox(
                width: 280,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: indigoAccent,
                    side:
                        const BorderSide(color: indigoAccent, width: 1.5),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => _openReport(_lastFormalReportPath!),
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: const Text(
                    'Open Last Report',
                    style: TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                ),
              ),
            ),
          ],

          if (_statusMessage != null && _lastFormalReportPath != null) ...[
            const SizedBox(height: 14),
            Center(
              child: Text(
                _statusMessage!,
                style: const TextStyle(
                    fontSize: 12, color: Color(0xFF94A3B8)),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildExcelReportCard(BuildContext context) {
    const activeColor = Color(0xFF10B981);
    const slateDark = Color(0xFF1E293B);
    final isBusy = _isGeneratingFormal || _isGeneratingExcel;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: slateDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.table_chart_outlined,
                  size: 20, color: activeColor),
              SizedBox(width: 8),
              Text(
                'EXCEL DATA REPORT',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF94A3B8),
                  letterSpacing: 1.1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Full breakdown with timestamps, durations, locations, sources, shift notes & summary statistics.',
            style: TextStyle(
                fontSize: 13, color: Color(0xFF94A3B8), height: 1.4),
          ),
          const SizedBox(height: 20),

          // Month Dropdown
          DropdownButtonFormField<DateTime>(
            key: const Key('excel_month_dropdown'),
            initialValue: _selectedExcelMonth,
            decoration: InputDecoration(
              labelText: 'Quick Select Month',
              labelStyle: const TextStyle(
                  color: Color(0xFF94A3B8), fontSize: 13),
              prefixIcon: const Icon(Icons.calendar_month,
                  size: 18, color: activeColor),
              filled: true,
              fillColor: const Color(0xFF0F172A),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFF334155)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFF334155)),
              ),
            ),
            dropdownColor: const Color(0xFF1E293B),
            items: _getLast6Months().map((m) {
              return DropdownMenuItem<DateTime>(
                value: m,
                child: Text(
                  _monthFormat.format(m),
                  style:
                      const TextStyle(color: Colors.white, fontSize: 14),
                ),
              );
            }).toList(),
            onChanged: isBusy
                ? null
                : (val) {
                    if (val != null) {
                      setState(() {
                        _selectedExcelMonth = val;
                        _startDate = DateTime(val.year, val.month, 1);
                        _endDate = DateTime(val.year, val.month + 1, 0);
                      });
                    }
                  },
          ),
          const SizedBox(height: 16),

          // Side-by-side Start & End Date Pickers
          Row(
            children: [
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: isBusy ? null : _selectStartDate,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
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
                            Icon(Icons.calendar_today,
                                size: 14, color: activeColor),
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
              const SizedBox(width: 12),
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: isBusy ? null : _selectEndDate,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
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
                            Icon(Icons.event,
                                size: 14, color: activeColor),
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
          const SizedBox(height: 24),

          // Reasonably Sized Generate Button Centered
          Center(
            child: SizedBox(
              width: 280,
              child: ElevatedButton.icon(
                key: const Key('generate_excel_report_button'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: activeColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: isBusy ? null : _generateExcelReport,
                icon: _isGeneratingExcel
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.table_view, size: 20),
                label: const Text(
                  'Generate Excel Report',
                  style: TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 14),
                ),
              ),
            ),
          ),

          if (_lastExcelReportPath != null) ...[
            const SizedBox(height: 12),
            Center(
              child: SizedBox(
                width: 280,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: activeColor,
                    side:
                        const BorderSide(color: activeColor, width: 1.5),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => _openReport(_lastExcelReportPath!),
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: const Text(
                    'Open Last Report',
                    style: TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                ),
              ),
            ),
          ],

          if (_statusMessage != null && _lastExcelReportPath != null) ...[
            const SizedBox(height: 14),
            Center(
              child: Text(
                _statusMessage!,
                style: const TextStyle(
                    fontSize: 12, color: Color(0xFF94A3B8)),
                textAlign: TextAlign.center,
              ),
            ),
          ],

          const SizedBox(height: 24),
          const Divider(color: Color(0xFF334155)),
          const SizedBox(height: 16),

          // Automated Storage Archive section
          Center(
            child: Column(
              children: [
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF38BDF8),
                    side: const BorderSide(
                        color: Color(0xFF38BDF8), width: 1.2),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed:
                      _isDownloadingLatest ? null : _downloadLatestMonth,
                  icon: _isDownloadingLatest
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Color(0xFF38BDF8)),
                        )
                      : const Icon(Icons.cloud_download_outlined,
                          size: 18, color: Color(0xFF38BDF8)),
                  label: const Text(
                    'Download Latest Automated Report',
                    style: TextStyle(
                      color: Color(0xFF38BDF8),
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Retrieve the scheduled monthly archive automatically generated on the 1st of the month',
                  style:
                      TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Dialog for planning remaining shifts in the current month before generating
/// the formal contract report.
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                    const Text('+',
                        style:
                            TextStyle(color: Color(0xFF64748B), fontSize: 14)),
                    _buildStatColumn(
                      label: 'Planned',
                      value: _formatHoursMinutes(plannedMins),
                      color: indigoAccent,
                    ),
                    const Text('=',
                        style:
                            TextStyle(color: Color(0xFF64748B), fontSize: 14)),
                    _buildStatColumn(
                      label: 'Projected Total',
                      value: _formatHoursMinutes(projectedMins),
                      color: activeColor,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Bulk Action Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: indigoAccent,
                        side: const BorderSide(color: Color(0xFF334155)),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () => _fillWeekdays(480),
                      child: const Text('Weekdays 8h',
                          style: TextStyle(fontSize: 11)),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: indigoAccent,
                        side: const BorderSide(color: Color(0xFF334155)),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () => _fillWeekdays(360),
                      child: const Text('Weekdays 6h',
                          style: TextStyle(fontSize: 11)),
                    ),
                  ),
                  const SizedBox(width: 6),
                  TextButton(
                    onPressed: _clearAll,
                    child: const Text('Clear',
                        style: TextStyle(
                            fontSize: 11, color: Color(0xFF94A3B8))),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Scrollable list of days
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
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: slateBg,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: mins > 0
                              ? indigoAccent
                              : const Color(0xFF334155),
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
                            constraints: const BoxConstraints(
                                minWidth: 26, minHeight: 26),
                            icon: const Icon(Icons.remove_circle_outline,
                                size: 18, color: Color(0xFF94A3B8)),
                            tooltip: '-30m',
                            onPressed: mins > 0
                                ? () => _adjustDayMinutes(key, -30)
                                : null,
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                                minWidth: 26, minHeight: 26),
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
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: _submit,
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text(
                      'Generate Report',
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

  Widget _buildDurationChip(
      String key, String label, int minutes, bool selected) {
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
