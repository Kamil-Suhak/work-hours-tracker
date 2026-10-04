import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../api/models.dart';
import '../history/recent_shifts_sheet.dart';
import '../settings/settings_dialog.dart';
import '../settings/settings_notifier.dart';
import '../settings/widget_sync_service.dart';
import 'clock_notifier.dart';
import 'widgets/current_shift_timer_card.dart';
import 'widgets/cyber_orbit_badge.dart';
import 'widgets/shift_notes_card.dart';

class ClockScreen extends ConsumerStatefulWidget {
  final bool enableAnimations;

  const ClockScreen({
    super.key,
    this.enableAnimations = true,
  });

  @override
  ConsumerState<ClockScreen> createState() => _ClockScreenState();
}

class _ClockScreenState extends ConsumerState<ClockScreen> {
  final _notesController = TextEditingController();
  Timer? _gracePeriodTicker;

  @override
  void dispose() {
    _gracePeriodTicker?.cancel();
    _notesController.dispose();
    super.dispose();
  }

  void _syncGracePeriodTicker(WorkStatus? status) {
    final hasGraceEvent = status?.latestEvent?.isWithinGracePeriod() ?? false;
    if (hasGraceEvent) {
      if (_gracePeriodTicker == null || !_gracePeriodTicker!.isActive) {
        _gracePeriodTicker = Timer.periodic(const Duration(seconds: 1), (_) {
          if (!mounted) return;
          final stillWithin = ref.read(currentStatusProvider).value?.latestEvent?.isWithinGracePeriod() ?? false;
          setState(() {});
          if (!stillWithin) {
            _gracePeriodTicker?.cancel();
            _gracePeriodTicker = null;
          }
        });
      }
    } else {
      _gracePeriodTicker?.cancel();
      _gracePeriodTicker = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusAsync = ref.watch(currentStatusProvider);
    final isLoading = statusAsync.isLoading;
    _syncGracePeriodTicker(statusAsync.value);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Work Hours Tracker'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'Shift History',
            onPressed: () => RecentShiftsSheet.show(context),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Status',
            onPressed: isLoading
                ? null
                : () =>
                    ref.read(currentStatusProvider.notifier).refreshStatus(),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Server Settings',
            onPressed: () => SettingsDialog.show(context),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () =>
            ref.read(currentStatusProvider.notifier).refreshStatus(),
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24.0, vertical: 32.0),
                  child: statusAsync.hasValue
                      ? _buildStatusContent(
                          context, statusAsync.value!, isLoading)
                      : statusAsync.when(
                          data: (status) =>
                              _buildStatusContent(context, status, isLoading),
                          loading: () => const Center(
                            child: CircularProgressIndicator(),
                          ),
                          error: (err, stack) =>
                              _buildErrorContent(context, err, isLoading),
                        ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildStatusContent(
      BuildContext context, WorkStatus status, bool isLoading) {
    final isClockedIn = status.state == WorkState.clockedIn;
    final timeFormat = DateFormat('HH:mm');

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Status Badge with Animated Cyber Orbiting Beacon
        Center(
          child: CyberOrbitBadge(
            isClockedIn: isClockedIn,
            enableAnimation: widget.enableAnimations,
          ),
        ),
        const SizedBox(height: 28),

        // Central Current Shift Timer Card (Stationary Anchor)
        CurrentShiftTimerCard(
          isClockedIn: isClockedIn,
          activeSince: status.activeSince,
          todaySeconds: status.todaySeconds,
          monthSeconds: status.monthSeconds,
          enablePeriodicTimer: widget.enableAnimations,
          onViewHistory: () => RecentShiftsSheet.show(context),
        ),
        const SizedBox(height: 36),

        // Action Buttons
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                key: const Key('clock_in_button'),
                icon: isLoading && !isClockedIn
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.play_arrow),
                label: const Text('CLOCK IN'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: isLoading || isClockedIn
                    ? null
                    : () async {
                        _triggerHapticIfEnabled();
                        await ref
                            .read(currentStatusProvider.notifier)
                            .clockIn();
                      },
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: ElevatedButton.icon(
                key: const Key('clock_out_button'),
                icon: isLoading && isClockedIn
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.stop),
                label: const Text('CLOCK OUT'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFEF4444),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: isLoading || !isClockedIn
                    ? null
                    : () async {
                        _triggerHapticIfEnabled();
                        final note = _notesController.text.trim();
                        await ref
                            .read(currentStatusProvider.notifier)
                            .clockOut(note: note.isNotEmpty ? note : null);
                        _notesController.clear();
                        await ShiftNotesCard.clearDraft();
                      },
              ),
            ),
          ],
        ),

        // Undo recent event button (shown only within 5-min grace window)
        if (status.latestEvent != null &&
            status.latestEvent!.isWithinGracePeriod(now: DateTime.now())) ...[
          const SizedBox(height: 16),
          Center(
            child: OutlinedButton.icon(
              key: const Key('undo_button'),
              icon: const Icon(Icons.undo, size: 18),
              label: Text(
                'Undo ${status.latestEvent!.eventType == 'clock_in' ? 'Clock In' : 'Clock Out'}',
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.amber[800],
                side: BorderSide(color: Colors.amber[800]!),
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              onPressed: isLoading
                  ? null
                  : () => _showUndoConfirmationDialog(
                        context,
                        status.latestEvent!,
                      ),
            ),
          ),
        ],

        // Optional Shift Notes Box when Clocked In
        if (isClockedIn) ...[
          const SizedBox(height: 24),
          ShiftNotesCard(controller: _notesController),
        ],

        const SizedBox(height: 24),

        // Last synced info
        Center(
          child: Text(
            'Authoritative server time: ${timeFormat.format(status.serverTime.toLocal())}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey[500],
                ),
          ),
        ),
      ],
    );
  }

  void _triggerHapticIfEnabled() {
    final haptics =
        ref.read(settingsProvider).value?.vibrationsEnabled ?? true;
    if (haptics) {
      WidgetSyncService.vibrate();
    }
  }

  Future<void> _showUndoConfirmationDialog(
    BuildContext context,
    LatestEventSummary event,
  ) async {
    final eventTypeLabel =
        event.eventType == 'clock_in' ? 'Clock In' : 'Clock Out';
    final timeStr =
        DateFormat('HH:mm:ss').format(event.occurredAtUtc.toLocal());

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.undo, color: Colors.amber),
            SizedBox(width: 8),
            Text('Revert Action'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Are you sure you want to revert your last action?'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.grey.withValues(alpha: 0.3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Event: $eventTypeLabel',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text('Recorded at: $timeStr'),
                  const SizedBox(height: 4),
                  Text(
                    'Event ID: ${event.id.length > 8 ? event.id.substring(0, 8) : event.id}...',
                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'This action is only available within the 5-minute grace period.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber[800],
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Confirm Undo'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      _triggerHapticIfEnabled();
      try {
        await ref.read(currentStatusProvider.notifier).undo(event.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Successfully reverted $eventTypeLabel!'),
              backgroundColor: const Color(0xFF0F766E),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Undo failed: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Widget _buildErrorContent(
      BuildContext context, Object error, bool isLoading) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.error_outline, size: 64, color: Colors.amber),
        const SizedBox(height: 16),
        Text(
          'Connection or Server Error',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          error.toString(),
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: Colors.grey[700]),
        ),
        const SizedBox(height: 24),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          alignment: WrapAlignment.center,
          children: [
            ElevatedButton.icon(
              onPressed: isLoading
                  ? null
                  : () =>
                      ref.read(currentStatusProvider.notifier).refreshStatus(),
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
            OutlinedButton.icon(
              onPressed: () => SettingsDialog.show(context),
              icon: const Icon(Icons.settings),
              label: const Text('Configure Server'),
            ),
          ],
        ),
      ],
    );
  }
}
