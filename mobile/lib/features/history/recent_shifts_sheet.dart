import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../clock/widgets/markdown_renderer.dart';
import 'manual_shift_dialog.dart';
import 'shift_model.dart';
import 'shifts_notifier.dart';

class RecentShiftsSheet extends ConsumerWidget {
  const RecentShiftsSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const RecentShiftsSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shiftsAsync = ref.watch(shiftsProvider);
    const activeEmerald = Color(0xFF10B981);

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF0F172A), // Dark Slate 900
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Drag handle
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

              // Header
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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

              // Shift List
              Expanded(
                child: RefreshIndicator(
                  color: activeEmerald,
                  backgroundColor: const Color(0xFF1E293B),
                  onRefresh: () => ref.read(shiftsProvider.notifier).refresh(),
                  child: shiftsAsync.when(
                    data: (shifts) {
                      if (shifts.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.calendar_today_outlined,
                                size: 48,
                                color: Color(0xFF475569),
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'No completed shifts found',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Color(0xFF94A3B8),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
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

                      return ListView.separated(
                        controller: scrollController,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 16,
                        ),
                        itemCount: shifts.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final shift = shifts[index];
                          return _buildShiftCard(context, shift);
                        },
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
          ),
        );
      },
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
        onTap: () {
          if (hasNote) {
            _showShiftNoteDialog(context, shift);
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('No notes from this day'),
                duration: Duration(seconds: 2),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        },
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B), // Slate 800
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
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
    final dateFormat = DateFormat('EEEE, MMMM d, yyyy');
    final timeFormat = DateFormat('HH:mm');

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
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
              child: const Icon(Icons.description, color: Color(0xFF10B981), size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Shift Notes',
                    style: TextStyle(
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
          constraints: const BoxConstraints(maxHeight: 320),
          child: SingleChildScrollView(
            child: MarkdownText(
              markdown: shift.note ?? '',
              baseStyle: const TextStyle(
                fontSize: 13,
                height: 1.5,
                color: Color(0xFFE2E8F0),
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close', style: TextStyle(color: Color(0xFF10B981))),
          ),
        ],
      ),
    );
  }
}
