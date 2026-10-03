import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../api/models.dart';
import '../clock/clock_notifier.dart';

final recentEventsProvider = FutureProvider.autoDispose<List<TrackingEvent>>((ref) async {
  final repository = ref.watch(timeTrackingRepositoryProvider);
  final now = DateTime.now();
  final sevenDaysAgo = now.subtract(const Duration(days: 7));
  return await repository.fetchEvents(sevenDaysAgo, now);
});
