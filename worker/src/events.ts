import type { D1Database } from '@cloudflare/workers-types';
import type { EventRow } from './types';
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
