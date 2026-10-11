import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/app_config.dart';
import '../../services/platform/platform_services.dart';

class PlannedShiftDurationNotifier extends Notifier<Duration?> {
  @override
  Duration? build() {
    _loadPersistedDuration();
    return null;
  }

  Future<void> _loadPersistedDuration() async {
    final store = ref.read(credentialStoreProvider);
    final raw = await store.read(AppConfig.plannedShiftMinutesKey);
    if (raw != null) {
      final minutes = int.tryParse(raw);
      if (minutes != null && minutes > 0) {
        state = Duration(minutes: minutes);
      }
    }
  }

  Future<void> setDuration(Duration? duration) async {
    state = duration;
    final store = ref.read(credentialStoreProvider);
    if (duration != null) {
      await store.write(
        AppConfig.plannedShiftMinutesKey,
        duration.inMinutes.toString(),
      );
    } else {
      await store.delete(AppConfig.plannedShiftMinutesKey);
    }
  }

  Future<void> clear() async {
    state = null;
    final store = ref.read(credentialStoreProvider);
    await store.delete(AppConfig.plannedShiftMinutesKey);
  }
}

final plannedShiftDurationProvider =
    NotifierProvider<PlannedShiftDurationNotifier, Duration?>(
  PlannedShiftDurationNotifier.new,
);
