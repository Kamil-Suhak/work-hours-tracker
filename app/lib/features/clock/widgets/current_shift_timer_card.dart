import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../clock_notifier.dart';

class CurrentShiftTimerCard extends StatefulWidget {
  final bool isClockedIn;
  final DateTime? activeSince;
  final int todaySeconds;
  final int monthSeconds;
  final bool enablePeriodicTimer;
  final VoidCallback? onViewHistory;

  const CurrentShiftTimerCard({
    super.key,
    required this.isClockedIn,
    this.activeSince,
    required this.todaySeconds,
    required this.monthSeconds,
    this.enablePeriodicTimer = true,
    this.onViewHistory,
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
        widget.activeSince != oldWidget.activeSince) {
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

  @override
  Widget build(BuildContext context) {
    const activeColor = Color(0xFF10B981); // Emerald
    const inactiveColor = Color(0xFF64748B); // Slate
    final timeFormat = DateFormat('HH:mm');

    final timerDisplay = widget.isClockedIn ? _formatDuration(_elapsed) : '--:--:--';
    final todayFormatted = formatSeconds(widget.todaySeconds);
    final monthFormatted = formatSeconds(widget.monthSeconds);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B), // Dark Slate
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: widget.isClockedIn
              ? activeColor.withValues(alpha: 0.35)
              : const Color(0xFF334155),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Header Label
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.timer_outlined,
                size: 15,
                color: widget.isClockedIn ? activeColor : inactiveColor,
              ),
              const SizedBox(width: 8),
              Text(
                'CURRENT SHIFT TIMER',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                  color: widget.isClockedIn
                      ? const Color(0xFF94A3B8)
                      : inactiveColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Central High-Precision Stopwatch
          Text(
            timerDisplay,
            style: TextStyle(
              fontSize: 42,
              fontWeight: FontWeight.w800,
              fontFeatures: const [FontFeature.tabularFigures()],
              letterSpacing: 2.0,
              color: widget.isClockedIn ? Colors.white : inactiveColor,
            ),
          ),
          const SizedBox(height: 8),

          // Subtitle details (Shift start or Today's tracked time)
          if (widget.isClockedIn && widget.activeSince != null)
            Text(
              'Started at ${timeFormat.format(widget.activeSince!.toLocal())} • Today: $todayFormatted',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Color(0xFF94A3B8),
              ),
            )
          else
            Text(
              "Today's total: $todayFormatted",
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Color(0xFF94A3B8),
              ),
            ),

          const SizedBox(height: 16),
          const Divider(color: Color(0xFF334155), height: 1),
          const SizedBox(height: 14),

          // Month to Date Total and Shift History Button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.calendar_month_outlined,
                    size: 15,
                    color: Color(0xFF64748B),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Month to date: $monthFormatted',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF94A3B8),
                    ),
                  ),
                ],
              ),
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: widget.onViewHistory,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'History',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: activeColor,
                        ),
                      ),
                      SizedBox(width: 2),
                      Icon(
                        Icons.chevron_right,
                        size: 16,
                        color: activeColor,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
