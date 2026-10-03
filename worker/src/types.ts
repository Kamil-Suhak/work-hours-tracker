export type WorkState = 'clocked_in' | 'clocked_out';

export type EventSource =
  | 'flutter_app'
  | 'android_widget'
  | 'admin_manual'
  | 'web_dashboard';

export type EventType = 'clock_in' | 'clock_out';

export interface Env {
  DB: D1Database;
  ADMIN_API_TOKEN?: string;
  DEVICE_TOKEN_PEPPER?: string;
}

export interface DeviceRow {
  id: string;
  name: string;
  token_hash: string;
  enabled: number;
  created_at_utc: string;
}

export interface WorkStateRow {
  user_id: string;
  state: WorkState;
  active_since_utc: string | null;
  version: number;
  updated_at_utc: string;
}

export interface EventRow {
  id: string;
  request_id: string;
  user_id: string;
  device_id: string | null;
  event_type: EventType;
  source: EventSource;
  occurred_at_utc: string;
  created_at_utc: string;
  reason: string | null;
}

export interface ProcessedRequestRow {
  request_id: string;
  user_id: string;
  operation: string;
  response_json: string;
  created_at_utc: string;
}

export interface ClockRequestBody {
  requestId: string;
  source: EventSource;
}

export interface LatestEventInfo {
  id: string;
  eventType: EventType;
  occurredAtUtc: string;
}

export interface CommandResponse {
  state: WorkState;
  changed: boolean;
  activeSince: string | null;
  serverTime: string;
  todaySeconds: number;
  monthSeconds: number;
  latestEvent?: LatestEventInfo | null;
}

export interface StatusResponse {
  state: WorkState;
  activeSince: string | null;
  serverTime: string;
  todaySeconds: number;
  monthSeconds: number;
  latestEvent?: LatestEventInfo | null;
}

export interface ManualEventRequestBody {
  clockInAt: string;
  clockOutAt: string;
  reason: string;
  requestId: string;
}

export interface ManualEventResponse {
  success: boolean;
  clockInEventId: string;
  clockOutEventId: string;
  clockInAt: string;
  clockOutAt: string;
  durationSeconds: number;
}

export interface UndoRequestBody {
  requestId: string;
  eventId: string;
}

export interface UndoResponse {
  success: boolean;
  undoneEventId: string;
  restoredState: WorkState;
  activeSince: string | null;
  serverTime: string;
  todaySeconds: number;
  monthSeconds: number;
  latestEvent?: LatestEventInfo | null;
}

export interface ApiErrorResponse {
  error: {
    code: string;
    message: string;
    requestId?: string;
  };
}
