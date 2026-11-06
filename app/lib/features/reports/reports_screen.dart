import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../api/models.dart';
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
  Map<String, dynamic>? _latestStorageReport;

  int _contractMonthlyHours = 80;
  int _monthWorkedMinutes = 0;
  List<Map<String, dynamic>> _plannedShifts = [];
  bool _isLoadingMonth = false;

  final DateFormat _displayFormat = DateFormat('MMM d, yyyy');
  final DateFormat _monthFormat = DateFormat('MMMM yyyy');

  bool get _isPastMonth {
    final now = DateTime.now();
    final firstOfCurrentMonth = DateTime(now.year, now.month, 1);
    return _formalMonth.isBefore(firstOfCurrentMonth);
  }

  int get _plannedMinutes => _plannedShifts.fold(
        0,
        (sum, s) => sum + (s['durationMinutes'] as int? ?? 0),
      );

  int get _totalFormalMinutes => _monthWorkedMinutes + _plannedMinutes;

  bool get _isFormalTargetMet {
    if (_isPastMonth) {
      return _monthWorkedMinutes == (_contractMonthlyHours * 60);
    }
    return _totalFormalMinutes == (_contractMonthlyHours * 60);
  }

  static DateTime _truncateToMinute(DateTime dt) {
    final utc = dt.toUtc();
    return DateTime.utc(
      utc.year,
      utc.month,
      utc.day,
      utc.hour,
      utc.minute,
    );
  }

  static String _formatHoursMinutes(int totalMinutes) {
    final h = totalMinutes ~/ 60;
    final m = totalMinutes % 60;
    return '${h}h ${m}m';
  }

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _formalMonth = DateTime(now.year, now.month, 1);
    _selectedExcelMonth = DateTime(now.year, now.month, 1);
    _startDate = DateTime(now.year, now.month, 1);
    _endDate = DateTime(now.year, now.month + 1, 0);
    _checkLatestStorageReport();
    _loadMonthData();
  }

  Future<void> _checkLatestStorageReport() async {
    try {
      final apiClient = ref.read(apiClientProvider);
      final latest = await apiClient.getLatestReport();
      if (mounted) {
        setState(() {
          _latestStorageReport = latest;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadMonthData() async {
    setState(() => _isLoadingMonth = true);
    try {
      final apiClient = ref.read(apiClientProvider);
      try {
        final profile = await apiClient.getContractProfile();
        if (profile['monthlyHours'] is num) {
          _contractMonthlyHours = (profile['monthlyHours'] as num).toInt();
        }
      } catch (_) {}

      final formalStart = DateTime(_formalMonth.year, _formalMonth.month, 1);
      final formalEnd =
          DateTime(_formalMonth.year, _formalMonth.month + 1, 0, 23, 59, 59);

      final now = DateTime.now();
      final isCurrentMonth =
          _formalMonth.year == now.year && _formalMonth.month == now.month;

      int workedMins = 0;
      try {
        final events =
            await apiClient.getEvents(from: formalStart, to: formalEnd);
        final sorted = List<TrackingEvent>.from(events)
          ..sort((a, b) => a.occurredAtUtc.compareTo(b.occurredAtUtc));
        TrackingEvent? pendingIn;
        for (final ev in sorted) {
          if (ev.eventType == 'clock_in') {
            pendingIn = ev;
          } else if (ev.eventType == 'clock_out' && pendingIn != null) {
            final inTime = _truncateToMinute(pendingIn.occurredAtUtc);
            final outTime = _truncateToMinute(ev.occurredAtUtc);
            final diffMins = outTime.difference(inTime).inMinutes;
            if (diffMins > 0) {
              workedMins += diffMins;
            }
            pendingIn = null;
          }
        }
      } catch (_) {}

      if (isCurrentMonth) {
        final status = ref.read(currentStatusProvider).value;
        if (status != null && status.monthSeconds > 0) {
          final statusMins = status.monthSeconds ~/ 60;
          if (statusMins > workedMins) {
            workedMins = statusMins;
          }
        }
      }

      if (mounted) {
        setState(() {
          _monthWorkedMinutes = workedMins;
          _isLoadingMonth = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingMonth = false);
    }
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

  Future<void> _openForecastDialog() async {
    if (_isPastMonth) return;
    final now = DateTime.now();
    final planned = await showDialog<List<Map<String, dynamic>>>(
      context: context,
      builder: (ctx) => PlanFutureShiftsDialog(
        month: _formalMonth,
        now: now,
        recordedMonthMinutes: _monthWorkedMinutes,
        initialPlannedShifts: _plannedShifts,
        targetMinutes: _contractMonthlyHours * 60,
      ),
    );

    if (planned != null && mounted) {
      setState(() {
        _plannedShifts = planned;
      });
    }
  }

  Future<void> _generateFormalReport() async {
    setState(() => _isGeneratingFormal = true);

    try {
      final apiClient = ref.read(apiClientProvider);
      final formalStart = DateTime(_formalMonth.year, _formalMonth.month, 1);
      final formalEnd = DateTime(_formalMonth.year, _formalMonth.month + 1, 0);

      final result = await apiClient.generateReport(
        startDate: formalStart,
        endDate: formalEnd,
        format: 'docx',
        preset: 'formal',
        plannedShifts: (!_isPastMonth && _plannedShifts.isNotEmpty)
            ? _plannedShifts
            : null,
      );

      await ref.read(reportFileServiceProvider).saveAndOpenReport(
            bytes: result.bytes,
            filename: result.filename,
          );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Formal report downloaded: ${result.filename}'),
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
    setState(() => _isGeneratingExcel = true);

    try {
      final apiClient = ref.read(apiClientProvider);
      final result = await apiClient.generateReport(
        startDate: _startDate,
        endDate: _endDate,
        format: 'xlsx',
        preset: 'full',
      );

      await ref.read(reportFileServiceProvider).saveAndOpenReport(
            bytes: result.bytes,
            filename: result.filename,
          );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Full report downloaded: ${result.filename}'),
            backgroundColor: const Color(0xFF0F766E),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to generate full report: $e'),
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

  Future<void> _downloadLatestMonth() async {
    setState(() => _isDownloadingLatest = true);

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
      await ref.read(reportFileServiceProvider).saveAndOpenReport(
            bytes: bytes,
            filename: cleanName,
          );

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
                        _plannedShifts = [];
                      });
                      _loadMonthData();
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
          const SizedBox(height: 16),

          // Contract Hours Status / Interactive Forecast Tile
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: (isBusy || _isPastMonth) ? null : _openForecastDialog,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _isFormalTargetMet
                      ? const Color(0xFF10B981)
                      : const Color(0xFFF59E0B),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _isFormalTargetMet
                        ? Icons.check_circle
                        : Icons.pending_outlined,
                    size: 20,
                    color: _isFormalTargetMet
                        ? const Color(0xFF10B981)
                        : const Color(0xFFF59E0B),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isLoadingMonth
                              ? 'Loading contract hours...'
                              : _isFormalTargetMet
                                  ? 'Contract Target Met (${_formatHoursMinutes(_isPastMonth ? _monthWorkedMinutes : _totalFormalMinutes)} / ${_contractMonthlyHours}h)'
                                  : _isPastMonth
                                      ? 'Contract Target Not Met (${_formatHoursMinutes(_monthWorkedMinutes)} / ${_contractMonthlyHours}h)'
                                      : 'Contract Target: ${_contractMonthlyHours}h (${_formatHoursMinutes(_totalFormalMinutes)} total)',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _isFormalTargetMet
                                ? const Color(0xFF10B981)
                                : const Color(0xFFF59E0B),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _isPastMonth
                              ? (_isFormalTargetMet
                                  ? 'All required contract hours recorded for this month.'
                                  : 'Past month cannot be forecasted. Check your shift history.')
                              : '${_formatHoursMinutes(_monthWorkedMinutes)} worked + ${_formatHoursMinutes(_plannedMinutes)} forecast — Tap to ${_isFormalTargetMet ? 'adjust forecast' : 'plan remaining shifts'}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF94A3B8),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!_isPastMonth)
                    const Icon(Icons.edit_calendar,
                        size: 16, color: Color(0xFF94A3B8)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Exactly 1 Function Button: Generate & Download Formal Report
          Center(
            child: SizedBox(
              width: 320,
              child: ElevatedButton.icon(
                key: const Key('generate_formal_report_button'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: indigoAccent,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: const Color(0xFF334155),
                  disabledForegroundColor: const Color(0xFF64748B),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed:
                    (_isFormalTargetMet && !isBusy) ? _generateFormalReport : null,
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
                  'Generate & Download Formal Report',
                  style: TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 13),
                ),
              ),
            ),
          ),
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

          // Function Button 1: Generate & Download Full Report
          Center(
            child: SizedBox(
              width: 320,
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
                  'Generate & Download Full Report',
                  style: TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 13),
                ),
              ),
            ),
          ),

          // Function Button 2: Download Auto-Generated Report
          if (_latestStorageReport != null) ...[
            const SizedBox(height: 20),
            const Divider(color: Color(0xFF334155)),
            const SizedBox(height: 16),
            Center(
              child: SizedBox(
                width: 320,
                child: OutlinedButton.icon(
                  key: const Key('download_latest_storage_report_button'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF38BDF8),
                    side: const BorderSide(
                        color: Color(0xFF38BDF8), width: 1.2),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed:
                      _isDownloadingLatest ? null : _downloadLatestMonth,
                  icon: _isDownloadingLatest
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Color(0xFF38BDF8)),
                        )
                      : const Icon(Icons.cloud_download_outlined,
                          size: 20, color: Color(0xFF38BDF8)),
                  label: Text(
                    'Download Auto-Generated Report (${_latestStorageReport!['month'] ?? 'Archive'})',
                    style: const TextStyle(
                      color: Color(0xFF38BDF8),
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Dialog for planning remaining shifts in the current month before generating
/// the formal contract report.
class PlanFutureShiftsDialog extends StatefulWidget {
  final DateTime month;
  final DateTime now;
  final int recordedMonthMinutes;
  final List<Map<String, dynamic>>? initialPlannedShifts;
  final int targetMinutes;

  const PlanFutureShiftsDialog({
    super.key,
    required this.month,
    required this.now,
    required this.recordedMonthMinutes,
    this.initialPlannedShifts,
    this.targetMinutes = 4800,
  });

  @override
  State<PlanFutureShiftsDialog> createState() => _PlanFutureShiftsDialogState();
}

class _PlanFutureShiftsDialogState extends State<PlanFutureShiftsDialog> {
  late final List<DateTime> _remainingDays;
  late final Map<String, int> _minutesByDate;
  late final Map<String, TextEditingController> _controllers;
  late final Map<String, FocusNode> _focusNodes;
  final DateFormat _dayLabelFormat = DateFormat('EEE, MMM d');

  @override
  void initState() {
    super.initState();
    final year = widget.month.year;
    final month = widget.month.month;
    final lastDay = DateTime(year, month + 1, 0).day;

    final isCurrent = widget.now.year == year && widget.now.month == month;
    final startDay = isCurrent ? widget.now.day : 1;

    _remainingDays = [
      for (int d = startDay; d <= lastDay; d++) DateTime(year, month, d),
    ];
    _minutesByDate = {
      for (final day in _remainingDays) _formatYmd(day): 0,
    };

    if (widget.initialPlannedShifts != null) {
      for (final item in widget.initialPlannedShifts!) {
        final d = item['date'] as String?;
        final m = item['durationMinutes'] as int?;
        if (d != null && m != null && _minutesByDate.containsKey(d)) {
          _minutesByDate[d] = m;
        }
      }
    }

    _controllers = {
      for (final day in _remainingDays)
        _formatYmd(day): TextEditingController(
          text: (_minutesByDate[_formatYmd(day)] ?? 0) > 0
              ? _formatHoursMinutes(_minutesByDate[_formatYmd(day)]!)
              : '',
        ),
    };
    _focusNodes = {
      for (final day in _remainingDays)
        _formatYmd(day): FocusNode(),
    };

    for (final entry in _focusNodes.entries) {
      entry.value.addListener(() {
        if (!entry.value.hasFocus) {
          _commitDayInput(entry.key);
        }
      });
    }
  }

  @override
  void dispose() {
    for (final node in _focusNodes.values) {
      node.dispose();
    }
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
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

  static int? _parseDurationMinutes(String raw) {
    final input = raw.trim().toLowerCase().replaceAll(',', '.');
    if (input.isEmpty) return 0;

    if (input == '0' ||
        input == '0h' ||
        input == '0m' ||
        input == '0h 0m' ||
        input == '0h0m' ||
        input == '0:00' ||
        input == '00:00') {
      return 0;
    }

    final colonMatch = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(input);
    if (colonMatch != null) {
      final h = int.tryParse(colonMatch.group(1)!) ?? 0;
      final m = int.tryParse(colonMatch.group(2)!) ?? 0;
      if (m < 60) {
        return (h * 60 + m).clamp(0, 1440);
      }
    }

    final hmMatch = RegExp(
      r'^(?:(\d+(?:\.\d+)?)\s*h)?\s*(?:(\d+)\s*m?)?$',
    ).firstMatch(input);

    if (hmMatch != null) {
      final hStr = hmMatch.group(1);
      final mStr = hmMatch.group(2);

      if (hStr != null || mStr != null) {
        if (hStr == null && mStr != null && !input.contains('m')) {
          // Fall through
        } else {
          double totalMinutes = 0;
          if (hStr != null) {
            totalMinutes += (double.tryParse(hStr) ?? 0.0) * 60;
          }
          if (mStr != null) {
            totalMinutes += (int.tryParse(mStr) ?? 0);
          }
          return totalMinutes.round().clamp(0, 1440);
        }
      }
    }

    final numVal = double.tryParse(input);
    if (numVal != null && numVal >= 0) {
      if (numVal <= 24) {
        return (numVal * 60).round().clamp(0, 1440);
      } else {
        return numVal.round().clamp(0, 1440);
      }
    }

    return null;
  }

  void _commitDayInput(String key) {
    final text = _controllers[key]?.text.trim() ?? '';
    if (text.isEmpty) {
      if (mounted) {
        setState(() {
          _minutesByDate[key] = 0;
          _controllers[key]?.text = '';
        });
      }
      return;
    }
    final parsed = _parseDurationMinutes(text);
    if (parsed != null) {
      if (mounted) {
        setState(() {
          _minutesByDate[key] = parsed;
          _controllers[key]?.text =
              parsed > 0 ? _formatHoursMinutes(parsed) : '';
        });
      }
    } else {
      final current = _minutesByDate[key] ?? 0;
      _controllers[key]?.text =
          current > 0 ? _formatHoursMinutes(current) : '';
    }
  }

  int get _plannedTotalMinutes =>
      _minutesByDate.values.fold(0, (sum, mins) => sum + mins);

  void _fillWeekdays(int minutes) {
    setState(() {
      for (final day in _remainingDays) {
        final key = _formatYmd(day);
        final isWeekday =
            day.weekday >= DateTime.monday && day.weekday <= DateTime.friday;
        final val = isWeekday ? minutes : 0;
        _minutesByDate[key] = val;
        _controllers[key]?.text = val > 0 ? _formatHoursMinutes(val) : '';
      }
    });
  }

  void _clearAll() {
    setState(() {
      for (final key in _minutesByDate.keys.toList()) {
        _minutesByDate[key] = 0;
        _controllers[key]?.text = '';
      }
    });
  }

  void _setDayMinutes(String key, int minutes) {
    setState(() {
      final clamped = minutes.clamp(0, 1440);
      _minutesByDate[key] = clamped;
      _controllers[key]?.text =
          clamped > 0 ? _formatHoursMinutes(clamped) : '';
    });
  }

  void _submit() {
    for (final day in _remainingDays) {
      final key = _formatYmd(day);
      final text = _controllers[key]?.text.trim() ?? '';
      final parsed = _parseDurationMinutes(text);
      if (parsed != null) {
        _minutesByDate[key] = parsed;
      }
    }

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
    final isTargetMet = projectedMins == widget.targetMinutes;

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
              Text(
                'Add planned hours for remaining days in ${DateFormat('MMMM yyyy').format(widget.month)} to reach your contract target (${_formatHoursMinutes(widget.targetMinutes)}).',
                style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
              ),
              const SizedBox(height: 12),

              // Live Totals Bar
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: slateBg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isTargetMet
                        ? activeColor
                        : const Color(0xFFF59E0B),
                  ),
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
                      label: isTargetMet ? 'Target Met' : 'Projected',
                      value:
                          '${_formatHoursMinutes(projectedMins)} / ${_formatHoursMinutes(widget.targetMinutes)}',
                      color: isTargetMet
                          ? activeColor
                          : const Color(0xFFF59E0B),
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
                    final isCustom = mins > 0 && mins != 240 && mins != 480;

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
                          _buildDurationChip(key, '8h', 480, mins == 480),
                          const SizedBox(width: 6),
                          SizedBox(
                            width: 68,
                            child: TextField(
                              controller: _controllers[key],
                              focusNode: _focusNodes[key],
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: isCustom
                                    ? const Color(0xFFA5B4FC)
                                    : Colors.white,
                              ),
                              decoration: InputDecoration(
                                hintText: 'custom',
                                hintStyle: const TextStyle(
                                    color: Color(0xFF64748B), fontSize: 10),
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 6),
                                filled: true,
                                fillColor: const Color(0xFF1E293B),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(6),
                                  borderSide: BorderSide(
                                    color: isCustom
                                        ? indigoAccent
                                        : const Color(0xFF334155),
                                  ),
                                ),
                              ),
                              onSubmitted: (_) => _commitDayInput(key),
                            ),
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
                      'Apply Forecast',
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
