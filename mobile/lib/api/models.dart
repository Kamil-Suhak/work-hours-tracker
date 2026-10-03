enum WorkState {
  clockedIn,
  clockedOut;

  static WorkState fromString(String value) {
    switch (value) {
      case 'clocked_in':
        return WorkState.clockedIn;
      case 'clocked_out':
        return WorkState.clockedOut;
      default:
        throw FormatException('Unrecognized WorkState: "$value"');
    }
  }

  String toApiString() {
    return this == WorkState.clockedIn ? 'clocked_in' : 'clocked_out';
  }
}

class WorkStatus {
  final WorkState state;
  final bool changed;
  final DateTime? activeSince;
  final DateTime serverTime;
  final int todaySeconds;
  final int monthSeconds;

  const WorkStatus({
    required this.state,
    this.changed = false,
    this.activeSince,
    required this.serverTime,
    required this.todaySeconds,
    required this.monthSeconds,
  });

  factory WorkStatus.fromJson(Map<String, dynamic> json) {
    return WorkStatus(
      state: WorkState.fromString(json['state'] as String),
      changed: json['changed'] as bool? ?? false,
      activeSince: json['activeSince'] != null
          ? DateTime.parse(json['activeSince'] as String)
          : null,
      serverTime: DateTime.parse(json['serverTime'] as String),
      todaySeconds: json['todaySeconds'] as int? ?? 0,
      monthSeconds: json['monthSeconds'] as int? ?? 0,
    );
  }
}

class TrackingEvent {
  final String id;
  final String requestId;
  final String userId;
  final String? deviceId;
  final String eventType;
  final String source;
  final DateTime occurredAtUtc;
  final DateTime createdAtUtc;
  final String? reason;

  const TrackingEvent({
    required this.id,
    required this.requestId,
    required this.userId,
    this.deviceId,
    required this.eventType,
    required this.source,
    required this.occurredAtUtc,
    required this.createdAtUtc,
    this.reason,
  });

  factory TrackingEvent.fromJson(Map<String, dynamic> json) {
    return TrackingEvent(
      id: json['id'] as String,
      requestId: json['request_id'] as String,
      userId: json['user_id'] as String,
      deviceId: json['device_id'] as String?,
      eventType: json['event_type'] as String,
      source: json['source'] as String,
      occurredAtUtc: DateTime.parse(json['occurred_at_utc'] as String),
      createdAtUtc: DateTime.parse(json['created_at_utc'] as String),
      reason: json['reason'] as String?,
    );
  }
}

class ApiException implements Exception {
  final String code;
  final String message;
  final String? requestId;
  final int statusCode;

  const ApiException({
    required this.code,
    required this.message,
    this.requestId,
    required this.statusCode,
  });

  @override
  String toString() => 'ApiException($code, status: $statusCode): $message';
}
