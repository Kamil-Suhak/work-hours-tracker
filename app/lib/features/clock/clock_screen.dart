import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../api/models.dart';
import '../history/recent_shifts_sheet.dart';
import '../history/shift_model.dart';
import '../history/shifts_notifier.dart';
import '../reports/reports_screen.dart';
import '../settings/settings_dialog.dart';
import '../settings/settings_notifier.dart';
import '../../services/platform/platform_services.dart';
import 'clock_notifier.dart';
import 'widgets/current_shift_timer_card.dart';
import 'widgets/cyber_orbit_badge.dart';
import 'widgets/shift_notes_card.dart';
import 'widgets/clock_action_button.dart';
import 'widgets/shift_target_dialog.dart';
import '../history/recent_shifts_view.dart';
import 'widgets/current_tracker_quadrant.dart';
import 'widgets/note_editor_quadrant.dart';
import 'widgets/note_preview_quadrant.dart';

class ClockScreen extends ConsumerStatefulWidget {
  final bool enableAnimations;

  const ClockScreen({
    super.key,
    this.enableAnimations = true,
  });

  @override
  ConsumerState<ClockScreen> createState() => _ClockScreenState();
}

class _ClockScreenState extends ConsumerState<ClockScreen>
    with WidgetsBindingObserver {
  final _notesController = TextEditingController();
  Timer? _gracePeriodTicker;
  ShiftRecord? _selectedPastShift;
  String? _activeShiftDraft;
  Timer? _pastShiftSaveDebounce;
  bool _isSavingPastNote = false;
  bool _pastNoteSaved = false;
  bool _isUpdatingTarget = false;
  bool _isManualClockOut = false;
  bool _isRefreshingTargetReached = false;
  String? _lastReminderSignature;
  Future<void> _reminderSyncQueue = Future<void>.value();

  Future<void> _enqueueReminderOp(Future<void> Function() op) {
    final next = _reminderSyncQueue.then((_) => op());
    _reminderSyncQueue = next.then((_) {}, onError: (_) {});
    return next;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _gracePeriodTicker?.cancel();
    _pastShiftSaveDebounce?.cancel();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _savePastShiftNote(ShiftRecord shift, String noteText) async {
    setState(() {
      _isSavingPastNote = true;
      _pastNoteSaved = false;
    });
    try {
      final targetEventId = shift.clockOut.id;
      final apiClient = ref.read(apiClientProvider);
      await apiClient.updateEventNote(
        eventId: targetEventId,
        note: noteText.trim().isNotEmpty ? noteText.trim() : null,
      );
      ref.read(shiftsProvider.notifier).refresh();
      if (mounted) {
        setState(() {
          _isSavingPastNote = false;
          _pastNoteSaved = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSavingPastNote = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save past shift note: $e'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _selectPastShift(ShiftRecord shift) async {
    _pastShiftSaveDebounce?.cancel();

    if (_selectedPastShift == null) {
      _activeShiftDraft = _notesController.text;
      await ShiftNotesCard.saveDraft(_activeShiftDraft!);
    } else if (_selectedPastShift!.clockOut.id != shift.clockOut.id) {
      await _savePastShiftNote(_selectedPastShift!, _notesController.text);
    }

    setState(() {
      _selectedPastShift = shift;
      _pastNoteSaved = false;
      _isSavingPastNote = false;
      _notesController.text = shift.note ?? '';
    });
  }

  Future<void> _returnToCurrentShift() async {
    _pastShiftSaveDebounce?.cancel();
    if (_selectedPastShift != null) {
      await _savePastShiftNote(_selectedPastShift!, _notesController.text);
    }

    final activeDraft =
        _activeShiftDraft ?? await ShiftNotesCard.loadSavedDraft() ?? '';
    setState(() {
      _selectedPastShift = null;
      _pastNoteSaved = false;
      _isSavingPastNote = false;
      _notesController.text = activeDraft;
    });
  }

  void _handlePastNoteChanged(String text) {
    if (_selectedPastShift != null) {
      setState(() => _pastNoteSaved = false);
      _pastShiftSaveDebounce?.cancel();
      _pastShiftSaveDebounce = Timer(const Duration(seconds: 1), () {
        if (mounted && _selectedPastShift != null) {
          _savePastShiftNote(_selectedPastShift!, _notesController.text);
        }
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(currentStatusProvider.notifier).refreshStatus();
    }
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
    final isStaging =
        ref.watch(settingsProvider).value?.environment == 'staging';
    _syncGracePeriodTicker(statusAsync.value);

    ref.listen<AsyncValue<WorkStatus>>(currentStatusProvider, (previous, next) {
      if (next.hasError && !next.isLoading) {
        final error = next.error;
        final message = (error is ApiException)
            ? '${error.message} (${error.code})'
            : error.toString();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else if (next.hasValue && !next.isLoading) {
        final status = next.value!;
        _syncReminderIfNeeded(status);
        final justAutoStopped =
            !_isManualClockOut &&
            previous?.value?.isClockedIn == true &&
            status.isClockedOut &&
            status.latestEvent?.eventType == 'clock_out';
        if (justAutoStopped) {
          unawaited(_flushDraftToAutoStoppedEvent(status.latestEvent!.id));
        }
      }
    });

    ref.listen<AsyncValue<AppSettings>>(settingsProvider, (_, next) {
      final status = ref.read(currentStatusProvider).value;
      if (next.hasValue && status != null) {
        _syncReminderIfNeeded(status);
      }
    });

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.assessment_outlined),
          tooltip: 'Reports',
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ReportsScreen()),
            );
          },
        ),
        title: isStaging
            ? const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Work Hours Tracker',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  Text(
                    'STAGING',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFFBBF24),
                      letterSpacing: 1.0,
                    ),
                  ),
                ],
              )
            : const Text(
                'Work Hours Tracker',
                overflow: TextOverflow.ellipsis,
              ),
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
            final isDesktop = constraints.maxWidth >= 900;
            final showContent = statusAsync.hasValue &&
                (!statusAsync.hasError || isLoading);

            if (isDesktop) {
              return showContent
                  ? _buildDesktopQuadrants(
                      context, statusAsync.value!, isLoading)
                  : statusAsync.when(
                      data: (status) => _buildDesktopQuadrants(
                          context, status, isLoading),
                      loading: () => const Center(
                        child: CircularProgressIndicator(),
                      ),
                      error: (err, stack) =>
                          _buildErrorContent(context, err, isLoading),
                    );
            }

            return SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24.0, vertical: 32.0),
                  child: showContent
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

  Widget _buildDesktopQuadrants(
      BuildContext context, WorkStatus status, bool isLoading) {
    final isClockedIn = status.state == WorkState.clockedIn;
    final isEditingPastShift = _selectedPastShift != null;
    final shiftDateLabel = isEditingPastShift
        ? DateFormat('MMM d, yyyy').format(_selectedPastShift!.startTime)
        : null;
    final editorTitle = isEditingPastShift
        ? 'Notes | Shift on $shiftDateLabel'
        : 'Notes | Current Shift';

    String? syncStatusText;
    if (isEditingPastShift) {
      if (_isSavingPastNote) {
        syncStatusText = 'Saving...';
      } else if (_pastNoteSaved) {
        syncStatusText = 'Saved';
      }
    }

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Left Half (Flex 1):
          // Top Left: Editor of current or past shift note
          // Bottom Left: Preview of current or past shift note
          Expanded(
            flex: 1,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 1,
                  child: NoteEditorQuadrant(
                    controller: _notesController,
                    title: editorTitle,
                    isEditingPastShift: isEditingPastShift,
                    isReadOnly: !isEditingPastShift && !isClockedIn,
                    syncStatusText: syncStatusText,
                    onReturnToCurrentShift: _returnToCurrentShift,
                    onChanged: _handlePastNoteChanged,
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  flex: 1,
                  child: NotePreviewQuadrant(
                    controller: _notesController,
                    isEditingPastShift: isEditingPastShift,
                    shiftDateLabel: shiftDateLabel,
                    onReturnToCurrentShift: _returnToCurrentShift,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),

          // Right Half (Flex 1):
          // Top Right: Current shift tracker + buttons
          // Bottom Right: Recent shifts (clickable to show past notes)
          Expanded(
            flex: 1,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 1,
                  child: CurrentTrackerQuadrant(
                    status: status,
                    isLoading: isLoading,
                    enableAnimations: widget.enableAnimations,
                    isAdjustingTarget: _isUpdatingTarget,
                    onAdjustTargetDelta: (delta) =>
                        _applyTargetUpdate(deltaMinutes: delta),
                    onOpenCustomTarget: () => _openCustomTargetDialog(status),
                    onTargetReached: _handleTargetReached,
                    onClockIn: _handleClockIn,
                    onClockOut: _handleClockOut,
                    onUndo: (event) =>
                        _showUndoConfirmationDialog(context, event),
                    onViewHistory: () => RecentShiftsSheet.show(context),
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  flex: 1,
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0xFF334155),
                        width: 1.2,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: RecentShiftsView(
                        showHeader: true,
                        showDragHandle: false,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        onShiftSelected: _selectPastShift,
                        selectedShiftId: _selectedPastShift?.clockOut.id,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusContent(
      BuildContext context, WorkStatus status, bool isLoading) {
    final isClockedIn = status.state == WorkState.clockedIn;
    final timeFormat = DateFormat('HH:mm');

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: Column(
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
          targetClockOutUtc: status.targetClockOutUtc,
          serverTime: status.serverTime,
          todaySeconds: status.todaySeconds,
          monthSeconds: status.monthSeconds,
          enablePeriodicTimer: widget.enableAnimations,
          isAdjustingTarget: _isUpdatingTarget,
          onAdjustTargetDelta: (delta) =>
              _applyTargetUpdate(deltaMinutes: delta),
          onOpenCustomTarget: () => _openCustomTargetDialog(status),
          onTargetReached: _handleTargetReached,
          onViewHistory: () => RecentShiftsSheet.show(context),
        ),
        const SizedBox(height: 36),

        // Action Buttons
        Row(
          children: [
            Expanded(
              child: ClockActionButton(
                isClockIn: true,
                isLoading: isLoading && !isClockedIn,
                isEnabled: !isLoading && !isClockedIn,
                padding: const EdgeInsets.symmetric(vertical: 18),
                onAction: _handleClockIn,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: ClockActionButton(
                isClockIn: false,
                isLoading: isLoading && isClockedIn,
                isEnabled: !isLoading && isClockedIn,
                padding: const EdgeInsets.symmetric(vertical: 18),
                onAction: ({
                  int? offsetMinutes,
                  Duration? plannedDuration,
                  String location = 'remote',
                }) =>
                    _handleClockOut(offsetMinutes: offsetMinutes),
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
            'Last synced: ${timeFormat.format(status.serverTime.toLocal())}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey[500],
                ),
          ),
        ),
      ],
    ),
  ),
);
  }

  void _triggerHapticIfEnabled() {
    final haptics =
        ref.read(settingsProvider).value?.vibrationsEnabled ?? true;
    if (haptics) {
      ref.read(hapticServiceProvider).vibrate();
    }
  }

  Future<void> _handleClockIn({
    int? offsetMinutes,
    Duration? plannedDuration,
    String location = 'remote',
  }) async {
    _triggerHapticIfEnabled();
    await ref.read(currentStatusProvider.notifier).clockIn(
          offsetMinutes: offsetMinutes,
          location: location,
          targetMinutes: plannedDuration?.inMinutes,
        );
    final statusAsync = ref.read(currentStatusProvider);
    if (!statusAsync.hasError && mounted) {
      _activeShiftDraft = null;
      if (_selectedPastShift == null) {
        _notesController.clear();
      }
      await ShiftNotesCard.clearDraft();
      unawaited(ref.read(widgetSyncServiceProvider).syncActiveNote(''));
    }
  }

  Future<void> _handleClockOut({int? offsetMinutes}) async {
    _triggerHapticIfEnabled();
    _isManualClockOut = true;
    try {
      _lastReminderSignature = null;
      await _enqueueReminderOp(
        () => ref.read(notificationServiceProvider).cancelShiftReminder(),
      );

      String noteToSaveOnClockOut = '';
      if (_selectedPastShift != null) {
        // Dual-save edge case: save past shift note first, then retrieve active draft
        await _savePastShiftNote(_selectedPastShift!, _notesController.text);
        noteToSaveOnClockOut =
            _activeShiftDraft ?? (await ShiftNotesCard.loadSavedDraft()) ?? '';
      } else {
        noteToSaveOnClockOut = _notesController.text.trim();
      }

      await ref.read(currentStatusProvider.notifier).clockOut(
            note: noteToSaveOnClockOut.isNotEmpty ? noteToSaveOnClockOut : null,
            offsetMinutes: offsetMinutes,
          );

      final statusAsync = ref.read(currentStatusProvider);
      if (statusAsync.hasError) return;

      final updated = statusAsync.value;
      // If server just auto-stopped right before manual tap, still persist typed shift note
      if (updated != null &&
          !updated.changed &&
          updated.latestEvent?.eventType == 'clock_out' &&
          noteToSaveOnClockOut.isNotEmpty) {
        try {
          await ref.read(apiClientProvider).updateEventNote(
                eventId: updated.latestEvent!.id,
                note: noteToSaveOnClockOut,
              );
        } catch (e) {
          ref.read(shiftsProvider.notifier).refresh();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Shift was already stopped, but failed to save note (draft kept): $e',
                ),
                backgroundColor: Colors.orangeAccent,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
          return;
        }
      }

      _activeShiftDraft = null;
      _selectedPastShift = null;
      _notesController.clear();
      await ShiftNotesCard.clearDraft();
      unawaited(ref.read(widgetSyncServiceProvider).syncActiveNote(''));
      ref.read(shiftsProvider.notifier).refresh();
    } finally {
      _isManualClockOut = false;
    }
  }

  Future<void> _applyTargetUpdate({
    int? deltaMinutes,
    int? targetMinutes,
    bool clearTarget = false,
  }) async {
    if (!mounted || _isUpdatingTarget) return;
    _triggerHapticIfEnabled();
    setState(() => _isUpdatingTarget = true);
    try {
      await ref.read(currentStatusProvider.notifier).updateShiftTarget(
            deltaMinutes: deltaMinutes,
            targetMinutes: targetMinutes,
            clearTarget: clearTarget,
          );
    } catch (e) {
      if (e is ApiException &&
          (e.statusCode == 409 ||
              e.code == 'NOT_CLOCKED_IN' ||
              e.code == 'STATE_CONFLICT')) {
        unawaited(ref.read(currentStatusProvider.notifier).refreshStatus());
      }
      if (mounted) {
        final message = (e is ApiException)
            ? '${e.message} (${e.code})'
            : 'Failed to update target: $e';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUpdatingTarget = false);
      }
    }
  }

  Future<void> _openCustomTargetDialog(WorkStatus status) async {
    if (status.activeSince == null) return;
    final result = await ShiftTargetDialog.show(
      context,
      activeSince: status.activeSince!,
      currentTargetUtc: status.targetClockOutUtc,
    );
    if (result == null || !mounted) return;
    await _applyTargetUpdate(
      targetMinutes: result.targetMinutes,
      clearTarget: result.clearTarget,
    );
  }

  Future<void> _handleTargetReached() async {
    if (!mounted || _isRefreshingTargetReached) return;
    _isRefreshingTargetReached = true;
    try {
      await ref.read(currentStatusProvider.notifier).refreshStatus();
    } finally {
      _isRefreshingTargetReached = false;
    }
  }

  Future<void> _flushDraftToAutoStoppedEvent(String clockOutEventId) async {
    final bool editingActiveDraft = _selectedPastShift == null;
    final rawDraft = editingActiveDraft
        ? (_notesController.text.isNotEmpty
            ? _notesController.text
            : (_activeShiftDraft ?? await ShiftNotesCard.loadSavedDraft() ?? ''))
        : (_activeShiftDraft ?? await ShiftNotesCard.loadSavedDraft() ?? '');
    final draft = rawDraft.trim();
    if (draft.isNotEmpty) {
      try {
        await ref.read(apiClientProvider).updateEventNote(
              eventId: clockOutEventId,
              note: draft,
            );
        ref.read(shiftsProvider.notifier).refresh();
      } catch (_) {
        // Keep local draft intact if network fails
        return;
      }
    }
    if (!mounted) return;
    _activeShiftDraft = null;
    final userTypedNewDraft = _selectedPastShift == null &&
        _notesController.text != rawDraft &&
        _notesController.text.isNotEmpty;
    if (!userTypedNewDraft) {
      if (_selectedPastShift == null) {
        _notesController.clear();
      }
      await ShiftNotesCard.clearDraft();
      unawaited(ref.read(widgetSyncServiceProvider).syncActiveNote(''));
    }
  }

  void _syncReminderIfNeeded(WorkStatus status) {
    final reminderMinutes =
        ref.read(settingsProvider).value?.shiftReminderMinutes ?? 0;
    final sig =
        '${status.isClockedIn}|${status.targetClockOutUtc?.toUtc().toIso8601String()}|$reminderMinutes';
    if (_lastReminderSignature == sig) return;
    _lastReminderSignature = sig;
    unawaited(
      _enqueueReminderOp(
        () => _applyShiftReminderSync(status, reminderMinutes, sig),
      ),
    );
  }

  Future<void> _applyShiftReminderSync(
    WorkStatus status,
    int reminderMinutes,
    String expectedSig,
  ) async {
    if (_lastReminderSignature != expectedSig) return;
    final notificationService = ref.read(notificationServiceProvider);
    await notificationService.cancelShiftReminder();
    if (_lastReminderSignature != expectedSig) return;
    if (status.isClockedIn &&
        status.targetClockOutUtc != null &&
        reminderMinutes > 0 &&
        status.targetClockOutUtc!.toLocal().isAfter(DateTime.now())) {
      await notificationService.scheduleShiftReminder(
        targetEndTime: status.targetClockOutUtc!.toLocal(),
        minutesBefore: reminderMinutes,
      );
    }
  }

  Future<void> _showUndoConfirmationDialog(
    BuildContext context,
    LatestEventSummary event,
  ) async {
    final eventTypeLabel =
        event.eventType == 'clock_in' ? 'Clock In' : 'Clock Out';
    final timeStr =
        DateFormat('HH:mm').format(event.occurredAtUtc.toLocal());

    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF334155), width: 1.2),
        ),
        title: const Row(
          children: [
            Icon(Icons.undo, color: Color(0xFFFBBF24)),
            SizedBox(width: 8),
            Text('Revert Action'),
          ],
        ),
        content: Text(
          'Revert $eventTypeLabel recorded at $timeStr?',
          style: const TextStyle(color: Color(0xFFE2E8F0)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF59E0B),
              foregroundColor: Colors.black,
              textStyle: const TextStyle(fontWeight: FontWeight.w700),
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
        final statusAfterUndo = ref.read(currentStatusProvider);
        if (statusAfterUndo.hasError) {
          return;
        }
        _lastReminderSignature = null;
        if (statusAfterUndo.value != null) {
          _syncReminderIfNeeded(statusAfterUndo.value!);
        } else {
          await _enqueueReminderOp(
            () => ref.read(notificationServiceProvider).cancelShiftReminder(),
          );
        }
        if (mounted) {
          messenger.showSnackBar(
            SnackBar(
              content: Text('Successfully reverted $eventTypeLabel!'),
              backgroundColor: const Color(0xFF0F766E),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          messenger.showSnackBar(
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
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.amber),
            const SizedBox(height: 16),
            Text(
              'Connection or Server Error',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              error.toString(),
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: const Color(0xFF94A3B8)),
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: isLoading
                      ? null
                      : () =>
                          ref.read(currentStatusProvider.notifier).refreshStatus(),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.black,
                    textStyle: const TextStyle(fontWeight: FontWeight.w700),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => SettingsDialog.show(context),
                  icon: const Icon(Icons.settings),
                  label: const Text('Configure Server'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF38BDF8),
                    side: const BorderSide(color: Color(0xFF38BDF8)),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
