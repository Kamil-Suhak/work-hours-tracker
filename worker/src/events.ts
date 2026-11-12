import type { D1Database } from '@cloudflare/workers-types';
import type {
  EventRow,
  UpdateNoteRequestBody,
  UpdateNoteResponse,
} from './types';
import { AppError } from './errors';

const MAX_QUERY_RANGE_DAYS = 93;

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
       ORDER BY occurred_at_utc ASC, created_at_utc ASC, rowid ASC`
    )
    .bind(userId, fromDate.toISOString(), toDate.toISOString())
    .all<EventRow>();

  return results ?? [];
}

export function validateUpdateNoteRequest(body: unknown): UpdateNoteRequestBody {
  if (!body || typeof body !== 'object') {
    throw new AppError('VALIDATION_ERROR', 'Request body must be a JSON object.', 400);
  }

  const { note } = body as Record<string, unknown>;

  if (note === null || note === undefined) {
    return { note: null };
  }

  if (typeof note !== 'string') {
    throw new AppError('VALIDATION_ERROR', 'note must be a string or null.', 400);
  }

  const trimmed = note.trim();
  if (trimmed.length > 4000) {
    throw new AppError('NOTE_TOO_LONG', 'Note must not exceed 4,000 characters', 400);
  }

  return { note: trimmed.length > 0 ? trimmed : null };
}

export async function handleUpdateEventNote(
  db: D1Database,
  userId: string,
  eventId: string,
  note: string | null
): Promise<UpdateNoteResponse> {
  const event = await db
    .prepare('SELECT id, event_type FROM events WHERE id = ? AND user_id = ?')
    .bind(eventId, userId)
    .first<{ id: string; event_type: string }>();

  if (!event) {
    throw new AppError('EVENT_NOT_FOUND', `Event with ID ${eventId} was not found.`, 404);
  }

  await db
    .prepare('UPDATE events SET note = ? WHERE id = ? AND user_id = ?')
    .bind(note, eventId, userId)
    .run();

  return {
    success: true,
    id: eventId,
    note,
  };
}
