import type { D1Database } from '@cloudflare/workers-types';
import type { EventRow, StatusResponse, WorkState } from './types';

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
  now: Date
): Promise<{ todaySeconds: number; monthSeconds: number }> {
  const { dateString: todayString, monthString: currentMonthString } =
    getWarsawDateComponents(now);

  // Fetch all events for the current month window
  // Query starting slightly before current month boundary to catch UTC/local time offsets
  const startOfMonthUtc = `${currentMonthString}-01T00:00:00.000Z`;

  const { results: rawEvents } = await db
    .prepare(
      `SELECT * FROM events 
       WHERE user_id = ? AND occurred_at_utc >= ? 
       ORDER BY occurred_at_utc ASC, id ASC`
    )
    .bind(userId, startOfMonthUtc)
    .all<EventRow>();

  const events = rawEvents ?? [];
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

  return {
    state: currentState,
    activeSince,
    serverTime: now.toISOString(),
    todaySeconds,
    monthSeconds,
  };
}
