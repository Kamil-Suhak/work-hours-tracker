import type { D1Database } from '@cloudflare/workers-types';
import type {
  ClockRequestBody,
  CommandResponse,
  EventRow,
  EventSource,
  UndoRequestBody,
  UndoResponse,
  WorkState,
  WorkStateRow,
  ProcessedRequestRow,
} from './types';
import { AppError } from './errors';
import { calculateDurations, getWarsawDateComponents } from './status';

export const DEFAULT_USER_ID = 'default-user';

const VALID_SOURCES = new Set<EventSource>([
  'flutter_app',
  'android_widget',
  'admin_manual',
  'web_dashboard',
]);

export function validateClockRequest(body: unknown): ClockRequestBody {
  if (!body || typeof body !== 'object') {
    throw new AppError('VALIDATION_ERROR', 'Request body must be a JSON object.', 400);
  }

  const { requestId, source } = body as Record<string, unknown>;

  if (typeof requestId !== 'string' || requestId.trim().length === 0) {
    throw new AppError('INVALID_REQUEST_ID', 'requestId must be a non-empty string.', 400);
  }

  if (requestId.length > 128) {
    throw new AppError('INVALID_REQUEST_ID', 'requestId exceeds maximum length of 128.', 400);
  }

  if (typeof source !== 'string' || !VALID_SOURCES.has(source as EventSource)) {
    throw new AppError(
      'INVALID_SOURCE',
      `source must be one of: ${Array.from(VALID_SOURCES).join(', ')}`,
      400,
      requestId
    );
  }

  return {
    requestId: requestId.trim(),
    source: source as EventSource,
  };
}

export async function handleClockIn(
  db: D1Database,
  deviceId: string,
  req: ClockRequestBody,
  now: Date = new Date()
): Promise<CommandResponse> {
  const { requestId, source } = req;
  const nowIso = now.toISOString();

  // 1. Idempotency check: return cached outcome if requestId was already processed
  const cached = await db
    .prepare('SELECT response_json FROM processed_requests WHERE request_id = ?')
    .bind(requestId)
    .first<Pick<ProcessedRequestRow, 'response_json'>>();

  if (cached) {
    return JSON.parse(cached.response_json) as CommandResponse;
  }

  // 2. Query current state
  const stateRow = await db
    .prepare(
      'SELECT user_id, state, active_since_utc, version, updated_at_utc FROM work_state WHERE user_id = ?'
    )
    .bind(DEFAULT_USER_ID)
    .first<WorkStateRow>();

  const currentState: WorkState = stateRow?.state ?? 'clocked_out';

  if (currentState === 'clocked_in') {
    // Already clocked in: insert nothing, return current state with changed: false
    const { todaySeconds, monthSeconds } = await calculateDurations(
      db,
      DEFAULT_USER_ID,
      'clocked_in',
      stateRow?.active_since_utc ?? nowIso,
      now
    );

    const response: CommandResponse = {
      state: 'clocked_in',
      changed: false,
      activeSince: stateRow?.active_since_utc ?? nowIso,
      serverTime: nowIso,
      todaySeconds,
      monthSeconds,
    };

    // Store in processed_requests so repeated calls are idempotent
    await db
      .prepare(
        'INSERT OR IGNORE INTO processed_requests (request_id, user_id, operation, response_json, created_at_utc) VALUES (?, ?, ?, ?, ?)'
      )
      .bind(requestId, DEFAULT_USER_ID, 'clock_in', JSON.stringify(response), nowIso)
      .run();

    return response;
  }

  // Currently clocked_out: transition to clocked_in
  const eventId = crypto.randomUUID();
  const nextVersion = (stateRow?.version ?? 0) + 1;

  const { todaySeconds, monthSeconds } = await calculateDurations(
    db,
    DEFAULT_USER_ID,
    'clocked_in',
    nowIso,
    now
  );

  const response: CommandResponse = {
    state: 'clocked_in',
    changed: true,
    activeSince: nowIso,
    serverTime: nowIso,
    todaySeconds,
    monthSeconds,
    latestEvent: {
      id: eventId,
      eventType: 'clock_in',
      occurredAtUtc: nowIso,
    },
  };

  const responseJson = JSON.stringify(response);

  // Execute atomic batch
  await db.batch([
    db
      .prepare(
        `INSERT INTO events (id, request_id, user_id, device_id, event_type, source, occurred_at_utc, created_at_utc)
         VALUES (?, ?, ?, ?, 'clock_in', ?, ?, ?)`
      )
      .bind(eventId, requestId, DEFAULT_USER_ID, deviceId, source, nowIso, nowIso),
    db
      .prepare(
        `INSERT INTO work_state (user_id, state, active_since_utc, version, updated_at_utc)
         VALUES (?, 'clocked_in', ?, ?, ?)
         ON CONFLICT(user_id) DO UPDATE SET
           state = 'clocked_in',
           active_since_utc = excluded.active_since_utc,
           version = excluded.version,
           updated_at_utc = excluded.updated_at_utc`
      )
      .bind(DEFAULT_USER_ID, nowIso, nextVersion, nowIso),
    db
      .prepare(
        `INSERT INTO processed_requests (request_id, user_id, operation, response_json, created_at_utc)
         VALUES (?, ?, ?, ?, ?)`
      )
      .bind(requestId, DEFAULT_USER_ID, 'clock_in', responseJson, nowIso),
  ]);

  return response;
}

export async function handleClockOut(
  db: D1Database,
  deviceId: string,
  req: ClockRequestBody,
  now: Date = new Date()
): Promise<CommandResponse> {
  const { requestId, source } = req;
  const nowIso = now.toISOString();

  // 1. Idempotency check
  const cached = await db
    .prepare('SELECT response_json FROM processed_requests WHERE request_id = ?')
    .bind(requestId)
    .first<Pick<ProcessedRequestRow, 'response_json'>>();

  if (cached) {
    return JSON.parse(cached.response_json) as CommandResponse;
  }

  // 2. Query current state
  const stateRow = await db
    .prepare(
      'SELECT user_id, state, active_since_utc, version, updated_at_utc FROM work_state WHERE user_id = ?'
    )
    .bind(DEFAULT_USER_ID)
    .first<WorkStateRow>();

  const currentState: WorkState = stateRow?.state ?? 'clocked_out';

  if (currentState === 'clocked_out') {
    // Already clocked out: insert nothing, return current state with changed: false
    const { todaySeconds, monthSeconds } = await calculateDurations(
      db,
      DEFAULT_USER_ID,
      'clocked_out',
      null,
      now
    );

    const response: CommandResponse = {
      state: 'clocked_out',
      changed: false,
      activeSince: null,
      serverTime: nowIso,
      todaySeconds,
      monthSeconds,
    };

    await db
      .prepare(
        'INSERT OR IGNORE INTO processed_requests (request_id, user_id, operation, response_json, created_at_utc) VALUES (?, ?, ?, ?, ?)'
      )
      .bind(requestId, DEFAULT_USER_ID, 'clock_out', JSON.stringify(response), nowIso)
      .run();

    return response;
  }

  // Currently clocked_in: transition to clocked_out
  const eventId = crypto.randomUUID();
  const nextVersion = (stateRow?.version ?? 0) + 1;

  // Calculate shift duration and cumulative totals with this shift included
  const activeSince = stateRow?.active_since_utc ?? nowIso;
  const completedShiftSeconds = Math.max(
    0,
    Math.floor((now.getTime() - new Date(activeSince).getTime()) / 1000)
  );

  const activeStartDate = new Date(activeSince);
  const { dateString: shiftDateString, monthString: shiftMonthString } =
    getWarsawDateComponents(activeStartDate);
  const { dateString: todayString, monthString: currentMonthString } =
    getWarsawDateComponents(now);

  const prevDurations = await calculateDurations(
    db,
    DEFAULT_USER_ID,
    'clocked_out',
    null,
    now
  );

  const response: CommandResponse = {
    state: 'clocked_out',
    changed: true,
    activeSince: null,
    serverTime: nowIso,
    todaySeconds:
      prevDurations.todaySeconds +
      (shiftDateString === todayString ? completedShiftSeconds : 0),
    monthSeconds:
      prevDurations.monthSeconds +
      (shiftMonthString === currentMonthString ? completedShiftSeconds : 0),
    latestEvent: {
      id: eventId,
      eventType: 'clock_out',
      occurredAtUtc: nowIso,
    },
  };

  const responseJson = JSON.stringify(response);

  // Execute atomic batch
  await db.batch([
    db
      .prepare(
        `INSERT INTO events (id, request_id, user_id, device_id, event_type, source, occurred_at_utc, created_at_utc)
         VALUES (?, ?, ?, ?, 'clock_out', ?, ?, ?)`
      )
      .bind(eventId, requestId, DEFAULT_USER_ID, deviceId, source, nowIso, nowIso),
    db
      .prepare(
        `INSERT INTO work_state (user_id, state, active_since_utc, version, updated_at_utc)
         VALUES (?, 'clocked_out', NULL, ?, ?)
         ON CONFLICT(user_id) DO UPDATE SET
           state = 'clocked_out',
           active_since_utc = NULL,
           version = excluded.version,
           updated_at_utc = excluded.updated_at_utc`
      )
      .bind(DEFAULT_USER_ID, nextVersion, nowIso),
    db
      .prepare(
        `INSERT INTO processed_requests (request_id, user_id, operation, response_json, created_at_utc)
         VALUES (?, ?, ?, ?, ?)`
      )
      .bind(requestId, DEFAULT_USER_ID, 'clock_out', responseJson, nowIso),
  ]);

  return response;
}

export function validateUndoRequest(body: unknown): UndoRequestBody {
  if (!body || typeof body !== 'object') {
    throw new AppError('VALIDATION_ERROR', 'Request body must be a JSON object.', 400);
  }

  const { requestId, eventId } = body as Record<string, unknown>;

  if (typeof requestId !== 'string' || requestId.trim().length === 0) {
    throw new AppError('INVALID_REQUEST_ID', 'requestId must be a non-empty string.', 400);
  }

  if (requestId.length > 128) {
    throw new AppError('INVALID_REQUEST_ID', 'requestId exceeds maximum length of 128.', 400);
  }

  if (typeof eventId !== 'string' || eventId.trim().length === 0) {
    throw new AppError(
      'INVALID_EVENT_ID',
      'eventId must be a non-empty string specifying the event to undo.',
      400,
      requestId
    );
  }

  return {
    requestId: requestId.trim(),
    eventId: eventId.trim(),
  };
}

export async function handleUndo(
  db: D1Database,
  req: UndoRequestBody,
  now: Date = new Date()
): Promise<UndoResponse> {
  const { requestId, eventId } = req;
  const nowIso = now.toISOString();

  // 1. Idempotency check
  const cached = await db
    .prepare('SELECT response_json FROM processed_requests WHERE request_id = ?')
    .bind(requestId)
    .first<Pick<ProcessedRequestRow, 'response_json'>>();

  if (cached) {
    return JSON.parse(cached.response_json) as UndoResponse;
  }

  // 2. Query latest event
  const latestEvent = await db
    .prepare(
      'SELECT id, event_type, occurred_at_utc FROM events WHERE user_id = ? ORDER BY occurred_at_utc DESC, id DESC LIMIT 1'
    )
    .bind(DEFAULT_USER_ID)
    .first<Pick<EventRow, 'id' | 'event_type' | 'occurred_at_utc'>>();

  if (!latestEvent) {
    throw new AppError('NO_EVENTS_FOUND', 'No clock events exist to undo.', 404, requestId);
  }

  if (latestEvent.id !== eventId) {
    throw new AppError(
      'EVENT_MISMATCH',
      'The specified event is not the latest event and cannot be undone.',
      409,
      requestId
    );
  }

  // 3. Grace period check: 5 minutes (300,000 ms)
  const eventTimeMs = new Date(latestEvent.occurred_at_utc).getTime();
  const nowMs = now.getTime();
  const UNDO_WINDOW_MS = 5 * 60 * 1000;
  if (nowMs - eventTimeMs > UNDO_WINDOW_MS) {
    throw new AppError('UNDO_WINDOW_EXPIRED', 'The 5-minute undo window has expired.', 400, requestId);
  }

  // 4. Query preceding event to determine restored state
  const prevEvent = await db
    .prepare(
      'SELECT id, event_type, occurred_at_utc FROM events WHERE user_id = ? AND id != ? ORDER BY occurred_at_utc DESC, id DESC LIMIT 1'
    )
    .bind(DEFAULT_USER_ID, eventId)
    .first<Pick<EventRow, 'id' | 'event_type' | 'occurred_at_utc'>>();

  const restoredState: WorkState = prevEvent?.event_type === 'clock_in' ? 'clocked_in' : 'clocked_out';
  const restoredActiveSince: string | null = restoredState === 'clocked_in' ? prevEvent!.occurred_at_utc : null;

  // 5. Query current work_state version
  const stateRow = await db
    .prepare('SELECT version FROM work_state WHERE user_id = ?')
    .bind(DEFAULT_USER_ID)
    .first<Pick<WorkStateRow, 'version'>>();

  const nextVersion = (stateRow?.version ?? 0) + 1;

  // 6. Delete event from DB
  await db.prepare('DELETE FROM events WHERE id = ?').bind(eventId).run();

  // 7. Calculate restored durations
  const { todaySeconds, monthSeconds } = await calculateDurations(
    db,
    DEFAULT_USER_ID,
    restoredState,
    restoredActiveSince,
    now
  );

  const response: UndoResponse = {
    success: true,
    undoneEventId: eventId,
    restoredState,
    activeSince: restoredActiveSince,
    serverTime: nowIso,
    todaySeconds,
    monthSeconds,
    latestEvent: prevEvent
      ? {
          id: prevEvent.id,
          eventType: prevEvent.event_type,
          occurredAtUtc: prevEvent.occurred_at_utc,
        }
      : null,
  };

  const responseJson = JSON.stringify(response);

  // 8. Update work_state and record processed request
  await db.batch([
    db
      .prepare(
        `INSERT INTO work_state (user_id, state, active_since_utc, version, updated_at_utc)
         VALUES (?, ?, ?, ?, ?)
         ON CONFLICT(user_id) DO UPDATE SET
           state = excluded.state,
           active_since_utc = excluded.active_since_utc,
           version = excluded.version,
           updated_at_utc = excluded.updated_at_utc`
      )
      .bind(DEFAULT_USER_ID, restoredState, restoredActiveSince, nextVersion, nowIso),
    db
      .prepare(
        `INSERT INTO processed_requests (request_id, user_id, operation, response_json, created_at_utc)
         VALUES (?, ?, ?, ?, ?)`
      )
      .bind(requestId, DEFAULT_USER_ID, 'undo', responseJson, nowIso),
  ]);

  return response;
}
