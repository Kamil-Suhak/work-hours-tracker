import type { D1Database } from '@cloudflare/workers-types';
import type {
  EventRow,
  ManualEventRequestBody,
  ManualEventResponse,
  ProcessedRequestRow,
} from './types';
import { AppError } from './errors';
import { DEFAULT_USER_ID } from './clock';
import { pairShifts, formatDuration } from './status';

const MAX_QUERY_RANGE_DAYS = 93;
const MAX_SHIFT_DURATION_SECONDS = 24 * 60 * 60; // 24 hours

export function validateIsoDate(dateString: string, fieldName: string): Date {
  const date = new Date(dateString);
  if (isNaN(date.getTime()) || !dateString.includes('T')) {
    throw new AppError(
      'VALIDATION_ERROR',
      `${fieldName} must be a valid ISO 8601 date string.`,
      400
    );
  }
  return date;
}

export async function handleGetEvents(
  db: D1Database,
  userId: string,
  url: URL
): Promise<EventRow[]> {
  const fromParam = url.searchParams.get('from');
  const toParam = url.searchParams.get('to');

  if (!fromParam || !toParam) {
    throw new AppError(
      'VALIDATION_ERROR',
      'Both "from" and "to" query parameters are required ISO timestamps.',
      400
    );
  }

  const fromDate = validateIsoDate(fromParam, 'from');
  const toDate = validateIsoDate(toParam, 'to');

  if (toDate.getTime() <= fromDate.getTime()) {
    throw new AppError('INVALID_DATE_RANGE', '"to" must be strictly after "from".', 400);
  }

  const rangeDays = (toDate.getTime() - fromDate.getTime()) / (1000 * 60 * 60 * 24);
  if (rangeDays > MAX_QUERY_RANGE_DAYS) {
    throw new AppError(
      'INVALID_DATE_RANGE',
      `Requested date range exceeds maximum allowed limit of ${MAX_QUERY_RANGE_DAYS} days.`,
      400
    );
  }

  const { results } = await db
    .prepare(
      `SELECT * FROM events
       WHERE user_id = ? AND occurred_at_utc >= ? AND occurred_at_utc <= ?
       ORDER BY occurred_at_utc ASC, id ASC`
    )
    .bind(userId, fromDate.toISOString(), toDate.toISOString())
    .all<EventRow>();

  return results ?? [];
}

export function validateManualEventRequest(body: unknown): ManualEventRequestBody {
  if (!body || typeof body !== 'object') {
    throw new AppError('VALIDATION_ERROR', 'Request body must be a JSON object.', 400);
  }

  const { clockInAt, clockOutAt, reason, requestId } = body as Record<string, unknown>;

  if (typeof requestId !== 'string' || requestId.trim().length === 0) {
    throw new AppError('INVALID_REQUEST_ID', 'requestId must be a non-empty string.', 400);
  }

  if (typeof clockInAt !== 'string' || typeof clockOutAt !== 'string') {
    throw new AppError(
      'VALIDATION_ERROR',
      'clockInAt and clockOutAt must be ISO 8601 strings.',
      400,
      requestId
    );
  }

  if (typeof reason !== 'string' || reason.trim().length === 0) {
    throw new AppError(
      'VALIDATION_ERROR',
      'reason is required and cannot be empty.',
      400,
      requestId
    );
  }

  const inDate = validateIsoDate(clockInAt, 'clockInAt');
  const outDate = validateIsoDate(clockOutAt, 'clockOutAt');

  if (outDate.getTime() <= inDate.getTime()) {
    throw new AppError(
      'VALIDATION_ERROR',
      'clockOutAt must be strictly greater than clockInAt.',
      400,
      requestId
    );
  }

  const durationSeconds = Math.floor((outDate.getTime() - inDate.getTime()) / 1000);
  if (durationSeconds > MAX_SHIFT_DURATION_SECONDS) {
    throw new AppError(
      'INVALID_DURATION',
      `Shift duration (${formatDuration(durationSeconds)}) exceeds the maximum allowed ${formatDuration(MAX_SHIFT_DURATION_SECONDS)}.`,
      400,
      requestId
    );
  }

  return {
    clockInAt: inDate.toISOString(),
    clockOutAt: outDate.toISOString(),
    reason: reason.trim(),
    requestId: requestId.trim(),
  };
}

export async function handleAdminManualEvent(
  db: D1Database,
  req: ManualEventRequestBody,
  now: Date = new Date()
): Promise<ManualEventResponse> {
  const { clockInAt, clockOutAt, reason, requestId } = req;
  const nowIso = now.toISOString();

  // 1. Idempotency check
  const cached = await db
    .prepare('SELECT response_json FROM processed_requests WHERE request_id = ?')
    .bind(requestId)
    .first<Pick<ProcessedRequestRow, 'response_json'>>();

  if (cached) {
    return JSON.parse(cached.response_json) as ManualEventResponse;
  }

  // 2. Check for overlapping shifts
  // Query existing events around the proposed timeframe
  const bufferFrom = new Date(new Date(clockInAt).getTime() - 24 * 60 * 60 * 1000).toISOString();
  const bufferTo = new Date(new Date(clockOutAt).getTime() + 24 * 60 * 60 * 1000).toISOString();

  const { results: existingEvents } = await db
    .prepare(
      `SELECT * FROM events
       WHERE user_id = ? AND occurred_at_utc >= ? AND occurred_at_utc <= ?
       ORDER BY occurred_at_utc ASC, id ASC`
    )
    .bind(DEFAULT_USER_ID, bufferFrom, bufferTo)
    .all<EventRow>();

  const existingShifts = pairShifts(existingEvents ?? []);
  const proposedIn = new Date(clockInAt).getTime();
  const proposedOut = new Date(clockOutAt).getTime();

  for (const shift of existingShifts) {
    const shiftIn = new Date(shift.clockIn.occurred_at_utc).getTime();
    const shiftOut = new Date(shift.clockOut.occurred_at_utc).getTime();
    if (Math.max(proposedIn, shiftIn) < Math.min(proposedOut, shiftOut)) {
      throw new AppError(
        'OVERLAPPING_SHIFT',
        `Proposed shift overlaps with existing shift (${shift.clockIn.occurred_at_utc} to ${shift.clockOut.occurred_at_utc}).`,
        400,
        requestId
      );
    }
  }

  // 3. Insert matched pair in atomic batch
  const clockInId = crypto.randomUUID();
  const clockOutId = crypto.randomUUID();
  const durationSeconds = Math.floor((proposedOut - proposedIn) / 1000);

  const response: ManualEventResponse = {
    success: true,
    clockInEventId: clockInId,
    clockOutEventId: clockOutId,
    clockInAt,
    clockOutAt,
    durationSeconds,
  };

  const responseJson = JSON.stringify(response);

  await db.batch([
    db
      .prepare(
        `INSERT INTO events (id, request_id, user_id, device_id, event_type, source, occurred_at_utc, created_at_utc, reason)
         VALUES (?, ?, ?, NULL, 'clock_in', 'admin_manual', ?, ?, ?)`
      )
      .bind(clockInId, `${requestId}_in`, DEFAULT_USER_ID, clockInAt, nowIso, reason),
    db
      .prepare(
        `INSERT INTO events (id, request_id, user_id, device_id, event_type, source, occurred_at_utc, created_at_utc, reason)
         VALUES (?, ?, ?, NULL, 'clock_out', 'admin_manual', ?, ?, ?)`
      )
      .bind(clockOutId, `${requestId}_out`, DEFAULT_USER_ID, clockOutAt, nowIso, reason),
    db
      .prepare(
        `INSERT INTO processed_requests (request_id, user_id, operation, response_json, created_at_utc)
         VALUES (?, ?, 'admin_manual', ?, ?)`
      )
      .bind(requestId, DEFAULT_USER_ID, responseJson, nowIso),
  ]);

  return response;
}
