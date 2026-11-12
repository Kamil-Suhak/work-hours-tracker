import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../api/models.dart';
import '../clock_notifier.dart';

class CurrentShiftTimerCard extends StatefulWidget {
  final bool isClockedIn;
  final DateTime? activeSince;
  final DateTime? targetClockOutUtc;
  final DateTime? serverTime;
  final int todaySeconds;
  final int monthSeconds;
  final bool enablePeriodicTimer;
  final VoidCallback? onViewHistory;
  final bool showHistoryButton;
  final bool embedded;
  final bool isAdjustingTarget;
  final ValueChanged<int>? onAdjustTargetDelta;
  final VoidCallback? onOpenCustomTarget;
  final VoidCallback? onTargetReached;

  const CurrentShiftTimerCard({
    super.key,
    required this.isClockedIn,
    this.activeSince,
    this.targetClockOutUtc,
    this.serverTime,
    required this.todaySeconds,
    required this.monthSeconds,
    this.enablePeriodicTimer = true,
    this.onViewHistory,
    this.showHistoryButton = true,
    this.embedded = false,
    this.isAdjustingTarget = false,
    this.onAdjustTargetDelta,
    this.onOpenCustomTarget,
    this.onTargetReached,
  });

  @override
  State<CurrentShiftTimerCard> createState() => _CurrentShiftTimerCardState();
}

class _CurrentShiftTimerCardState extends State<CurrentShiftTimerCard> {
  Timer? _timer;
  Duration _elapsed = Duration.zero;
  String? _notifiedTargetKey;
  DateTime? _lastTargetNotifyAttempt;

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
      if (!mounted) return;
      setState(_updateElapsed);
      _checkTargetReached();
    });
  }

  void _checkTargetReached() {
    if (!widget.isClockedIn ||
        widget.targetClockOutUtc == null ||
        widget.onTargetReached == null) {
      return;
    }
    final now = DateTime.now();
    final targetLocal = widget.targetClockOutUtc!.toLocal();
    // 2-second grace buffer ensures edge Worker clock has crossed the minute boundary
    if (now.isAfter(targetLocal.add(const Duration(seconds: 2)))) {
      final key =
          '${widget.activeSince?.toIso8601String()}|${widget.targetClockOutUtc?.toIso8601String()}';
      final canRetry = _notifiedTargetKey != key ||
          _lastTargetNotifyAttempt == null ||
          now.difference(_lastTargetNotifyAttempt!) >= const Duration(seconds: 5);
      if (canRetry) {
        _notifiedTargetKey = key;
        _lastTargetNotifyAttempt = now;
        widget.onTargetReached!();
      }
    }
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
    if (!widget.isClockedIn || widget.targetClockOutUtc == null) {
      _notifiedTargetKey = null;
      _lastTargetNotifyAttempt = null;
    }
    if (widget.isClockedIn != oldWidget.isClockedIn ||
        widget.activeSince != oldWidget.activeSince ||
        widget.targetClockOutUtc != oldWidget.targetClockOutUtc ||
        widget.enablePeriodicTimer != oldWidget.enablePeriodicTimer) {
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
    const inactiveColor = Color(0xFF94A3B8); // Muted Slate (>= 4.5:1 on card)
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

    final hasTargetFooter = widget.isClockedIn &&
        widget.activeSince != null &&
        (widget.targetClockOutUtc != null || widget.onOpenCustomTarget != null);

    return Container(
      padding: widget.embedded
          ? const EdgeInsets.symmetric(horizontal: 4, vertical: 4)
          : const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: widget.embedded
          ? null
          : BoxDecoration(
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          IntrinsicHeight(
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
                            color: widget.isClockedIn
                                ? activeColor
                                : inactiveColor,
                          ),
                          const SizedBox(width: 6),
                          const Flexible(
                            child: Text(
                              'CURRENT SHIFT TIMER',
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.0,
                                color: inactiveColor,
                              ),
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
                            color: widget.isClockedIn
                                ? Colors.white
                                : inactiveColor,
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
                    ],
                  ),
                ),

                // Vertical divider separating timer and month/history sections
                const VerticalDivider(
                  color: Color(0xFF334155),
                  thickness: 1,
                  width: 20,
                ),

                // Right: Month to date & History
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
                            color: Color(0xFF94A3B8),
                          ),
                          SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              'MONTH TO DATE',
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.0,
                                color: Color(0xFF94A3B8),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
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
                      if (widget.showHistoryButton &&
                          widget.onViewHistory != null) ...[
                        const SizedBox(height: 4),
                        TextButton.icon(
                          key: const Key('timer_card_history_button'),
                          onPressed: widget.onViewHistory,
                          icon: const Icon(Icons.history, size: 14),
                          label: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'History',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              SizedBox(width: 2),
                              Icon(Icons.chevron_right, size: 15),
                            ],
                          ),
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFF34D399),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            minimumSize: const Size(0, 32),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (hasTargetFooter) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Divider(color: Color(0xFF334155), height: 1),
            ),
            if (widget.targetClockOutUtc != null) ...[
              _buildProgressBar(
                context,
                target: _targetDurationFromTimestamps(
                  widget.activeSince!,
                  widget.targetClockOutUtc!,
                ),
                elapsed: _elapsed,
              ),
              if (widget.onAdjustTargetDelta != null ||
                  widget.onOpenCustomTarget != null) ...[
                const SizedBox(height: 12),
                _buildTargetControls(context, timeFormat),
              ],
            ] else if (widget.onOpenCustomTarget != null)
              _buildSetTargetButton(),
          ],
        ],
      ),
    );
  }

  Duration _targetDurationFromTimestamps(DateTime activeSince, DateTime targetUtc) {
    final diff = targetUtc.toUtc().difference(activeSince.toUtc());
    return diff.isNegative ? Duration.zero : diff;
  }

  Widget _buildTargetControls(BuildContext context, DateFormat timeFormat) {
    final targetLocal = widget.targetClockOutUtc!.toLocal();
    final disabled = widget.isAdjustingTarget;
    final endLabel = 'Ends ${timeFormat.format(targetLocal)}';
    final hasDelta = widget.onAdjustTargetDelta != null;
    final hasCustom = widget.onOpenCustomTarget != null;

    return Container(
      key: const Key('shift_target_controls'),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF334155), width: 1),
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            if (hasDelta)
              Expanded(
                flex: 2,
                child: _buildStepperSegment(
                  key: const Key('target_minus_10_button'),
                  semanticsLabel: 'Subtract 10 minutes from auto-stop target',
                  label: '-10m',
                  onTap: disabled ? null : () => widget.onAdjustTargetDelta!(-10),
                ),
              ),
            if (hasDelta && hasCustom)
              const VerticalDivider(
                width: 1,
                thickness: 1,
                color: Color(0xFF334155),
              ),
            if (hasCustom)
              Expanded(
                flex: 3,
                child: _buildStepperSegment(
                  key: const Key('target_custom_button'),
                  semanticsLabel: 'Edit shift auto-stop target',
                  icon: Icons.tune_rounded,
                  label: endLabel,
                  isHighlighted: true,
                  showSpinner: disabled,
                  onTap: disabled ? null : widget.onOpenCustomTarget,
                ),
              ),
            if (hasDelta) ...[
              const VerticalDivider(
                width: 1,
                thickness: 1,
                color: Color(0xFF334155),
              ),
              Expanded(
                flex: 2,
                child: _buildStepperSegment(
                  key: const Key('target_plus_10_button'),
                  semanticsLabel: 'Add 10 minutes to auto-stop target',
                  label: '+10m',
                  onTap: disabled ? null : () => widget.onAdjustTargetDelta!(10),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSetTargetButton() {
    final disabled = widget.isAdjustingTarget;
    return Semantics(
      button: true,
      label: 'Set auto-stop target',
      child: OutlinedButton.icon(
        key: const Key('set_target_button'),
        onPressed: disabled ? null : widget.onOpenCustomTarget,
        icon: disabled
            ? const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 1.8,
                  color: Color(0xFF94A3B8),
                ),
              )
            : const Icon(Icons.timer_outlined, size: 15),
        label: const Text(
          'Set auto-stop target',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFFCBD5E1),
          backgroundColor: const Color(0xFF0F172A),
          side: const BorderSide(color: Color(0xFF334155)),
          minimumSize: const Size.fromHeight(38),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
    );
  }

  Widget _buildStepperSegment({
    required Key key,
    required String semanticsLabel,
    required String label,
    IconData? icon,
    bool isHighlighted = false,
    bool showSpinner = false,
    VoidCallback? onTap,
  }) {
    const activeEmerald = Color(0xFF10B981);
    final fgColor = onTap == null
        ? const Color(0xFF64748B)
        : (isHighlighted ? const Color(0xFF34D399) : const Color(0xFFE2E8F0));

    return Semantics(
      button: true,
      label: semanticsLabel,
      child: Material(
        color: isHighlighted
            ? activeEmerald.withValues(alpha: 0.1)
            : Colors.transparent,
        child: InkWell(
          key: key,
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 40),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (showSpinner) ...[
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.8,
                      color: Color(0xFF34D399),
                    ),
                  ),
                  const SizedBox(width: 6),
                ] else if (icon != null) ...[
                  Icon(icon, size: 14, color: fgColor),
                  const SizedBox(width: 5),
                ],
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: fgColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
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
    final fraction = isOvertime || target.inMilliseconds <= 0
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
