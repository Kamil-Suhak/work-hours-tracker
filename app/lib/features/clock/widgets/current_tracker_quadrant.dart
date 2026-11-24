import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../api/models.dart';
import 'clock_action_button.dart';
import 'current_shift_timer_card.dart';
import 'cyber_orbit_badge.dart';

class CurrentTrackerQuadrant extends StatelessWidget {
  final WorkStatus status;
  final bool isLoading;
  final bool enableAnimations;
  final void Function({
    int? offsetMinutes,
    Duration? plannedDuration,
    String location,
  }) onClockIn;
  final void Function({int? offsetMinutes}) onClockOut;
  final ValueChanged<LatestEventSummary> onUndo;
  final VoidCallback? onViewHistory;
  final bool isAdjustingTarget;
  final ValueChanged<int>? onAdjustTargetDelta;
  final VoidCallback? onOpenCustomTarget;
  final VoidCallback? onTargetReached;

  const CurrentTrackerQuadrant({
    super.key,
    required this.status,
    required this.isLoading,
    this.enableAnimations = true,
    required this.onClockIn,
    required this.onClockOut,
    required this.onUndo,
    this.onViewHistory,
    this.isAdjustingTarget = false,
    this.onAdjustTargetDelta,
    this.onOpenCustomTarget,
    this.onTargetReached,
  });

  @override
  Widget build(BuildContext context) {
    final isClockedIn = status.state == WorkState.clockedIn;
    final timeFormat = DateFormat('HH:mm');
    const slateDark = Color(0xFF1E293B);

    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: slateDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF334155),
          width: 1.2,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Status Badge with Animated Cyber Orbiting Beacon
          Center(
            child: CyberOrbitBadge(
              isClockedIn: isClockedIn,
              enableAnimation: enableAnimations,
            ),
          ),
          const SizedBox(height: 24),

          // Central Current Shift Timer Card (embedded cleanly)
          CurrentShiftTimerCard(
            isClockedIn: isClockedIn,
            activeSince: status.activeSince,
            targetClockOutUtc: status.targetClockOutUtc,
            serverTime: status.serverTime,
            todaySeconds: status.todaySeconds,
            monthSeconds: status.monthSeconds,
            enablePeriodicTimer: enableAnimations,
            onViewHistory: onViewHistory,
            showHistoryButton: false,
            embedded: true,
            isAdjustingTarget: isAdjustingTarget,
            onAdjustTargetDelta: onAdjustTargetDelta,
            onOpenCustomTarget: onOpenCustomTarget,
            onTargetReached: onTargetReached,
          ),
          const SizedBox(height: 24),

          // Action Buttons (aligned cleanly within centered hero width)
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Row(
                children: [
                  Expanded(
                    child: ClockActionButton(
                      isClockIn: true,
                      isLoading: isLoading && !isClockedIn,
                      isEnabled: !isLoading && !isClockedIn,
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      onAction: onClockIn,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ClockActionButton(
                      isClockIn: false,
                      isLoading: isLoading && isClockedIn,
                      isEnabled: !isLoading && isClockedIn,
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      onAction: ({
                        int? offsetMinutes,
                        Duration? plannedDuration,
                        String location = 'remote',
                      }) =>
                          onClockOut(offsetMinutes: offsetMinutes),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Undo Action Button if within grace period
          if (status.latestEvent != null &&
              status.latestEvent!.isWithinGracePeriod(now: DateTime.now())) ...[
            const SizedBox(height: 16),
            Center(
              child: OutlinedButton.icon(
                key: const Key('undo_button'),
                icon: const Icon(Icons.undo, size: 16),
                label: Text(
                  'Undo ${status.latestEvent!.eventType == 'clock_in' ? 'Clock In' : 'Clock Out'}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.amber[800],
                  side: BorderSide(color: Colors.amber[800]!),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed:
                    isLoading ? null : () => onUndo(status.latestEvent!),
              ),
            ),
          ],

          const SizedBox(height: 16),
          Center(
            child: Text(
              'Last synced: ${timeFormat.format(status.serverTime.toLocal())}',
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF94A3B8),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
