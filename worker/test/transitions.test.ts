import { describe, it, expect } from 'vitest';
import { validateClockRequest } from '../src/clock';
import { pairShifts, getWarsawDateComponents, formatDuration } from '../src/status';
import type { EventRow } from '../src/types';

describe('State Transitions & Duration Rules', () => {
  it('validates clock requests strictly', () => {
    expect(() => validateClockRequest(null)).toThrowError(/JSON object/);
    expect(() => validateClockRequest({})).toThrowError(/requestId/);
    expect(() =>
      validateClockRequest({ requestId: 'req-1', source: 'invalid_source' })
    ).toThrowError(/source must be one of/);

    const valid = validateClockRequest({
      requestId: 'req-1',
      source: 'flutter_app',
    });
    expect(valid.requestId).toBe('req-1');
    expect(valid.source).toBe('flutter_app');
  });

  it('correctly pairs consecutive clock-in and clock-out events', () => {
    const events: EventRow[] = [
      {
        id: '1',
        request_id: 'r1',
        user_id: 'default-user',
        device_id: 'd1',
        event_type: 'clock_in',
        source: 'flutter_app',
        occurred_at_utc: '2026-10-03T08:00:00.000Z',
        created_at_utc: '2026-10-03T08:00:00.000Z',
        reason: null,
      },
      {
        id: '2',
        request_id: 'r2',
        user_id: 'default-user',
        device_id: 'd1',
        event_type: 'clock_out',
        source: 'flutter_app',
        occurred_at_utc: '2026-10-03T16:30:00.000Z',
        created_at_utc: '2026-10-03T16:30:00.000Z',
        reason: null,
      },
    ];

    const shifts = pairShifts(events);
    expect(shifts).toHaveLength(1);
    expect(shifts[0].durationSeconds).toBe(8.5 * 3600);
  });

  it('skips unmatched consecutive clock-in events without failing', () => {
    const events: EventRow[] = [
      {
        id: '1',
        request_id: 'r1',
        user_id: 'default-user',
        device_id: 'd1',
        event_type: 'clock_in',
        source: 'flutter_app',
        occurred_at_utc: '2026-10-03T08:00:00.000Z',
        created_at_utc: '2026-10-03T08:00:00.000Z',
        reason: null,
      },
      {
        id: '2',
        request_id: 'r2',
        user_id: 'default-user',
        device_id: 'd1',
        event_type: 'clock_in', // unclosed prior shift
        source: 'flutter_app',
        occurred_at_utc: '2026-10-03T09:00:00.000Z',
        created_at_utc: '2026-10-03T09:00:00.000Z',
        reason: null,
      },
      {
        id: '3',
        request_id: 'r3',
        user_id: 'default-user',
        device_id: 'd1',
        event_type: 'clock_out',
        source: 'flutter_app',
        occurred_at_utc: '2026-10-03T17:00:00.000Z',
        created_at_utc: '2026-10-03T17:00:00.000Z',
        reason: null,
      },
    ];

    const shifts = pairShifts(events);
    expect(shifts).toHaveLength(1);
    expect(shifts[0].clockIn.id).toBe('2');
    expect(shifts[0].durationSeconds).toBe(8 * 3600);
  });

  it('determines Europe/Warsaw date components accurately', () => {
    // 22:30 UTC on Oct 3 is 00:30 on Oct 4 in Warsaw (CEST, UTC+2)
    const dateUtc = new Date('2026-10-03T22:30:00.000Z');
    const { dateString, monthString } = getWarsawDateComponents(dateUtc);
    expect(dateString).toBe('2026-10-04');
    expect(monthString).toBe('2026-10');
  });

  it('handles Europe/Warsaw daylight-saving transition in late October', () => {
    // Warsaw transitions from UTC+2 (CEST) to UTC+1 (CET) on last Sunday of October
    // October 25, 2026 at 00:30 UTC is 02:30 CEST (summer time)
    const dateSummer = new Date('2026-10-25T00:30:00.000Z');
    const compSummer = getWarsawDateComponents(dateSummer);
    expect(compSummer.dateString).toBe('2026-10-25');

    // October 26, 2026 at 00:30 UTC is 01:30 CET (standard winter time)
    const dateWinter = new Date('2026-10-26T00:30:00.000Z');
    const compWinter = getWarsawDateComponents(dateWinter);
    expect(compWinter.dateString).toBe('2026-10-26');
  });

  it('formats duration integers to Xh Ym representation', () => {
    expect(formatDuration(0)).toBe('0h 0m');
    expect(formatDuration(3600)).toBe('1h 0m');
    expect(formatDuration(86400)).toBe('24h 0m');
    expect(formatDuration(90000)).toBe('25h 0m');
  });
});
