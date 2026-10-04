import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../api/api_client.dart';
import '../../api/models.dart';
import 'time_tracking_repository.dart';

import '../settings/settings_notifier.dart';

// Configurable base URL provider wired to user settings
final apiBaseUrlProvider = Provider<String>((ref) {
  final settingsAsync = ref.watch(settingsProvider);
  return settingsAsync.value?.baseUrl ??
      const String.fromEnvironment(
        'API_BASE_URL',
        defaultValue: defaultApiBaseUrl,
      );
});

final apiClientProvider = Provider<ApiClient>((ref) {
  final baseUrl = ref.watch(apiBaseUrlProvider);
  return ApiClient(baseUrl: baseUrl);
});

final timeTrackingRepositoryProvider = Provider<TimeTrackingRepository>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return TimeTrackingRepository(apiClient);
});

class CurrentStatusNotifier extends AsyncNotifier<WorkStatus> {
  @override
  Future<WorkStatus> build() async {
    final repository = ref.read(timeTrackingRepositoryProvider);
    return await repository.fetchCurrentStatus();
  }

  Future<void> refreshStatus() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final repository = ref.read(timeTrackingRepositoryProvider);
      return await repository.fetchCurrentStatus();
    });
  }

  Future<void> clockIn() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final repository = ref.read(timeTrackingRepositoryProvider);
      return await repository.clockIn();
    });
  }

  Future<void> clockOut({String? note}) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final repository = ref.read(timeTrackingRepositoryProvider);
      return await repository.clockOut(note: note);
    });
  }

  Future<void> undo(String eventId) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final repository = ref.read(timeTrackingRepositoryProvider);
      final result = await repository.undo(eventId);
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
