import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../api/api_client.dart';
import '../clock/clock_notifier.dart';
import 'report_file_service.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  late DateTime _startDate;
  late DateTime _endDate;
  String _preset = 'formal'; // 'formal' | 'full'

  // Options checklist
  bool _includeNotes = false;
  bool _includeStats = false;
  bool _includeSource = false;

  bool _isGenerating = false;
  bool _isDownloadingLatest = false;
  String? _lastGeneratedPath;
  String? _lastGeneratedFilename;
  String? _statusMessage;

  final DateFormat _dateFormat = DateFormat('yyyy-MM-dd');
  final DateFormat _displayFormat = DateFormat('MMM d, yyyy');

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    // Default: Month-To-Date (MTD)
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
      _endDate = DateTime(now.year, now.month, 0); // Last day of previous month
    });
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFF10B981),
              onPrimary: Colors.white,
              surface: Color(0xFF1E293B),
              onSurface: Color(0xFFF8FAFC),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
    }
  }

  void _onPresetChanged(String newPreset) {
    setState(() {
      _preset = newPreset;
      if (newPreset == 'full') {
        // Full preset turns all options on by default
        _includeNotes = true;
        _includeStats = true;
        _includeSource = true;
      }
    });
  }

  Future<void> _generateReport() async {
    setState(() {
      _isGenerating = true;
      _statusMessage = null;
    });

    try {
      final apiClient = ref.read(apiClientProvider);
      final result = await apiClient.generateReport(
        startDate: _startDate,
        endDate: _endDate,
        preset: _preset,
        includeNotes: _preset == 'full' ? true : _includeNotes,
        includeStats: _preset == 'full' ? true : _includeStats,
        includeSource: _preset == 'full' ? true : _includeSource,
      );

      final path = await ReportFileService.saveAndOpenReport(
        bytes: result.bytes,
        filename: result.filename,
      );

      setState(() {
        _lastGeneratedPath = path;
        _lastGeneratedFilename = result.filename;
        _statusMessage = 'Generated ${result.totalHours.toStringAsFixed(1)}h (${result.totalShifts} shifts)';
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
        setState(() => _isGenerating = false);
      }
    }
  }

  Future<void> _openLastReport() async {
    if (_lastGeneratedPath != null) {
      await ReportFileService.openReportFile(_lastGeneratedPath!);
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
      final path = await ReportFileService.saveAndOpenReport(
        bytes: bytes,
        filename: cleanName,
      );

      setState(() {
        _lastGeneratedPath = path;
        _lastGeneratedFilename = cleanName;
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
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Date Range Card
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
                  const Text(
                    'DATE RANGE',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF94A3B8),
                      letterSpacing: 1.1,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Quick selection chips
                  Wrap(
                    spacing: 8,
                    children: [
                      ActionChip(
                        label: const Text('This Month'),
                        backgroundColor: const Color(0xFF0F172A),
                        side: const BorderSide(color: Color(0xFF334155)),
                        labelStyle: const TextStyle(fontSize: 12, color: Colors.white),
                        onPressed: _setThisMonth,
                      ),
                      ActionChip(
                        label: const Text('Last Month'),
                        backgroundColor: const Color(0xFF0F172A),
                        side: const BorderSide(color: Color(0xFF334155)),
                        labelStyle: const TextStyle(fontSize: 12, color: Colors.white),
                        onPressed: _setLastMonth,
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.calendar_today, size: 14, color: activeColor),
                        label: const Text('Custom'),
                        backgroundColor: const Color(0xFF0F172A),
                        side: const BorderSide(color: Color(0xFF334155)),
                        labelStyle: const TextStyle(fontSize: 12, color: Colors.white),
                        onPressed: _pickDateRange,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Display selected range
                  InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: _pickDateRange,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF334155)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.date_range, color: activeColor, size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              '${_displayFormat.format(_startDate)}  —  ${_displayFormat.format(_endDate)}',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFFF8FAFC),
                              ),
                            ),
                          ),
                          const Icon(Icons.edit, color: Color(0xFF94A3B8), size: 16),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Preset Selector Card
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
                  const Text(
                    'REPORT PRESET',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF94A3B8),
                      letterSpacing: 1.1,
                    ),
                  ),
                  const SizedBox(height: 12),

                  Row(
                    children: [
                      Expanded(
                        child: _buildPresetCard(
                          title: 'Formal',
                          subtitle: 'Dates & hours log',
                          isSelected: _preset == 'formal',
                          onTap: () => _onPresetChanged('formal'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildPresetCard(
                          title: 'Full',
                          subtitle: 'Notes, stats & details',
                          isSelected: _preset == 'full',
                          onTap: () => _onPresetChanged('full'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Options Checklist (active when Formal, auto-checked when Full)
                  const Text(
                    'OPTIONS CHECKLIST',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 6),

                  Material(
                    color: Colors.transparent,
                    child: Column(
                      children: [
                        CheckboxListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          activeColor: activeColor,
                          title: const Text('Include Shift Notes', style: TextStyle(fontSize: 13, color: Colors.white)),
                          value: _preset == 'full' ? true : _includeNotes,
                          onChanged: _preset == 'full'
                              ? null
                              : (val) => setState(() => _includeNotes = val ?? false),
                        ),
                        CheckboxListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          activeColor: activeColor,
                          title: const Text('Include Summary Statistics', style: TextStyle(fontSize: 13, color: Colors.white)),
                          value: _preset == 'full' ? true : _includeStats,
                          onChanged: _preset == 'full'
                              ? null
                              : (val) => setState(() => _includeStats = val ?? false),
                        ),
                        CheckboxListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          activeColor: activeColor,
                          title: const Text('Include Source Breakdown', style: TextStyle(fontSize: 13, color: Colors.white)),
                          value: _preset == 'full' ? true : _includeSource,
                          onChanged: _preset == 'full'
                              ? null
                              : (val) => setState(() => _includeSource = val ?? false),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Action Buttons Row: "Generate" & "Open"
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: activeColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _isGenerating ? null : _generateReport,
                    icon: _isGenerating
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.table_view, size: 20),
                    label: const Text(
                      'Generate',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                  ),
                ),
                if (_lastGeneratedPath != null) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: activeColor,
                        side: const BorderSide(color: activeColor, width: 1.5),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _openLastReport,
                      icon: const Icon(Icons.open_in_new, size: 18),
                      label: const Text(
                        'Open',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                      ),
                    ),
                  ),
                ],
              ],
            ),

            if (_statusMessage != null) ...[
              const SizedBox(height: 12),
              Center(
                child: Text(
                  _statusMessage!,
                  style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                ),
              ),
            ],

            const SizedBox(height: 24),
            const Divider(color: Color(0xFF334155)),
            const SizedBox(height: 12),

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
                  'Download Latest Month',
                  style: TextStyle(color: activeColor, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPresetCard({
    required String title,
    required String subtitle,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    const activeColor = Color(0xFF10B981);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? activeColor : const Color(0xFF334155),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: isSelected ? Colors.white : const Color(0xFF94A3B8),
                  ),
                ),
                const Spacer(),
                if (isSelected)
                  const Icon(Icons.check_circle, color: activeColor, size: 16),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
            ),
          ],
        ),
      ),
    );
  }
}
