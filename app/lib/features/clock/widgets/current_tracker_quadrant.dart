import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../api/models.dart';
import 'current_shift_timer_card.dart';
import 'cyber_orbit_badge.dart';

class CurrentTrackerQuadrant extends StatelessWidget {
  final WorkStatus status;
  final bool isLoading;
  final bool enableAnimations;
  final VoidCallback onClockIn;
  final VoidCallback onClockOut;
  final ValueChanged<LatestEventSummary> onUndo;
  final VoidCallback? onViewHistory;

  const CurrentTrackerQuadrant({
    super.key,
    required this.status,
    required this.isLoading,
    this.enableAnimations = true,
    required this.onClockIn,
    required this.onClockOut,
    required this.onUndo,
    this.onViewHistory,
  });

  @override
  Widget build(BuildContext context) {
    final isClockedIn = status.state == WorkState.clockedIn;
    final timeFormat = DateFormat('HH:mm');
    const slateDark = Color(0xFF1E293B);

    return Container(
      decoration: BoxDecoration(
        color: slateDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF334155),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                const Icon(
                  Icons.timer_outlined,
                  color: Color(0xFF10B981),
                  size: 20,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Shift Tracker & Controls',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: Color(0xFFF8FAFC),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Server time: ${timeFormat.format(status.serverTime.toLocal())}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF94A3B8),
                  ),
                ),
              ],
            ),
          ),
          const Divider(color: Color(0xFF334155), height: 1),

          // Tracker body
          Expanded(
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                  const SizedBox(height: 10),

                  // Central Current Shift Timer Card (Consolidated side-by-side)
                  CurrentShiftTimerCard(
                    isClockedIn: isClockedIn,
                    activeSince: status.activeSince,
                    todaySeconds: status.todaySeconds,
                    monthSeconds: status.monthSeconds,
                    enablePeriodicTimer: enableAnimations,
                    onViewHistory: onViewHistory,
                  ),
                  const SizedBox(height: 12),

                  // Action Buttons (Narrower & Centered)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 150,
                        child: ElevatedButton.icon(
                          key: const Key('clock_in_button'),
                          icon: isLoading && !isClockedIn
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.play_arrow, size: 20),
                          label: const Text('CLOCK IN'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF10B981),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onPressed:
                              isLoading || isClockedIn ? null : onClockIn,
                        ),
                      ),
                      const SizedBox(width: 14),
                      SizedBox(
                        width: 150,
                        child: ElevatedButton.icon(
                          key: const Key('clock_out_button'),
                          icon: isLoading && isClockedIn
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.stop, size: 20),
                          label: const Text('CLOCK OUT'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFEF4444),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onPressed:
                              isLoading || !isClockedIn ? null : onClockOut,
                        ),
                      ),
                    ],
                  ),

                  // Undo Action Button if within grace period
                  if (status.latestEvent != null &&
                      status.latestEvent!
                          .isWithinGracePeriod(now: DateTime.now())) ...[
                    const SizedBox(height: 8),
                    Center(
                      child: OutlinedButton.icon(
                        key: const Key('undo_button'),
                        icon: const Icon(Icons.undo, size: 15),
                        label: Text(
                          'Undo ${status.latestEvent!.eventType == 'clock_in' ? 'Clock In' : 'Clock Out'}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.amber[800],
                          side: BorderSide(color: Colors.amber[800]!),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 6),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        onPressed: isLoading
                            ? null
                            : () => onUndo(status.latestEvent!),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
