import type { D1Database } from '@cloudflare/workers-types';
import type {
  ClockRequestBody,
  CommandResponse,
  EventRow,
  EventSource,
  StatusResponse,
  UndoRequestBody,
  UndoResponse,
  UpdateTargetRequestBody,
  WorkLocation,
  WorkState,
  WorkStateRow,
  ProcessedRequestRow,
} from './types';
import { AppError } from './errors';
import { calculateDurations, getStatus, getWarsawDateComponents, truncateToMinute } from './status';

export const DEFAULT_USER_ID = 'default-user';
export const MAX_TARGET_MINUTES = 24 * 60; // 24 hours

const VALID_SOURCES = new Set<EventSource>([
  'flutter_app',
  'android_widget',
  'web_dashboard',
]);

export const VALID_LOCATIONS = new Set<WorkLocation>(['remote', 'in-office']);

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

  const note = typeof (body as Record<string, unknown>).note === 'string'
    ? ((body as Record<string, unknown>).note as string).trim()
    : undefined;

  if (note !== undefined && note.length > 4000) {
    throw new AppError(
      'NOTE_TOO_LONG',
      'Note must not exceed 4,000 characters',
      400,
      requestId
    );
  }

  const offsetMinutes = typeof (body as Record<string, unknown>).offsetMinutes === 'number'
    ? ((body as Record<string, unknown>).offsetMinutes as number)
    : undefined;

  if (offsetMinutes !== undefined) {
    if (!Number.isInteger(offsetMinutes) || offsetMinutes < -120 || offsetMinutes > 120) {
      throw new AppError(
        'INVALID_OFFSET',
        'offsetMinutes must be an integer between -120 and 120.',
        400,
        requestId
      );
    }
  }

  const rawLocation = (body as Record<string, unknown>).location;
  let location: WorkLocation | undefined;
  if (rawLocation !== undefined && rawLocation !== null) {
    if (typeof rawLocation !== 'string' || !VALID_LOCATIONS.has(rawLocation as WorkLocation)) {
      throw new AppError(
        'INVALID_LOCATION',
        `location must be one of: ${Array.from(VALID_LOCATIONS).join(', ')}`,
        400,
        requestId
      );
    }
    location = rawLocation as WorkLocation;
  }

  const rawTargetMinutes = (body as Record<string, unknown>).targetMinutes;
  let targetMinutes: number | undefined;
  if (rawTargetMinutes !== undefined && rawTargetMinutes !== null) {
    if (
      typeof rawTargetMinutes !== 'number' ||
      !Number.isInteger(rawTargetMinutes) ||
      rawTargetMinutes < 1 ||
      rawTargetMinutes > MAX_TARGET_MINUTES
    ) {
      throw new AppError(
        'INVALID_TARGET',
        `targetMinutes must be an integer between 1 and ${MAX_TARGET_MINUTES}.`,
        400,
        requestId
      );
    }
    targetMinutes = rawTargetMinutes;
  }

  return {
    requestId: requestId.trim(),
    source: source as EventSource,
    ...(note !== undefined && note.length > 0 ? { note } : {}),
    ...(offsetMinutes !== undefined ? { offsetMinutes } : {}),
    ...(location !== undefined ? { location } : {}),
    ...(targetMinutes !== undefined ? { targetMinutes } : {}),
  };
}

/**
 * Lazily materializes a server-side clock-out if the active shift has reached its target_clock_out_utc.
 * Uses an atomic batch guarded by the current work_state version and a deterministic request_id
 * so concurrent requests cannot insert duplicate clock_out events or corrupt state.
 */
export async function materializeAutoClockOutIfDue(
  db: D1Database,
  userId: string = DEFAULT_USER_ID,
  now: Date = new Date()
): Promise<boolean> {
  const stateRow = await db
    .prepare(
      'SELECT user_id, state, active_since_utc, target_clock_out_utc, version, updated_at_utc FROM work_state WHERE user_id = ?'
    )
    .bind(userId)
    .first<WorkStateRow>();

  if (
    !stateRow ||
    stateRow.state !== 'clocked_in' ||
    !stateRow.active_since_utc ||
    !stateRow.target_clock_out_utc
  ) {
    return false;
  }

  const targetDate = truncateToMinute(stateRow.target_clock_out_utc);
  const targetMs = targetDate.getTime();
  if (!Number.isFinite(targetMs) || now.getTime() < targetMs) {
    return false;
  }

  const activeStartMs = truncateToMinute(stateRow.active_since_utc).getTime();
  const effectiveClockOutIso = new Date(
    Number.isFinite(activeStartMs) ? Math.max(activeStartMs, targetMs) : targetMs
  ).toISOString();
  const nowIso = now.toISOString();

  const latestEventRow = await db
    .prepare(
      "SELECT id, event_type, device_id, source, location FROM events WHERE user_id = ? AND event_type = 'clock_in' ORDER BY occurred_at_utc DESC, created_at_utc DESC, rowid DESC LIMIT 1"
    )
    .bind(userId)
    .first<Pick<EventRow, 'id' | 'event_type' | 'device_id' | 'source' | 'location'>>();

  const clockInEvent = latestEventRow;

  const eventId = crypto.randomUUID();
  const autoRequestId = `auto_stop_${clockInEvent?.id ?? stateRow.active_since_utc}_v${stateRow.version}`;
  const source: EventSource = clockInEvent?.source ?? 'flutter_app';
  const deviceId = clockInEvent?.device_id ?? null;
  const location: WorkLocation = clockInEvent?.location ?? 'remote';
  const nextVersion = stateRow.version + 1;

  try {
    const results = await db.batch([
      db
        .prepare(
          `INSERT INTO events (id, request_id, user_id, device_id, event_type, source, occurred_at_utc, created_at_utc, reason, note, location)
           SELECT ?, ?, ?, ?, 'clock_out', ?, ?, ?, 'Auto-stopped at target', NULL, ?
           WHERE EXISTS (
             SELECT 1 FROM work_state
             WHERE user_id = ? AND state = 'clocked_in' AND version = ? AND target_clock_out_utc = ?
           )`
        )
        .bind(
          eventId,
          autoRequestId,
          userId,
          deviceId,
          source,
          effectiveClockOutIso,
          nowIso,
          location,
          userId,
          stateRow.version,
          stateRow.target_clock_out_utc
        ),
      db
        .prepare(
          `UPDATE work_state
           SET state = 'clocked_out',
               active_since_utc = NULL,
               target_clock_out_utc = NULL,
               version = ?,
               updated_at_utc = ?
           WHERE user_id = ? AND state = 'clocked_in' AND version = ? AND target_clock_out_utc = ?`
        )
        .bind(
          nextVersion,
          nowIso,
          userId,
          stateRow.version,
          stateRow.target_clock_out_utc
        ),
    ]);

    return (results[0]?.meta?.changes ?? 0) > 0;
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    if (message.includes('UNIQUE')) {
      return false;
    }
    throw err;
  }
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
      'SELECT user_id, state, active_since_utc, target_clock_out_utc, version, updated_at_utc FROM work_state WHERE user_id = ?'
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
      targetClockOutUtc: stateRow?.target_clock_out_utc ?? null,
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

  const offsetMs = (req.offsetMinutes ?? 0) * 60 * 1000;
  const effectiveTime = truncateToMinute(new Date(now.getTime() + offsetMs));
  const effectiveTimeIso = effectiveTime.toISOString();

  let targetClockOutUtc: string | null = null;
  if (req.targetMinutes !== undefined) {
    const targetDate = new Date(effectiveTime.getTime() + req.targetMinutes * 60_000);
    if (targetDate.getTime() <= truncateToMinute(now).getTime()) {
      throw new AppError(
        'INVALID_TARGET',
        'Target clock-out time must be at least 1 minute in the future.',
        400,
        requestId
      );
    }
    targetClockOutUtc = targetDate.toISOString();
  }

  const { todaySeconds, monthSeconds } = await calculateDurations(
    db,
    DEFAULT_USER_ID,
    'clocked_in',
    effectiveTimeIso,
    now
  );

  const response: CommandResponse = {
    state: 'clocked_in',
    changed: true,
    activeSince: effectiveTimeIso,
    targetClockOutUtc,
    serverTime: nowIso,
    todaySeconds,
    monthSeconds,
    latestEvent: {
      id: eventId,
      eventType: 'clock_in',
      occurredAtUtc: effectiveTimeIso,
      createdAtUtc: nowIso,
    },
  };

  const responseJson = JSON.stringify(response);

  // Execute atomic batch guarded by optimistic work_state version check
  const batchResults = await db.batch(
    stateRow !== null
      ? [
          db
            .prepare(
              `INSERT INTO events (id, request_id, user_id, device_id, event_type, source, occurred_at_utc, created_at_utc, note, location)
               SELECT ?, ?, ?, ?, 'clock_in', ?, ?, ?, ?, ?
               WHERE EXISTS (
                 SELECT 1 FROM work_state WHERE user_id = ? AND state = 'clocked_out' AND version = ?
               )`
            )
            .bind(
              eventId,
              requestId,
              DEFAULT_USER_ID,
              deviceId,
              source,
              effectiveTimeIso,
              nowIso,
              req.note ?? null,
              req.location ?? 'remote',
              DEFAULT_USER_ID,
              stateRow.version
            ),
          db
            .prepare(
              `UPDATE work_state
               SET state = 'clocked_in',
                   active_since_utc = ?,
                   target_clock_out_utc = ?,
                   version = ?,
                   updated_at_utc = ?
               WHERE user_id = ? AND state = 'clocked_out' AND version = ?`
            )
            .bind(
              effectiveTimeIso,
              targetClockOutUtc,
              nextVersion,
              nowIso,
              DEFAULT_USER_ID,
              stateRow.version
            ),
          db
            .prepare(
              `INSERT INTO processed_requests (request_id, user_id, operation, response_json, created_at_utc)
               SELECT ?, ?, ?, ?, ?
               WHERE EXISTS (SELECT 1 FROM events WHERE id = ?)`
            )
            .bind(requestId, DEFAULT_USER_ID, 'clock_in', responseJson, nowIso, eventId),
        ]
      : [
          db
            .prepare(
              `INSERT INTO events (id, request_id, user_id, device_id, event_type, source, occurred_at_utc, created_at_utc, note, location)
               SELECT ?, ?, ?, ?, 'clock_in', ?, ?, ?, ?, ?
               WHERE NOT EXISTS (SELECT 1 FROM work_state WHERE user_id = ?)`
            )
            .bind(
              eventId,
              requestId,
              DEFAULT_USER_ID,
              deviceId,
              source,
              effectiveTimeIso,
              nowIso,
              req.note ?? null,
              req.location ?? 'remote',
              DEFAULT_USER_ID
            ),
          db
            .prepare(
              `INSERT INTO work_state (user_id, state, active_since_utc, target_clock_out_utc, version, updated_at_utc)
               VALUES (?, 'clocked_in', ?, ?, ?, ?)
               ON CONFLICT(user_id) DO NOTHING`
            )
            .bind(DEFAULT_USER_ID, effectiveTimeIso, targetClockOutUtc, nextVersion, nowIso),
          db
            .prepare(
              `INSERT INTO processed_requests (request_id, user_id, operation, response_json, created_at_utc)
               SELECT ?, ?, ?, ?, ?
               WHERE EXISTS (SELECT 1 FROM events WHERE id = ?)`
            )
            .bind(requestId, DEFAULT_USER_ID, 'clock_in', responseJson, nowIso, eventId),
        ]
  );

  if ((batchResults[0]?.meta?.changes ?? 0) === 0 || (batchResults[1]?.meta?.changes ?? 0) === 0) {
    const racedCached = await db
      .prepare('SELECT response_json FROM processed_requests WHERE request_id = ?')
      .bind(requestId)
      .first<{ response_json: string }>();
    if (racedCached) {
      return JSON.parse(racedCached.response_json) as CommandResponse;
    }
    throw new AppError(
      'STATE_CONFLICT',
      'Work state changed concurrently while processing clock-in. Please retry.',
      409,
      requestId
    );
  }

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

    const latestRow = await db
      .prepare(
        'SELECT id, event_type, occurred_at_utc, created_at_utc FROM events WHERE user_id = ? ORDER BY occurred_at_utc DESC, created_at_utc DESC, rowid DESC LIMIT 1'
      )
      .bind(DEFAULT_USER_ID)
      .first<Pick<EventRow, 'id' | 'event_type' | 'occurred_at_utc' | 'created_at_utc'>>();

    const response: CommandResponse = {
      state: 'clocked_out',
      changed: false,
      activeSince: null,
      targetClockOutUtc: null,
      serverTime: nowIso,
      todaySeconds,
      monthSeconds,
      latestEvent: latestRow
        ? {
            id: latestRow.id,
            eventType: latestRow.event_type,
            occurredAtUtc: latestRow.occurred_at_utc,
            createdAtUtc: latestRow.created_at_utc,
          }
        : undefined,
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
  const offsetMs = (req.offsetMinutes ?? 0) * 60 * 1000;
  let effectiveTime = truncateToMinute(new Date(now.getTime() + offsetMs));
  const activeSince = stateRow?.active_since_utc ?? nowIso;
  const activeStartDate = truncateToMinute(activeSince);

  if (effectiveTime.getTime() < activeStartDate.getTime()) {
    effectiveTime = activeStartDate;
  }
  const effectiveTimeIso = effectiveTime.toISOString();

  const completedShiftSeconds = Math.max(
    0,
    Math.floor((effectiveTime.getTime() - activeStartDate.getTime()) / 1000)
  );

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
    targetClockOutUtc: null,
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
      occurredAtUtc: effectiveTimeIso,
      createdAtUtc: nowIso,
    },
  };

  const responseJson = JSON.stringify(response);

  const expectedVersion = stateRow?.version ?? 0;

  // Execute atomic batch guarded by optimistic work_state version check
  const batchResults = await db.batch([
    db
      .prepare(
        `INSERT INTO events (id, request_id, user_id, device_id, event_type, source, occurred_at_utc, created_at_utc, note, location)
         SELECT ?, ?, ?, ?, 'clock_out', ?, ?, ?, ?, ?
         WHERE EXISTS (
           SELECT 1 FROM work_state WHERE user_id = ? AND state = 'clocked_in' AND version = ?
         )`
      )
      .bind(
        eventId,
        requestId,
        DEFAULT_USER_ID,
        deviceId,
        source,
        effectiveTimeIso,
        nowIso,
        req.note ?? null,
        req.location ?? 'remote',
        DEFAULT_USER_ID,
        expectedVersion
      ),
    db
      .prepare(
        `UPDATE work_state
         SET state = 'clocked_out',
             active_since_utc = NULL,
             target_clock_out_utc = NULL,
             version = ?,
             updated_at_utc = ?
         WHERE user_id = ? AND state = 'clocked_in' AND version = ?`
      )
      .bind(nextVersion, nowIso, DEFAULT_USER_ID, expectedVersion),
    db
      .prepare(
        `INSERT INTO processed_requests (request_id, user_id, operation, response_json, created_at_utc)
         SELECT ?, ?, ?, ?, ?
         WHERE EXISTS (SELECT 1 FROM events WHERE id = ?)`
      )
      .bind(requestId, DEFAULT_USER_ID, 'clock_out', responseJson, nowIso, eventId),
  ]);

  if ((batchResults[0]?.meta?.changes ?? 0) === 0 || (batchResults[1]?.meta?.changes ?? 0) === 0) {
    const racedCached = await db
      .prepare('SELECT response_json FROM processed_requests WHERE request_id = ?')
      .bind(requestId)
      .first<{ response_json: string }>();
    if (racedCached) {
      return JSON.parse(racedCached.response_json) as CommandResponse;
    }
    throw new AppError(
      'STATE_CONFLICT',
      'Work state changed concurrently while processing clock-out. Please retry.',
      409,
      requestId
    );
  }

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
      'SELECT id, event_type, occurred_at_utc, created_at_utc FROM events WHERE user_id = ? ORDER BY occurred_at_utc DESC, created_at_utc DESC, rowid DESC LIMIT 1'
    )
    .bind(DEFAULT_USER_ID)
    .first<Pick<EventRow, 'id' | 'event_type' | 'occurred_at_utc' | 'created_at_utc'>>();

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

  // 3. Grace period check: 5 minutes (300,000 ms) based on transaction creation timestamp
  const creationTimeMs = new Date(latestEvent.created_at_utc ?? latestEvent.occurred_at_utc).getTime();
  const nowMs = now.getTime();
  const UNDO_WINDOW_MS = 5 * 60 * 1000;
  if (nowMs - creationTimeMs > UNDO_WINDOW_MS) {
    throw new AppError('UNDO_WINDOW_EXPIRED', 'The 5-minute undo window has expired.', 400, requestId);
  }

  // 4. Query preceding event to determine restored state
  const prevEvent = await db
    .prepare(
      'SELECT id, event_type, occurred_at_utc FROM events WHERE user_id = ? AND id != ? ORDER BY occurred_at_utc DESC, created_at_utc DESC, rowid DESC LIMIT 1'
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

  // 6. Calculate restored durations BEFORE database mutations, excluding the event to be undone
  const { todaySeconds, monthSeconds } = await calculateDurations(
    db,
    DEFAULT_USER_ID,
    restoredState,
    restoredActiveSince,
    now,
    eventId
  );

  const response: UndoResponse = {
    success: true,
    undoneEventId: eventId,
    restoredState,
    activeSince: restoredActiveSince,
    targetClockOutUtc: null,
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

  // 7. Execute all database mutations atomically in a single version-guarded batch
  const batchResults = await db.batch(
    stateRow !== null
      ? [
          db
            .prepare(
              `DELETE FROM events
               WHERE id = ?
                 AND user_id = ?
                 AND EXISTS (
                   SELECT 1 FROM work_state WHERE user_id = ? AND version = ?
                 )
                 AND NOT EXISTS (
                   SELECT 1 FROM events e2
                   WHERE e2.user_id = ?
                     AND e2.id != ?
                     AND (
                       e2.occurred_at_utc > ?
                       OR (e2.occurred_at_utc = ? AND e2.created_at_utc > ?)
                     )
                 )`
            )
            .bind(
              eventId,
              DEFAULT_USER_ID,
              DEFAULT_USER_ID,
              stateRow.version,
              DEFAULT_USER_ID,
              eventId,
              latestEvent.occurred_at_utc,
              latestEvent.occurred_at_utc,
              latestEvent.created_at_utc
            ),
          db
            .prepare(
              `UPDATE work_state
               SET state = ?,
                   active_since_utc = ?,
                   target_clock_out_utc = NULL,
                   version = ?,
                   updated_at_utc = ?
               WHERE user_id = ?
                 AND version = ?
                 AND NOT EXISTS (SELECT 1 FROM events WHERE id = ?)`
            )
            .bind(
              restoredState,
              restoredActiveSince,
              nextVersion,
              nowIso,
              DEFAULT_USER_ID,
              stateRow.version,
              eventId
            ),
          db
            .prepare(
              `INSERT INTO processed_requests (request_id, user_id, operation, response_json, created_at_utc)
               SELECT ?, ?, ?, ?, ?
               WHERE NOT EXISTS (SELECT 1 FROM events WHERE id = ?)
                 AND EXISTS (
                   SELECT 1 FROM work_state WHERE user_id = ? AND version = ? AND updated_at_utc = ?
                 )
                 AND NOT EXISTS (
                   SELECT 1 FROM processed_requests
                   WHERE user_id = ? AND operation = 'undo' AND json_extract(response_json, '$.undoneEventId') = ?
                 )`
            )
            .bind(
              requestId,
              DEFAULT_USER_ID,
              'undo',
              responseJson,
              nowIso,
              eventId,
              DEFAULT_USER_ID,
              nextVersion,
              nowIso,
              DEFAULT_USER_ID,
              eventId
            ),
        ]
      : [
          db
            .prepare(
              `DELETE FROM events
               WHERE id = ?
                 AND user_id = ?
                 AND NOT EXISTS (SELECT 1 FROM work_state WHERE user_id = ?)
                 AND NOT EXISTS (
                   SELECT 1 FROM events e2
                   WHERE e2.user_id = ?
                     AND e2.id != ?
                     AND (
                       e2.occurred_at_utc > ?
                       OR (e2.occurred_at_utc = ? AND e2.created_at_utc > ?)
                     )
                 )`
            )
            .bind(
              eventId,
              DEFAULT_USER_ID,
              DEFAULT_USER_ID,
              DEFAULT_USER_ID,
              eventId,
              latestEvent.occurred_at_utc,
              latestEvent.occurred_at_utc,
              latestEvent.created_at_utc
            ),
          db
            .prepare(
              `INSERT INTO work_state (user_id, state, active_since_utc, target_clock_out_utc, version, updated_at_utc)
               SELECT ?, ?, ?, NULL, ?, ?
               WHERE NOT EXISTS (SELECT 1 FROM events WHERE id = ?)
               ON CONFLICT(user_id) DO NOTHING`
            )
            .bind(
              DEFAULT_USER_ID,
              restoredState,
              restoredActiveSince,
              nextVersion,
              nowIso,
              eventId
            ),
          db
            .prepare(
              `INSERT INTO processed_requests (request_id, user_id, operation, response_json, created_at_utc)
               SELECT ?, ?, ?, ?, ?
               WHERE NOT EXISTS (SELECT 1 FROM events WHERE id = ?)
                 AND EXISTS (
                   SELECT 1 FROM work_state WHERE user_id = ? AND version = ? AND updated_at_utc = ?
                 )
                 AND NOT EXISTS (
                   SELECT 1 FROM processed_requests
                   WHERE user_id = ? AND operation = 'undo' AND json_extract(response_json, '$.undoneEventId') = ?
                 )`
            )
            .bind(
              requestId,
              DEFAULT_USER_ID,
              'undo',
              responseJson,
              nowIso,
              eventId,
              DEFAULT_USER_ID,
              nextVersion,
              nowIso,
              DEFAULT_USER_ID,
              eventId
            ),
        ]
  );

  if ((batchResults[0]?.meta?.changes ?? 0) === 0 || (batchResults[1]?.meta?.changes ?? 0) === 0) {
    const racedCached = await db
      .prepare('SELECT response_json FROM processed_requests WHERE request_id = ?')
      .bind(requestId)
      .first<{ response_json: string }>();
    if (racedCached) {
      return JSON.parse(racedCached.response_json) as UndoResponse;
    }
    throw new AppError(
      'EVENT_MISMATCH',
      'Work state or latest event changed concurrently while processing undo. Please retry.',
      409,
      requestId
    );
  }

  return response;
}

export function validateUpdateTargetRequest(body: unknown): UpdateTargetRequestBody {
  if (!body || typeof body !== 'object') {
    throw new AppError('VALIDATION_ERROR', 'Request body must be a JSON object.', 400);
  }

  const record = body as Record<string, unknown>;
  const hasDelta = record.deltaMinutes !== undefined;
  const hasTarget = record.targetMinutes !== undefined;

  if (hasDelta === hasTarget) {
    throw new AppError(
      'VALIDATION_ERROR',
      'Specify either deltaMinutes or targetMinutes (not both or neither).',
      400
    );
  }

  if (hasDelta) {
    const delta = record.deltaMinutes;
    if (
      typeof delta !== 'number' ||
      !Number.isInteger(delta) ||
      delta === 0 ||
      delta < -MAX_TARGET_MINUTES ||
      delta > MAX_TARGET_MINUTES
    ) {
      throw new AppError(
        'INVALID_TARGET',
        `deltaMinutes must be a non-zero integer between -${MAX_TARGET_MINUTES} and ${MAX_TARGET_MINUTES}.`,
        400
      );
    }
    return { deltaMinutes: delta };
  }

  const target = record.targetMinutes;
  if (target === null) {
    return { targetMinutes: null };
  }

  if (
    typeof target !== 'number' ||
    !Number.isInteger(target) ||
    target < 1 ||
    target > MAX_TARGET_MINUTES
  ) {
    throw new AppError(
      'INVALID_TARGET',
      `targetMinutes must be null or an integer between 1 and ${MAX_TARGET_MINUTES}.`,
      400
    );
  }

  return { targetMinutes: target };
}

export async function handleUpdateTarget(
  db: D1Database,
  req: UpdateTargetRequestBody,
  now: Date = new Date()
): Promise<StatusResponse> {
  const stateRow = await db
    .prepare(
      'SELECT user_id, state, active_since_utc, target_clock_out_utc, version, updated_at_utc FROM work_state WHERE user_id = ?'
    )
    .bind(DEFAULT_USER_ID)
    .first<WorkStateRow>();

  if (!stateRow || stateRow.state !== 'clocked_in' || !stateRow.active_since_utc) {
    throw new AppError(
      'NOT_CLOCKED_IN',
      'Cannot update shift target while clocked out.',
      409
    );
  }

  const activeStartMs = truncateToMinute(stateRow.active_since_utc).getTime();
  const nowMinuteMs = truncateToMinute(now).getTime();
  const minTargetMs = Math.max(nowMinuteMs + 60_000, activeStartMs + 60_000);
  const maxTargetMs = activeStartMs + MAX_TARGET_MINUTES * 60_000;

  let nextTargetUtc: string | null;

  if ('deltaMinutes' in req) {
    if (!stateRow.target_clock_out_utc) {
      throw new AppError(
        'NO_ACTIVE_TARGET',
        'No shift target is currently set.',
        400
      );
    }

    if (minTargetMs > maxTargetMs) {
      throw new AppError(
        'INVALID_TARGET',
        'Shift already meets or exceeds the 24-hour target limit.',
        400
      );
    }

    const currentTargetMs = truncateToMinute(stateRow.target_clock_out_utc).getTime();
    const proposedMs = currentTargetMs + req.deltaMinutes * 60_000;

    if (req.deltaMinutes < 0) {
      nextTargetUtc = new Date(Math.max(proposedMs, minTargetMs)).toISOString();
    } else {
      if (proposedMs > maxTargetMs) {
        throw new AppError(
          'INVALID_TARGET',
          'Target duration cannot exceed 24 hours.',
          400
        );
      }
      nextTargetUtc = new Date(Math.max(proposedMs, minTargetMs)).toISOString();
    }
  } else if (req.targetMinutes === null) {
    nextTargetUtc = null;
  } else {
    const proposedMs = activeStartMs + req.targetMinutes * 60_000;
    if (proposedMs < minTargetMs) {
      throw new AppError(
        'INVALID_TARGET',
        'Target clock-out time must be at least 1 minute in the future.',
        400
      );
    }
    if (proposedMs > maxTargetMs) {
      throw new AppError(
        'INVALID_TARGET',
        'Target duration cannot exceed 24 hours.',
        400
      );
    }
    nextTargetUtc = new Date(proposedMs).toISOString();
  }

  const nextVersion = stateRow.version + 1;
  const nowIso = now.toISOString();

  const updateRes = await db
    .prepare(
      `UPDATE work_state
       SET target_clock_out_utc = ?,
           version = ?,
           updated_at_utc = ?
       WHERE user_id = ? AND state = 'clocked_in' AND version = ?`
    )
    .bind(nextTargetUtc, nextVersion, nowIso, DEFAULT_USER_ID, stateRow.version)
    .run();

  if ((updateRes.meta?.changes ?? 0) === 0) {
    throw new AppError(
      'STATE_CONFLICT',
      'Shift state changed concurrently; please retry.',
      409
    );
  }

  return getStatus(db, DEFAULT_USER_ID, now);
}
