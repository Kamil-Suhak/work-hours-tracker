import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../api/models.dart';
import '../clock_notifier.dart';

class CurrentShiftTimerCard extends StatefulWidget {
  final bool isClockedIn;
  final DateTime? activeSince;
  final DateTime? serverTime;
  final int todaySeconds;
  final int monthSeconds;
  final bool enablePeriodicTimer;
  final VoidCallback? onViewHistory;
  final Duration? plannedDuration;
  final bool showHistoryButton;

  const CurrentShiftTimerCard({
    super.key,
    required this.isClockedIn,
    this.activeSince,
    this.serverTime,
    required this.todaySeconds,
    required this.monthSeconds,
    this.enablePeriodicTimer = true,
    this.onViewHistory,
    this.plannedDuration,
    this.showHistoryButton = true,
  });

  @override
  State<CurrentShiftTimerCard> createState() => _CurrentShiftTimerCardState();
}

class _CurrentShiftTimerCardState extends State<CurrentShiftTimerCard> {
  Timer? _timer;
  Duration _elapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    _updateElapsed();
    if (widget.isClockedIn && widget.enablePeriodicTimer) {
      _startTimer();
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(_updateElapsed);
      }
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  void _updateElapsed() {
    if (widget.isClockedIn && widget.activeSince != null) {
      final now = DateTime.now();
      final difference = now.difference(widget.activeSince!.toLocal());
      _elapsed = difference.isNegative ? Duration.zero : difference;
    } else {
      _elapsed = Duration.zero;
    }
  }

  @override
  void didUpdateWidget(covariant CurrentShiftTimerCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isClockedIn != oldWidget.isClockedIn ||
        widget.activeSince != oldWidget.activeSince ||
        widget.plannedDuration != oldWidget.plannedDuration) {
      _updateElapsed();
      if (widget.isClockedIn && widget.enablePeriodicTimer) {
        _startTimer();
      } else {
        _stopTimer();
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final hours = d.inHours.toString().padLeft(2, '0');
    final minutes = (d.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  int _liveAdditionalSeconds() {
    if (!widget.isClockedIn ||
        widget.activeSince == null ||
        widget.serverTime == null) {
      return 0;
    }
    final startMinute = truncateToMinute(widget.activeSince!.toUtc());
    final fetchMinute = truncateToMinute(widget.serverTime!.toUtc());
    final nowMinute = truncateToMinute(DateTime.now().toUtc());

    final fetchElapsedMinutes =
        fetchMinute.difference(startMinute).inMinutes.clamp(0, 1 << 30);
    final currentElapsedMinutes =
        nowMinute.difference(startMinute).inMinutes.clamp(0, 1 << 30);
    final deltaMinutes = currentElapsedMinutes - fetchElapsedMinutes;
    return deltaMinutes > 0 ? deltaMinutes * 60 : 0;
  }

  @override
  Widget build(BuildContext context) {
    const activeColor = Color(0xFF10B981); // Emerald
    const inactiveColor = Color(0xFF64748B); // Slate
    final timeFormat = DateFormat('HH:mm');

    final activeLocal = widget.activeSince?.toLocal();
    final nowLocal = DateTime.now();
    final startedToday = activeLocal != null &&
        activeLocal.year == nowLocal.year &&
        activeLocal.month == nowLocal.month &&
        activeLocal.day == nowLocal.day;
    final startedThisMonth = activeLocal != null &&
        activeLocal.year == nowLocal.year &&
        activeLocal.month == nowLocal.month;

    final liveDelta = _liveAdditionalSeconds();
    final timerDisplay = widget.isClockedIn ? _formatDuration(_elapsed) : '--:--:--';
    final todayFormatted =
        formatSeconds(widget.todaySeconds + (startedToday ? liveDelta : 0));
    final monthFormatted =
        formatSeconds(widget.monthSeconds + (startedThisMonth ? liveDelta : 0));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: widget.isClockedIn
              ? activeColor.withValues(alpha: 0.35)
              : const Color(0xFF334155),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Left: Current Shift Timer
            Expanded(
              flex: 3,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.timer_outlined,
                        size: 14,
                        color: widget.isClockedIn ? activeColor : inactiveColor,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'CURRENT SHIFT TIMER',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.1,
                          color: widget.isClockedIn
                              ? const Color(0xFF94A3B8)
                              : inactiveColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      timerDisplay,
                      style: TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        letterSpacing: 1.5,
                        color: widget.isClockedIn ? Colors.white : inactiveColor,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: widget.isClockedIn && widget.activeSince != null
                        ? Text(
                            'Started at ${timeFormat.format(widget.activeSince!.toLocal())} • Today: $todayFormatted',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF94A3B8),
                            ),
                            textAlign: TextAlign.center,
                          )
                        : Text(
                            "Today's total: $todayFormatted",
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF94A3B8),
                            ),
                            textAlign: TextAlign.center,
                          ),
                  ),
                  if (widget.isClockedIn && widget.plannedDuration != null) ...[
                    const SizedBox(height: 8),
                    _buildProgressBar(
                      context,
                      target: widget.plannedDuration!,
                      elapsed: _elapsed,
                    ),
                  ],
                ],
              ),
            ),

            // Vertical divider separating timer and month/history sections
            const VerticalDivider(
              color: Color(0xFF334155),
              thickness: 1,
              width: 20,
            ),

            // Right: Month to date & History (aligned at same y level)
            Expanded(
              flex: 2,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.calendar_month_outlined,
                        size: 13,
                        color: Color(0xFF64748B),
                      ),
                      SizedBox(width: 4),
                      Text(
                        'MONTH TO DATE',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.1,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      monthFormatted,
                      style: TextStyle(
                        fontSize: widget.showHistoryButton ? 18 : 22,
                        fontWeight: FontWeight.w800,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        letterSpacing: 0.8,
                        color: Colors.white,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  if (widget.showHistoryButton && widget.onViewHistory != null) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          key: const Key('timer_card_history_button'),
                          borderRadius: BorderRadius.circular(10),
                          onTap: widget.onViewHistory,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: activeColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: activeColor.withValues(alpha: 0.35),
                                width: 1.2,
                              ),
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.history,
                                  size: 14,
                                  color: activeColor,
                                ),
                                SizedBox(width: 4),
                                Text(
                                  'History',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.3,
                                    color: activeColor,
                                  ),
                                ),
                                SizedBox(width: 2),
                                Icon(
                                  Icons.chevron_right,
                                  size: 14,
                                  color: activeColor,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressBar(
    BuildContext context, {
    required Duration target,
    required Duration elapsed,
  }) {
    final elapsedMinutes = Duration(minutes: elapsed.inMinutes);
    final isOvertime = elapsed >= target;
    final fraction = isOvertime
        ? 1.0
        : (elapsed.inMilliseconds / target.inMilliseconds).clamp(0.0, 1.0);
    final remaining = isOvertime ? Duration.zero : target - elapsedMinutes;

    final barColor = isOvertime ? const Color(0xFFF59E0B) : const Color(0xFF10B981);
    final glowColor = isOvertime
        ? const Color(0xFFF59E0B).withValues(alpha: 0.5)
        : const Color(0xFF10B981).withValues(alpha: 0.5);

    return Column(
      key: const Key('shift_progress_bar'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 6,
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: const Color(0xFF334155), width: 0.8),
          ),
          child: LayoutBuilder(
            builder: (ctx, constraints) {
              return Stack(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: constraints.maxWidth * fraction,
                    decoration: BoxDecoration(
                      gradient: isOvertime
                          ? const LinearGradient(
                              colors: [Color(0xFFD97706), Color(0xFFF59E0B)],
                            )
                          : const LinearGradient(
                              colors: [Color(0xFF10B981), Color(0xFF34D399)],
                            ),
                      borderRadius: BorderRadius.circular(3),
                      boxShadow: [
                        BoxShadow(
                          color: glowColor,
                          blurRadius: 6,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isOvertime ? Icons.warning_amber_rounded : Icons.hourglass_bottom_rounded,
                size: 11,
                color: barColor,
              ),
              const SizedBox(width: 4),
              Text(
                isOvertime
                    ? 'Target reached • Overtime: +${_formatHoursMinutes(elapsedMinutes - target)}'
                    : 'Target: ${_formatHoursMinutes(target)} • Remaining: ${_formatHoursMinutes(remaining)}',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: isOvertime ? const Color(0xFFFBBF24) : const Color(0xFF34D399),
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatHoursMinutes(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes % 60;
    if (hours > 0 && minutes > 0) {
      return '${hours}h ${minutes}m';
    } else if (hours > 0) {
      return '${hours}h';
    }
    return '${minutes}m';
  }
}
