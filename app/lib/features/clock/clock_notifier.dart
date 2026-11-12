// ignore_for_file: invalid_use_of_internal_member
// probably not best practice

import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../api/api_client.dart';
import '../../api/models.dart';
import 'time_tracking_repository.dart';

import '../../config/app_config.dart';
import '../../services/platform/platform_services.dart';
import '../history/shifts_notifier.dart';
import '../settings/settings_notifier.dart';

// Configurable base URL provider wired to user settings
final apiBaseUrlProvider = Provider<String>((ref) {
  final settingsAsync = ref.watch(settingsProvider);
  return settingsAsync.value?.baseUrl ?? AppConfig.defaultApiBaseUrl;
});

final apiClientProvider = Provider<ApiClient>((ref) {
  final baseUrl = ref.watch(apiBaseUrlProvider);
  final settings = ref.watch(settingsProvider).value;
  return ApiClient(baseUrl: baseUrl, token: settings?.deviceToken);
});

final timeTrackingRepositoryProvider = Provider<TimeTrackingRepository>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return TimeTrackingRepository(apiClient);
});

class CurrentStatusNotifier extends AsyncNotifier<WorkStatus> {
  void _syncWidget(WorkStatus status) {
    try {
      final widgetSync = ref.read(widgetSyncServiceProvider);
      unawaited(widgetSync.syncWidgetStatus(
        isClockedIn: status.isClockedIn,
      ));
    } catch (_) {}
  }

  Future<void> _runStatusTransition(
    Future<WorkStatus> Function(TimeTrackingRepository repo) action, {
    bool invalidateShifts = true,
    bool resetToLoading = false,
  }) async {
    final prevClockedIn = state.value?.isClockedIn ?? false;
    state = resetToLoading
        ? const AsyncValue.loading()
        : const AsyncLoading<WorkStatus>().copyWithPrevious(state);
    state = await AsyncValue.guard(() async {
      final repository = ref.read(timeTrackingRepositoryProvider);
      final status = await action(repository);
      if (invalidateShifts || (prevClockedIn && status.isClockedOut)) {
        ref.invalidate(shiftsProvider);
      }
      _syncWidget(status);
      return status;
    });
  }

  @override
  Future<WorkStatus> build() async {
    final repository = ref.watch(timeTrackingRepositoryProvider);
    final status = await repository.fetchCurrentStatus();
    _syncWidget(status);
    return status;
  }

  Future<void> refreshStatus() => _runStatusTransition(
        (repo) => repo.fetchCurrentStatus(),
        invalidateShifts: false,
      );

  Future<void> resetAndRefresh() => _runStatusTransition(
        (repo) => repo.fetchCurrentStatus(),
        invalidateShifts: false,
        resetToLoading: true,
      );

  Future<void> clockIn({
    int? offsetMinutes,
    String location = 'remote',
    int? targetMinutes,
  }) =>
      _runStatusTransition(
        (repo) => repo.clockIn(
          offsetMinutes: offsetMinutes,
          location: location,
          targetMinutes: targetMinutes,
        ),
      );

  Future<WorkStatus> updateShiftTarget({
    int? deltaMinutes,
    int? targetMinutes,
    bool clearTarget = false,
  }) async {
    final repository = ref.read(timeTrackingRepositoryProvider);
    final updated = await repository.updateShiftTarget(
      deltaMinutes: deltaMinutes,
      targetMinutes: targetMinutes,
      clearTarget: clearTarget,
    );
    state = AsyncData(updated);
    _syncWidget(updated);
    return updated;
  }

  Future<void> clockOut({String? note, int? offsetMinutes}) =>
      _runStatusTransition(
        (repo) => repo.clockOut(note: note, offsetMinutes: offsetMinutes),
      );

  Future<void> undo(String eventId) => _runStatusTransition(
        (repo) async => (await repo.undo(eventId)).status,
      );
}

final currentStatusProvider =
    AsyncNotifierProvider<CurrentStatusNotifier, WorkStatus>(
  CurrentStatusNotifier.new,
);

String formatSeconds(int totalSeconds) {
  if (totalSeconds <= 0) return '0h 0m';
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  return '${hours}h ${minutes}m';
}
