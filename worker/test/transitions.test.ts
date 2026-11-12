import { describe, it, expect, vi } from 'vitest';
import type { D1Database } from '@cloudflare/workers-types';
import {
  validateClockRequest,
  validateUpdateTargetRequest,
  handleClockIn,
  handleClockOut,
  handleUndo,
  materializeAutoClockOutIfDue,
} from '../src/clock';
import { AppError } from '../src/errors';
import { pairShifts, getWarsawDateComponents, formatDuration, truncateToMinute } from '../src/status';
import type { EventRow } from '../src/types';
import { MockD1Database } from './mock-d1';

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

    // offsetMinutes validation
    expect(validateClockRequest({
      requestId: 'req-offset-1',
      source: 'flutter_app',
      offsetMinutes: -5,
    }).offsetMinutes).toBe(-5);

    expect(validateClockRequest({
      requestId: 'req-offset-2',
      source: 'flutter_app',
      offsetMinutes: 5,
    }).offsetMinutes).toBe(5);

    expect(() => validateClockRequest({
      requestId: 'req-offset-3',
      source: 'flutter_app',
      offsetMinutes: 121,
    })).toThrowError(/between -120 and 120/);

    expect(() => validateClockRequest({
      requestId: 'req-offset-4',
      source: 'flutter_app',
      offsetMinutes: -121,
    })).toThrowError(/between -120 and 120/);

    expect(() => validateClockRequest({
      requestId: 'req-offset-5',
      source: 'flutter_app',
      offsetMinutes: 4.5,
    })).toThrowError(/between -120 and 120/);

    // location validation
    expect(validateClockRequest({
      requestId: 'req-loc-1',
      source: 'flutter_app',
      location: 'remote',
    }).location).toBe('remote');

    expect(validateClockRequest({
      requestId: 'req-loc-2',
      source: 'flutter_app',
      location: 'in-office',
    }).location).toBe('in-office');

    expect(() => validateClockRequest({
      requestId: 'req-loc-3',
      source: 'flutter_app',
      location: 'hybrid',
    })).toThrowError(/location must be one of/);
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

  it('ignores seconds and milliseconds so 17:00:45 to 21:00:12 is exactly 4h', () => {
    expect(truncateToMinute('2026-10-03T17:00:45.987Z').toISOString()).toBe('2026-10-03T17:00:00.000Z');

    const events: EventRow[] = [
      {
        id: '1',
        request_id: 'r1',
        user_id: 'default-user',
        device_id: 'd1',
        event_type: 'clock_in',
        source: 'flutter_app',
        occurred_at_utc: '2026-10-03T17:00:45.123Z',
        created_at_utc: '2026-10-03T17:00:45.123Z',
        reason: null,
      },
      {
        id: '2',
        request_id: 'r2',
        user_id: 'default-user',
        device_id: 'd1',
        event_type: 'clock_out',
        source: 'flutter_app',
        occurred_at_utc: '2026-10-03T21:00:12.456Z',
        created_at_utc: '2026-10-03T21:00:12.456Z',
        reason: null,
      },
    ];

    const shifts = pairShifts(events);
    expect(shifts).toHaveLength(1);
    expect(shifts[0].durationSeconds).toBe(4 * 3600);
    expect(formatDuration(shifts[0].durationSeconds)).toBe('4h 0m');
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

  it('validates targetMinutes on clock requests', () => {
    expect(
      validateClockRequest({
        requestId: 'req-target-valid',
        source: 'flutter_app',
        targetMinutes: 120,
      }).targetMinutes
    ).toBe(120);

    expect(
      validateClockRequest({
        requestId: 'req-target-null',
        source: 'flutter_app',
        targetMinutes: null,
      }).targetMinutes
    ).toBeUndefined();

    expect(() =>
      validateClockRequest({
        requestId: 'req-target-zero',
        source: 'flutter_app',
        targetMinutes: 0,
      })
    ).toThrowError(/targetMinutes/);

    expect(() =>
      validateClockRequest({
        requestId: 'req-target-over-24h',
        source: 'flutter_app',
        targetMinutes: 1441,
      })
    ).toThrowError(/targetMinutes/);
  });

  it('validates PATCH shift target payloads strictly', () => {
    expect(() => validateUpdateTargetRequest(null)).toThrowError(/JSON object/);
    expect(() => validateUpdateTargetRequest({})).toThrowError(/deltaMinutes or targetMinutes/);
    expect(() =>
      validateUpdateTargetRequest({ deltaMinutes: 10, targetMinutes: 120 })
    ).toThrowError(/deltaMinutes or targetMinutes/);
    expect(() => validateUpdateTargetRequest({ deltaMinutes: 0 })).toThrowError(/non-zero/);
    expect(() => validateUpdateTargetRequest({ deltaMinutes: 1441 })).toThrowError(/deltaMinutes/);
    expect(() => validateUpdateTargetRequest({ targetMinutes: 0 })).toThrowError(/targetMinutes/);
    expect(() => validateUpdateTargetRequest({ targetMinutes: 1441 })).toThrowError(/targetMinutes/);

    expect(validateUpdateTargetRequest({ deltaMinutes: -10 })).toEqual({ deltaMinutes: -10 });
    expect(validateUpdateTargetRequest({ targetMinutes: 180 })).toEqual({ targetMinutes: 180 });
    expect(validateUpdateTargetRequest({ targetMinutes: null })).toEqual({ targetMinutes: null });
  });
});

describe('Optimistic Version Guards & Concurrency Races', () => {
  it('handleClockIn rejects concurrent state transition with 409 STATE_CONFLICT', async () => {
    vi.useFakeTimers();
    try {
      vi.setSystemTime(new Date('2026-11-10T09:00:00.000Z'));
      const mockDb = new MockD1Database();
      mockDb.workState.set('default-user', {
        user_id: 'default-user',
        state: 'clocked_out',
        active_since_utc: null,
        target_clock_out_utc: null,
        version: 1,
        updated_at_utc: '2026-11-10T08:00:00.000Z',
      });

      const originalBatch = mockDb.batch.bind(mockDb);
      mockDb.batch = async (stmts) => {
        // Simulate another request winning the race before our batch commits.
        mockDb.workState.set('default-user', {
          user_id: 'default-user',
          state: 'clocked_in',
          active_since_utc: '2026-11-10T09:00:00.000Z',
          target_clock_out_utc: null,
          version: 2,
          updated_at_utc: '2026-11-10T09:00:00.000Z',
        });
        mockDb.events.push({
          id: 'ev-winner',
          request_id: 'req-winner',
          user_id: 'default-user',
          device_id: 'dev-other',
          event_type: 'clock_in',
          source: 'flutter_app',
          occurred_at_utc: '2026-11-10T09:00:00.000Z',
          created_at_utc: '2026-11-10T09:00:00.000Z',
          reason: null,
          note: null,
          location: 'remote',
        });
        return originalBatch(stmts);
      };

      await expect(
        handleClockIn(mockDb as unknown as D1Database, 'dev-1', {
          requestId: 'req-loser',
          source: 'flutter_app',
        })
      ).rejects.toMatchObject({ status: 409, code: 'STATE_CONFLICT' });

      expect(mockDb.events).toHaveLength(1);
      expect(mockDb.events[0].id).toBe('ev-winner');
      expect(mockDb.processedRequests.has('req-loser')).toBe(false);
    } finally {
      vi.useRealTimers();
    }
  });

  it('handleClockIn rejects concurrent initialization when work_state was empty', async () => {
    vi.useFakeTimers();
    try {
      vi.setSystemTime(new Date('2026-11-10T09:00:00.000Z'));
      const mockDb = new MockD1Database();
      const originalBatch = mockDb.batch.bind(mockDb);
      mockDb.batch = async (stmts) => {
        mockDb.workState.set('default-user', {
          user_id: 'default-user',
          state: 'clocked_in',
          active_since_utc: '2026-11-10T09:00:00.000Z',
          target_clock_out_utc: null,
          version: 1,
          updated_at_utc: '2026-11-10T09:00:00.000Z',
        });
        return originalBatch(stmts);
      };

      await expect(
        handleClockIn(mockDb as unknown as D1Database, 'dev-1', {
          requestId: 'req-init-race',
          source: 'flutter_app',
        })
      ).rejects.toMatchObject({ status: 409, code: 'STATE_CONFLICT' });

      expect(mockDb.events).toHaveLength(0);
      expect(mockDb.processedRequests.has('req-init-race')).toBe(false);
    } finally {
      vi.useRealTimers();
    }
  });

  it('handleClockOut rejects concurrent clock-out with 409 STATE_CONFLICT and returns cached on same-requestId race', async () => {
    vi.useFakeTimers();
    try {
      vi.setSystemTime(new Date('2026-11-10T11:00:00.000Z'));
      const mockDb = new MockD1Database();
      mockDb.workState.set('default-user', {
        user_id: 'default-user',
        state: 'clocked_in',
        active_since_utc: '2026-11-10T09:00:00.000Z',
        target_clock_out_utc: '2026-11-10T11:00:00.000Z',
        version: 2,
        updated_at_utc: '2026-11-10T09:00:00.000Z',
      });

      const originalBatch = mockDb.batch.bind(mockDb);
      mockDb.batch = async (stmts) => {
        // Simulate auto-stop winning right before batch()
        mockDb.workState.set('default-user', {
          user_id: 'default-user',
          state: 'clocked_out',
          active_since_utc: null,
          target_clock_out_utc: null,
          version: 3,
          updated_at_utc: '2026-11-10T11:00:00.000Z',
        });
        return originalBatch(stmts);
      };

      await expect(
        handleClockOut(mockDb as unknown as D1Database, 'dev-1', {
          requestId: 'req-out-race',
          source: 'flutter_app',
        })
      ).rejects.toMatchObject({ status: 409, code: 'STATE_CONFLICT' });

      expect(mockDb.events).toHaveLength(0);
      expect(mockDb.processedRequests.has('req-out-race')).toBe(false);

      // Reset to version 2 and simulate identical requestId winning the race
      mockDb.workState.set('default-user', {
        user_id: 'default-user',
        state: 'clocked_in',
        active_since_utc: '2026-11-10T09:00:00.000Z',
        target_clock_out_utc: '2026-11-10T11:00:00.000Z',
        version: 2,
        updated_at_utc: '2026-11-10T09:00:00.000Z',
      });
      const cachedPayload = {
        state: 'clocked_out',
        changed: true,
        activeSince: null,
        targetClockOutUtc: null,
        serverTime: '2026-11-10T11:00:00.000Z',
        todaySeconds: 7200,
        monthSeconds: 7200,
      };
      mockDb.batch = async (stmts) => {
        mockDb.workState.set('default-user', {
          user_id: 'default-user',
          state: 'clocked_out',
          active_since_utc: null,
          target_clock_out_utc: null,
          version: 3,
          updated_at_utc: '2026-11-10T11:00:00.000Z',
        });
        mockDb.processedRequests.set('req-same-id', {
          request_id: 'req-same-id',
          user_id: 'default-user',
          operation: 'clock_out',
          response_json: JSON.stringify(cachedPayload),
          created_at_utc: '2026-11-10T11:00:00.000Z',
        });
        return originalBatch(stmts);
      };

      const res = await handleClockOut(mockDb as unknown as D1Database, 'dev-1', {
        requestId: 'req-same-id',
        source: 'flutter_app',
      });
      expect(res.changed).toBe(true);
      expect(res.todaySeconds).toBe(7200);
    } finally {
      vi.useRealTimers();
    }
  });

  it('handleUndo rejects concurrent mutation at identical millisecond without polluting processed_requests', async () => {
    vi.useFakeTimers();
    try {
      vi.setSystemTime(new Date('2026-11-10T09:02:00.000Z'));
      const mockDb = new MockD1Database();
      mockDb.workState.set('default-user', {
        user_id: 'default-user',
        state: 'clocked_in',
        active_since_utc: '2026-11-10T09:00:00.000Z',
        target_clock_out_utc: null,
        version: 1,
        updated_at_utc: '2026-11-10T09:00:00.000Z',
      });
      mockDb.events.push({
        id: 'ev-undo-target',
        request_id: 'req-in-1',
        user_id: 'default-user',
        device_id: 'dev-1',
        event_type: 'clock_in',
        source: 'flutter_app',
        occurred_at_utc: '2026-11-10T09:00:00.000Z',
        created_at_utc: '2026-11-10T09:00:00.000Z',
        reason: null,
        note: null,
        location: 'remote',
      });

      const originalBatch = mockDb.batch.bind(mockDb);
      mockDb.batch = async (stmts) => {
        // Concurrent undo deleted the event at the exact same millisecond.
        mockDb.events = [];
        mockDb.workState.set('default-user', {
          user_id: 'default-user',
          state: 'clocked_out',
          active_since_utc: null,
          target_clock_out_utc: null,
          version: 2,
          updated_at_utc: '2026-11-10T09:02:00.000Z',
        });
        mockDb.processedRequests.set('req-undo-winner', {
          request_id: 'req-undo-winner',
          user_id: 'default-user',
          operation: 'undo',
          response_json: JSON.stringify({ success: true, undoneEventId: 'ev-undo-target' }),
          created_at_utc: '2026-11-10T09:02:00.000Z',
        });
        return originalBatch(stmts);
      };

      await expect(
        handleUndo(mockDb as unknown as D1Database, {
          requestId: 'req-undo-loser',
          eventId: 'ev-undo-target',
        })
      ).rejects.toBeInstanceOf(AppError);

      expect(mockDb.processedRequests.has('req-undo-loser')).toBe(false);
    } finally {
      vi.useRealTimers();
    }
  });

  it('materializeAutoClockOutIfDue reads latest clock_in metadata even when a later clock_out exists', async () => {
    vi.useFakeTimers();
    try {
      vi.setSystemTime(new Date('2026-11-10T11:05:00.000Z'));
      const mockDb = new MockD1Database();
      mockDb.workState.set('default-user', {
        user_id: 'default-user',
        state: 'clocked_in',
        active_since_utc: '2026-11-10T09:00:00.000Z',
        target_clock_out_utc: '2026-11-10T11:00:00.000Z',
        version: 1,
        updated_at_utc: '2026-11-10T09:00:00.000Z',
      });
      mockDb.events.push(
        {
          id: 'ev-in-office',
          request_id: 'req-in-office',
          user_id: 'default-user',
          device_id: 'dev-office',
          event_type: 'clock_in',
          source: 'android_widget',
          occurred_at_utc: '2026-11-10T09:00:00.000Z',
          created_at_utc: '2026-11-10T09:00:00.000Z',
          reason: null,
          note: null,
          location: 'in-office',
        },
        {
          id: 'ev-future-out',
          request_id: 'req-future-out',
          user_id: 'default-user',
          device_id: 'dev-other',
          event_type: 'clock_out',
          source: 'flutter_app',
          occurred_at_utc: '2026-11-10T10:30:00.000Z',
          created_at_utc: '2026-11-10T10:30:00.000Z',
          reason: null,
          note: null,
          location: 'remote',
        }
      );

      const stopped = await materializeAutoClockOutIfDue(
        mockDb as unknown as D1Database,
        'default-user'
      );
      expect(stopped).toBe(true);
      const autoOut = mockDb.events.find((e) => e.reason === 'Auto-stopped at target');
      expect(autoOut).toBeDefined();
      expect(autoOut?.source).toBe('android_widget');
      expect(autoOut?.location).toBe('in-office');
      expect(autoOut?.device_id).toBe('dev-office');
    } finally {
      vi.useRealTimers();
    }
  });
});
