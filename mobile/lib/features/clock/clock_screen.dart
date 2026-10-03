import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../api/models.dart';
import '../settings/settings_dialog.dart';
import '../settings/settings_notifier.dart';
import 'clock_notifier.dart';

class ClockScreen extends ConsumerStatefulWidget {
  const ClockScreen({super.key});

  @override
  ConsumerState<ClockScreen> createState() => _ClockScreenState();
}

class _ClockScreenState extends ConsumerState<ClockScreen> {
  @override
  Widget build(BuildContext context) {
    final statusAsync = ref.watch(currentStatusProvider);
    final isLoading = statusAsync.isLoading;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Work Hours Tracker'),
        centerTitle: true,
        actions: [
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
                  child: statusAsync.when(
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
        // Status Badge
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: isClockedIn
                  ? Colors.green.withValues(alpha: 0.15)
                  : Colors.grey.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: isClockedIn ? Colors.green : Colors.grey,
                width: 1.5,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isClockedIn ? Icons.check_circle : Icons.pause_circle_outline,
                  color: isClockedIn ? Colors.green : Colors.grey,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  isClockedIn ? 'CLOCKED IN' : 'CLOCKED OUT',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                    color: isClockedIn ? Colors.green : Colors.grey,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 36),

        // Active since text
        if (isClockedIn && status.activeSince != null) ...[
          Center(
            child: Text(
              'Active since ${timeFormat.format(status.activeSince!.toLocal())}',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.grey[700],
                  ),
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Today's total card
        Card(
          elevation: 2,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              children: [
                Text(
                  "Today's Tracked Time",
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Colors.grey[600],
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  formatSeconds(status.todaySeconds),
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Month to date: ${formatSeconds(status.monthSeconds)}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.grey[500],
                      ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 48),

        // Action Buttons
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                key: const Key('clock_in_button'),
                icon: const Icon(Icons.play_arrow),
                label: const Text('CLOCK IN'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
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
                icon: const Icon(Icons.stop),
                label: const Text('CLOCK OUT'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
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
                        await ref
                            .read(currentStatusProvider.notifier)
                            .clockOut();
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
      HapticFeedback.mediumImpact();
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
