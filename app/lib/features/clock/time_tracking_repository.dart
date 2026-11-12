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

  Future<WorkStatus> clockIn({
    int? offsetMinutes,
    String location = 'remote',
    int? targetMinutes,
  }) async {
    final requestId = _uuid.v4();
    return await _apiClient.clockIn(
      requestId: requestId,
      offsetMinutes: offsetMinutes,
      location: location,
      targetMinutes: targetMinutes,
    );
  }

  Future<WorkStatus> updateShiftTarget({
    int? deltaMinutes,
    int? targetMinutes,
    bool clearTarget = false,
  }) async {
    return await _apiClient.updateShiftTarget(
      deltaMinutes: deltaMinutes,
      targetMinutes: targetMinutes,
      clearTarget: clearTarget,
    );
  }

  Future<WorkStatus> clockOut({String? note, int? offsetMinutes}) async {
    final requestId = _uuid.v4();
    return await _apiClient.clockOut(
      requestId: requestId,
      note: note,
      offsetMinutes: offsetMinutes,
    );
  }

  Future<List<TrackingEvent>> fetchEvents(DateTime from, DateTime to) async {
    return await _apiClient.getEvents(from: from, to: to);
  }

  Future<UndoResult> undo(String eventId) async {
    final requestId = _uuid.v4();
    return await _apiClient.undo(eventId: eventId, requestId: requestId);
  }
}
