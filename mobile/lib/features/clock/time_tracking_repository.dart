import 'package:uuid/uuid.dart';
import '../../api/api_client.dart';
import '../../api/models.dart';

class TimeTrackingRepository {
  final ApiClient _apiClient;
  final Uuid _uuid = const Uuid();

  TimeTrackingRepository(this._apiClient);

  Future<WorkStatus> fetchCurrentStatus() async {
    return await _apiClient.getStatus();
  }

  Future<WorkStatus> clockIn() async {
    final requestId = _uuid.v4();
    return await _apiClient.clockIn(requestId: requestId);
  }

  Future<WorkStatus> clockOut() async {
    final requestId = _uuid.v4();
    return await _apiClient.clockOut(requestId: requestId);
  }

  Future<List<TrackingEvent>> fetchEvents(DateTime from, DateTime to) async {
    return await _apiClient.getEvents(from: from, to: to);
  }
}
