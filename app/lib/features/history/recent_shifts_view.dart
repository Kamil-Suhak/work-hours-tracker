import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../clock/clock_notifier.dart';
import 'shift_model.dart';
import 'shifts_notifier.dart';

class _MonthGroup {
  final String key;
  final String label;
  final List<ShiftRecord> shifts;
  final int totalSeconds;

  const _MonthGroup({
    required this.key,
    required this.label,
    required this.shifts,
    required this.totalSeconds,
  });
}

class RecentShiftsView extends ConsumerStatefulWidget {
  final ScrollController? scrollController;
  final bool showHeader;
  final bool showDragHandle;
  final EdgeInsetsGeometry? padding;
  final bool shrinkWrap;

  const RecentShiftsView({
    super.key,
    this.scrollController,
    this.showHeader = true,
    this.showDragHandle = false,
    this.padding,
    this.shrinkWrap = false,
  });

  @override
  ConsumerState<RecentShiftsView> createState() => _RecentShiftsViewState();
}

class _RecentShiftsViewState extends ConsumerState<RecentShiftsView> {
  ScrollController? _internalController;
  final Set<String> _expandedMonths = {};
  bool _initializedExpansion = false;

  ScrollController get _effectiveController =>
      widget.scrollController ?? (_internalController ??= ScrollController());

  @override
  void dispose() {
    _internalController?.dispose();
    super.dispose();
  }

  List<_MonthGroup> _groupShiftsByMonth(List<ShiftRecord> shifts) {
    final monthFormat = DateFormat('MMMM yyyy');
    final buckets = <String, List<ShiftRecord>>{};
    final labels = <String, String>{};

    for (final shift in shifts) {
      final local = shift.startTime;
      final key =
          '${local.year}-${local.month.toString().padLeft(2, '0')}';
      buckets.putIfAbsent(key, () => []).add(shift);
      labels.putIfAbsent(
        key,
        () => monthFormat.format(DateTime(local.year, local.month)),
      );
    }

    return buckets.entries.map((entry) {
      final totalSeconds = entry.value.fold<int>(
        0,
        (sum, s) => sum + s.duration.inSeconds,
      );
      return _MonthGroup(
        key: entry.key,
        label: labels[entry.key]!,
        shifts: entry.value,
        totalSeconds: totalSeconds,
      );
    }).toList();
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
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Refresh History',
                  color: const Color(0xFF94A3B8),
                  onPressed: () =>
                      ref.read(shiftsProvider.notifier).refresh(),
                ),
              ],
            ),
          ),
          const Divider(color: Color(0xFF334155), height: 1),
        ],
        if (widget.shrinkWrap)
          _buildShiftsBody(shiftsAsync, activeEmerald)
        else
          Expanded(
            child: RefreshIndicator(
              color: activeEmerald,
              backgroundColor: const Color(0xFF1E293B),
              onRefresh: () => ref.read(shiftsProvider.notifier).refresh(),
              child: _buildShiftsBody(shiftsAsync, activeEmerald),
            ),
          ),
      ],
    );
  }

  Widget _buildShiftsBody(
    AsyncValue<List<ShiftRecord>> shiftsAsync,
    Color activeEmerald,
  ) {
    return shiftsAsync.when(
      data: (shifts) {
        if (shifts.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(
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
                ],
              ),
            ),
          );
        }

        final groups = _groupShiftsByMonth(shifts);
        if (!_initializedExpansion && groups.isNotEmpty) {
          _expandedMonths.add(groups.first.key);
          _initializedExpansion = true;
        }

        final listView = ListView.separated(
          controller: widget.shrinkWrap ? null : _effectiveController,
          shrinkWrap: widget.shrinkWrap,
          physics: widget.shrinkWrap
              ? const NeverScrollableScrollPhysics()
              : null,
          padding: widget.padding ??
              const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 16,
              ),
          itemCount: groups.length,
          separatorBuilder: (_, __) => const SizedBox(height: 16),
          itemBuilder: (context, index) {
            return _buildMonthGroup(context, groups[index]);
          },
        );

        if (widget.shrinkWrap) return listView;

        return Scrollbar(
          controller: _effectiveController,
          thumbVisibility: true,
          thickness: 6,
          radius: const Radius.circular(4),
          child: listView,
        );
      },
      loading: () => Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: CircularProgressIndicator(color: activeEmerald),
        ),
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
                  side: BorderSide(color: activeEmerald),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMonthGroup(BuildContext context, _MonthGroup group) {
    final isExpanded = _expandedMonths.contains(group.key);
    final countLabel =
        '${group.shifts.length} ${group.shifts.length == 1 ? 'shift' : 'shifts'}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: const Color(0xFF162032),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Color(0xFF334155), width: 1.0),
          ),
          child: InkWell(
            key: Key('month_header_${group.key}'),
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              setState(() {
                if (isExpanded) {
                  _expandedMonths.remove(group.key);
                } else {
                  _expandedMonths.add(group.key);
                }
              });
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      group.label,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFF8FAFC),
                      ),
                    ),
                  ),
                  Text(
                    '$countLabel • ${formatSeconds(group.totalSeconds)}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      fontFeatures: [FontFeature.tabularFigures()],
                      color: Color(0xFF94A3B8),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    isExpanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 20,
                    color: const Color(0xFF94A3B8),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (isExpanded) ...[
          const SizedBox(height: 8),
          for (var i = 0; i < group.shifts.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            _buildShiftCard(context, group.shifts[i]),
          ],
        ],
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

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF334155),
          width: 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      dateLabel,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: Color(0xFFF8FAFC),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    shift.durationFormatted,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontFeatures: [FontFeature.tabularFigures()],
                      fontSize: 13,
                      color: Color(0xFF34D399),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.schedule, size: 14, color: Color(0xFF64748B)),
                      const SizedBox(width: 6),
                      Text(
                        '$inTime - $outTime',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        shift.isInOffice
                            ? Icons.business_outlined
                            : Icons.home_work_outlined,
                        size: 13,
                        color: shift.isInOffice
                            ? const Color(0xFF38BDF8)
                            : const Color(0xFF94A3B8),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        shift.isInOffice ? 'In-Office' : 'Remote',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: shift.isInOffice
                              ? const Color(0xFF38BDF8)
                              : const Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                  ),
                  if (isManual)
                    const Text(
                      'Manual backfill',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFFBBF24),
                      ),
                    ),
                ],
              ),
              if ((shift.clockOut.reason?.trim().isNotEmpty ?? false) ||
                  (shift.clockIn.reason?.trim().isNotEmpty ?? false)) ...[
                const SizedBox(height: 6),
                Text(
                  'Reason: ${(shift.clockOut.reason?.trim().isNotEmpty ?? false) ? shift.clockOut.reason!.trim() : shift.clockIn.reason!.trim()}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                    color: Color(0xFF94A3B8),
                  ),
                ),
              ],
            ],
          ),
        );
  }
}
