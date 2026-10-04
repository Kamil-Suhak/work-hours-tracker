import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../clock/clock_notifier.dart';
import 'shift_model.dart';
import 'shift_notes_storage.dart';

class ShiftsNotifier extends AsyncNotifier<List<ShiftRecord>> {
  @override
  Future<List<ShiftRecord>> build() async {
    return _fetchShifts();
  }

  Future<List<ShiftRecord>> _fetchShifts() async {
    await ShiftNotesStorage.loadCache();
    final repository = ref.read(timeTrackingRepositoryProvider);
    final now = DateTime.now().toUtc();
    final from = DateTime.utc(now.year, now.month - 1, 1);
    final to = now.add(const Duration(hours: 1));

    final events = await repository.fetchEvents(from, to);
    return pairEventsIntoShifts(events);
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_fetchShifts);
  }
}

final shiftsProvider =
    AsyncNotifierProvider<ShiftsNotifier, List<ShiftRecord>>(
  ShiftsNotifier.new,
);
