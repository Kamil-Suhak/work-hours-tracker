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

  @override
  Future<WorkStatus> build() async {
    final repository = ref.read(timeTrackingRepositoryProvider);
    final status = await repository.fetchCurrentStatus();
    _syncWidget(status);
    return status;
  }

  Future<void> refreshStatus() async {
    state = const AsyncLoading<WorkStatus>().copyWithPrevious(state);
    state = await AsyncValue.guard(() async {
      final repository = ref.read(timeTrackingRepositoryProvider);
      final status = await repository.fetchCurrentStatus();
      _syncWidget(status);
      return status;
    });
  }

  Future<void> clockIn({int? offsetMinutes}) async {
    state = const AsyncLoading<WorkStatus>().copyWithPrevious(state);
    state = await AsyncValue.guard(() async {
      final repository = ref.read(timeTrackingRepositoryProvider);
      final res = await repository.clockIn(offsetMinutes: offsetMinutes);
      ref.invalidate(shiftsProvider);
      _syncWidget(res);
      return res;
    });
  }

  Future<void> clockOut({String? note, int? offsetMinutes}) async {
    state = const AsyncLoading<WorkStatus>().copyWithPrevious(state);
    state = await AsyncValue.guard(() async {
      final repository = ref.read(timeTrackingRepositoryProvider);
      final res = await repository.clockOut(note: note, offsetMinutes: offsetMinutes);
      ref.invalidate(shiftsProvider);
      _syncWidget(res);
      return res;
    });
  }

  Future<void> undo(String eventId) async {
    state = const AsyncLoading<WorkStatus>().copyWithPrevious(state);
    state = await AsyncValue.guard(() async {
      final repository = ref.read(timeTrackingRepositoryProvider);
      final result = await repository.undo(eventId);
      ref.invalidate(shiftsProvider);
      _syncWidget(result.status);
      return result.status;
    });
  }
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
