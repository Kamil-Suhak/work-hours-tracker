import type { D1Database } from '@cloudflare/workers-types';
import type { EventRow, EventType, StatusResponse, WorkState } from './types';

const WARSAW_TZ = 'Europe/Warsaw';

export function getWarsawDateComponents(date: Date): {
  dateString: string;
  monthString: string;
} {
  const formatter = new Intl.DateTimeFormat('en-CA', {
    timeZone: WARSAW_TZ,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  });
  const dateString = formatter.format(date); // Format: YYYY-MM-DD
  const monthString = dateString.slice(0, 7); // Format: YYYY-MM
  return { dateString, monthString };
}

export function formatDuration(totalSeconds: number): string {
  if (totalSeconds <= 0) return '0h 0m';
  const hours = Math.floor(totalSeconds / 3600);
  const minutes = Math.floor((totalSeconds % 3600) / 60);
  return `${hours}h ${minutes}m`;
}

/**
 * Converts a wall-clock date and time in Europe/Warsaw into its corresponding UTC Date instant.
 * Handles daylight saving transitions (CET UTC+1 / CEST UTC+2).
 */
export function warsawWallClockToUtc(
  year: number,
  month: number, // 1-12
  day: number,
  hour = 0,
  minute = 0,
  second = 0
): Date {
  const approxUtc = new Date(Date.UTC(year, month - 1, day, hour, minute, second));
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: WARSAW_TZ,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    hour12: false,
  }).formatToParts(approxUtc);

  const getPart = (type: string) => parseInt(parts.find((p) => p.type === type)?.value || '0', 10);
  const warsawYear = getPart('year');
  const warsawMonth = getPart('month');
  const warsawDay = getPart('day');
  let warsawHour = getPart('hour');
  if (warsawHour === 24) warsawHour = 0;
  const warsawMinute = getPart('minute');
  const warsawSecond = getPart('second');

  const warsawAsUtc = Date.UTC(warsawYear, warsawMonth - 1, warsawDay, warsawHour, warsawMinute, warsawSecond);
  const offsetMs = warsawAsUtc - approxUtc.getTime();

  return new Date(approxUtc.getTime() - offsetMs);
}

/**
 * Returns the exact UTC start and end bounds for the previous calendar month in Europe/Warsaw.
 * Uses half-open interval [startIso, endIso).
 */
export function getPreviousWarsawMonthRangeUtc(now: Date = new Date()): {
  startIso: string;
  endIso: string;
  monthString: string;
} {
  const { monthString: currentMonthString } = getWarsawDateComponents(now);
  const currentYear = parseInt(currentMonthString.slice(0, 4), 10);
  const currentMonth = parseInt(currentMonthString.slice(5, 7), 10);

  let prevYear = currentYear;
  let prevMonth = currentMonth - 1;
  if (prevMonth === 0) {
    prevMonth = 12;
    prevYear -= 1;
  }

  const monthString = `${prevYear}-${String(prevMonth).padStart(2, '0')}`;
  const startUtc = warsawWallClockToUtc(prevYear, prevMonth, 1, 0, 0, 0);
  const endUtc = warsawWallClockToUtc(currentYear, currentMonth, 1, 0, 0, 0);

  return {
    startIso: startUtc.toISOString(),
    endIso: endUtc.toISOString(),
    monthString,
  };
}

export function pairShifts(events: EventRow[]): {
  clockIn: EventRow;
  clockOut: EventRow;
  durationSeconds: number;
}[] {
  const shifts: {
    clockIn: EventRow;
    clockOut: EventRow;
    durationSeconds: number;
  }[] = [];

  let pendingClockIn: EventRow | null = null;

  for (const event of events) {
    if (event.event_type === 'clock_in') {
      pendingClockIn = event;
    } else if (event.event_type === 'clock_out' && pendingClockIn) {
      const inTime = new Date(pendingClockIn.occurred_at_utc).getTime();
      const outTime = new Date(event.occurred_at_utc).getTime();
      const durationSeconds = Math.max(0, Math.floor((outTime - inTime) / 1000));
      shifts.push({
        clockIn: pendingClockIn,
        clockOut: event,
        durationSeconds,
      });
      pendingClockIn = null;
    }
  }

  return shifts;
}

export async function calculateDurations(
  db: D1Database,
  userId: string,
  currentState: WorkState,
  activeSinceUtc: string | null,
  now: Date,
  excludeEventId?: string
): Promise<{ todaySeconds: number; monthSeconds: number }> {
  const { dateString: todayString, monthString: currentMonthString } =
    getWarsawDateComponents(now);

  // Fetch events for the current month window
  // Query starts 48 hours prior to UTC 1st to include shifts starting 00:00-02:00 Warsaw time (UTC+1/UTC+2)
  const firstOfMonthUtc = new Date(Date.parse(`${currentMonthString}-01T00:00:00.000Z`));
  const queryStartUtc = new Date(firstOfMonthUtc.getTime() - 48 * 60 * 60 * 1000).toISOString();

  const { results: rawEvents } = await db
    .prepare(
      `SELECT * FROM events 
       WHERE user_id = ? AND occurred_at_utc >= ? 
       ORDER BY occurred_at_utc ASC, id ASC`
    )
    .bind(userId, queryStartUtc)
    .all<EventRow>();

  const allEvents = rawEvents ?? [];
  const events = excludeEventId
    ? allEvents.filter((e) => e.id !== excludeEventId)
    : allEvents;
  const shifts = pairShifts(events);

  let todaySeconds = 0;
  let monthSeconds = 0;

  for (const shift of shifts) {
    const shiftStartDate = new Date(shift.clockIn.occurred_at_utc);
    const { dateString, monthString } = getWarsawDateComponents(shiftStartDate);

    if (monthString === currentMonthString) {
      monthSeconds += shift.durationSeconds;
    }
    if (dateString === todayString) {
      todaySeconds += shift.durationSeconds;
    }
  }

  // If currently clocked in, include the ongoing active shift duration
  if (currentState === 'clocked_in' && activeSinceUtc) {
    const activeStartDate = new Date(activeSinceUtc);
    const activeDuration = Math.max(
      0,
      Math.floor((now.getTime() - activeStartDate.getTime()) / 1000)
    );
    const { dateString, monthString } = getWarsawDateComponents(activeStartDate);

    if (monthString === currentMonthString) {
      monthSeconds += activeDuration;
    }
    if (dateString === todayString) {
      todaySeconds += activeDuration;
    }
  }

  return { todaySeconds, monthSeconds };
}

export async function getStatus(
  db: D1Database,
  userId: string,
  now: Date = new Date()
): Promise<StatusResponse> {
  const stateRow = await db
    .prepare(
      'SELECT user_id, state, active_since_utc, version, updated_at_utc FROM work_state WHERE user_id = ?'
    )
    .bind(userId)
    .first<{
      user_id: string;
      state: WorkState;
      active_since_utc: string | null;
      version: number;
      updated_at_utc: string;
    }>();

  const currentState: WorkState = stateRow?.state ?? 'clocked_out';
  const activeSince = stateRow?.active_since_utc ?? null;

  const { todaySeconds, monthSeconds } = await calculateDurations(
    db,
    userId,
    currentState,
    activeSince,
    now
  );

  const latestEventRow = await db
    .prepare(
      'SELECT id, event_type, occurred_at_utc FROM events WHERE user_id = ? ORDER BY occurred_at_utc DESC, id DESC LIMIT 1'
    )
    .bind(userId)
    .first<{ id: string; event_type: EventType; occurred_at_utc: string }>();

  const latestEvent = latestEventRow
    ? {
        id: latestEventRow.id,
        eventType: latestEventRow.event_type,
        occurredAtUtc: latestEventRow.occurred_at_utc,
      }
    : null;

  return {
    state: currentState,
    activeSince,
    serverTime: now.toISOString(),
    todaySeconds,
    monthSeconds,
    latestEvent,
  };
}
