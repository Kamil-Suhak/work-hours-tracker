import { describe, it, expect, beforeEach } from 'vitest';
import worker from '../src/index';
import type { Env } from '../src/types';
import { hashDeviceToken } from '../src/auth';
import { MockD1Database } from './mock-d1';
import type { D1Database } from '@cloudflare/workers-types';

describe('Worker End-to-End Integration Suite', () => {
  let mockDb: MockD1Database;
  let env: Env;
  const validToken = 'test-device-token-12345';
  const adminToken = 'admin-secret-token-67890';
  let deviceTokenHash: string;

  beforeEach(async () => {
    mockDb = new MockD1Database();
    deviceTokenHash = await hashDeviceToken(validToken);

    // Seed enabled device
    mockDb.devices.push({
      id: 'dev-1',
      name: 'Android Phone',
      token_hash: deviceTokenHash,
      enabled: 1,
      created_at_utc: new Date().toISOString(),
    });

    env = {
      DB: mockDb as unknown as D1Database,
      ADMIN_API_TOKEN: adminToken,
      DEVICE_TOKEN_PEPPER: '',
    };
  });

  function createRequest(
    path: string,
    options: {
      method?: string;
      token?: string;
      body?: unknown;
    } = {}
  ): Request {
    const { method = 'GET', token = validToken, body } = options;
    const headers: Record<string, string> = {};
    if (token) {
      headers['Authorization'] = `Bearer ${token}`;
    }
    if (body) {
      headers['Content-Type'] = 'application/json';
    }

    return new Request(`https://work-hours.local${path}`, {
      method,
      headers,
      body: body ? JSON.stringify(body) : undefined,
    });
  }

  describe('Authentication Enforcement', () => {
    it('rejects requests without Authorization header with 401', async () => {
      const req = createRequest('/api/v1/status', { token: '' });
      const res = await worker.fetch(req, env);
      expect(res.status).toBe(401);
      const data = await res.json() as { error: { code: string } };
      expect(data.error.code).toBe('UNAUTHORIZED');
    });

    it('rejects requests with an unknown token with 401', async () => {
      const req = createRequest('/api/v1/status', { token: 'wrong-token' });
      const res = await worker.fetch(req, env);
      expect(res.status).toBe(401);
    });

    it('rejects requests from a disabled device with 403', async () => {
      mockDb.devices[0].enabled = 0;
      const req = createRequest('/api/v1/status');
      const res = await worker.fetch(req, env);
      expect(res.status).toBe(403);
      const data = await res.json() as { error: { code: string } };
      expect(data.error.code).toBe('DEVICE_DISABLED');
    });
  });

  describe('Clock-In, Clock-Out & Idempotency Pipeline', () => {
    it('executes clean clock-in transition from clocked-out', async () => {
      const req = createRequest('/api/v1/clock-in', {
        method: 'POST',
        body: { requestId: 'req-in-1', source: 'flutter_app' },
      });

      const res = await worker.fetch(req, env);
      expect(res.status).toBe(200);

      const data = await res.json() as {
        state: string;
        changed: boolean;
        activeSince: string | null;
      };
      expect(data.state).toBe('clocked_in');
      expect(data.changed).toBe(true);
      expect(data.activeSince).toBeDefined();

      // Verify D1 state
      expect(mockDb.events).toHaveLength(1);
      expect(mockDb.events[0].event_type).toBe('clock_in');
      expect(mockDb.events[0].source).toBe('flutter_app');
      expect(mockDb.workState.get('default-user')?.state).toBe('clocked_in');
    });

    it('returns changed: false when clocking in while already clocked in', async () => {
      // 1. Clock in
      await worker.fetch(
        createRequest('/api/v1/clock-in', {
          method: 'POST',
          body: { requestId: 'req-in-1', source: 'flutter_app' },
        }),
        env
      );

      // 2. Second clock in with new requestId
      const req2 = createRequest('/api/v1/clock-in', {
        method: 'POST',
        body: { requestId: 'req-in-2', source: 'android_widget' },
      });
      const res2 = await worker.fetch(req2, env);
      expect(res2.status).toBe(200);

      const data2 = await res2.json() as { state: string; changed: boolean };
      expect(data2.state).toBe('clocked_in');
      expect(data2.changed).toBe(false);

      // Should not insert a second event
      expect(mockDb.events).toHaveLength(1);
    });

    it('replays cached response when repeating identical requestId (idempotency)', async () => {
      const reqBody = { requestId: 'req-idempotent-1', source: 'flutter_app' };

      // First call
      const res1 = await worker.fetch(
        createRequest('/api/v1/clock-in', { method: 'POST', body: reqBody }),
        env
      );
      const data1 = await res1.json() as { changed: boolean };
      expect(data1.changed).toBe(true);

      // Duplicate call with exact same requestId
      const res2 = await worker.fetch(
        createRequest('/api/v1/clock-in', { method: 'POST', body: reqBody }),
        env
      );
      const data2 = await res2.json() as { changed: boolean };

      expect(data2).toEqual(data1);
      expect(mockDb.events).toHaveLength(1);
    });

    it('executes clean clock-out transition from clocked-in', async () => {
      // Clock in first
      await worker.fetch(
        createRequest('/api/v1/clock-in', {
          method: 'POST',
          body: { requestId: 'req-in-1', source: 'flutter_app' },
        }),
        env
      );

      // Clock out
      const reqOut = createRequest('/api/v1/clock-out', {
        method: 'POST',
        body: { requestId: 'req-out-1', source: 'android_widget' },
      });
      const resOut = await worker.fetch(reqOut, env);
      expect(resOut.status).toBe(200);

      const dataOut = await resOut.json() as {
        state: string;
        changed: boolean;
        activeSince: string | null;
      };
      expect(dataOut.state).toBe('clocked_out');
      expect(dataOut.changed).toBe(true);
      expect(dataOut.activeSince).toBeNull();

      expect(mockDb.events).toHaveLength(2);
      expect(mockDb.events[1].event_type).toBe('clock_out');
      expect(mockDb.workState.get('default-user')?.state).toBe('clocked_out');
    });

    it('returns changed: false when clocking out while already clocked out', async () => {
      const reqOut = createRequest('/api/v1/clock-out', {
        method: 'POST',
        body: { requestId: 'req-out-noop', source: 'flutter_app' },
      });
      const resOut = await worker.fetch(reqOut, env);
      expect(resOut.status).toBe(200);

      const dataOut = await resOut.json() as { state: string; changed: boolean };
      expect(dataOut.state).toBe('clocked_out');
      expect(dataOut.changed).toBe(false);
      expect(mockDb.events).toHaveLength(0);
    });
  });

  describe('Status & Events Queries', () => {
    it('returns authoritative status matching work_state', async () => {
      const res = await worker.fetch(createRequest('/api/v1/status'), env);
      expect(res.status).toBe(200);
      const data = await res.json() as {
        state: string;
        todaySeconds: number;
        monthSeconds: number;
        serverTime: string;
      };
      expect(data.state).toBe('clocked_out');
      expect(data.todaySeconds).toBe(0);
      expect(data.monthSeconds).toBe(0);
      expect(data.serverTime).toBeDefined();
    });

    it('queries events within valid date range', async () => {
      // Seed an event
      mockDb.events.push({
        id: 'ev-1',
        request_id: 'r-seed',
        user_id: 'default-user',
        device_id: 'dev-1',
        event_type: 'clock_in',
        source: 'flutter_app',
        occurred_at_utc: '2026-10-02T10:00:00.000Z',
        created_at_utc: '2026-10-02T10:00:00.000Z',
        reason: null,
      });

      const res = await worker.fetch(
        createRequest('/api/v1/events?from=2026-10-01T00:00:00Z&to=2026-10-05T00:00:00Z'),
        env
      );
      expect(res.status).toBe(200);
      const list = await res.json() as unknown[];
      expect(list).toHaveLength(1);
    });

    it('rejects events query when range exceeds 93 days', async () => {
      const res = await worker.fetch(
        createRequest('/api/v1/events?from=2026-01-01T00:00:00Z&to=2026-06-01T00:00:00Z'),
        env
      );
      expect(res.status).toBe(400);
      const data = await res.json() as { error: { code: string } };
      expect(data.error.code).toBe('INVALID_DATE_RANGE');
    });
  });

  describe('Admin Manual Shift Backfill', () => {
    it('rejects manual backfill with device token (requires admin token)', async () => {
      const res = await worker.fetch(
        createRequest('/api/v1/admin/events/manual', {
          method: 'POST',
          token: validToken, // device token, not admin token
          body: {
            clockInAt: '2026-10-01T08:00:00Z',
            clockOutAt: '2026-10-01T16:00:00Z',
            reason: 'Test backfill',
            requestId: 'req-backfill-1',
          },
        }),
        env
      );
      expect(res.status).toBe(401);
    });

    it('inserts matched shift pair when authenticated with admin token', async () => {
      const res = await worker.fetch(
        createRequest('/api/v1/admin/events/manual', {
          method: 'POST',
          token: adminToken,
          body: {
            clockInAt: '2026-10-01T08:00:00Z',
            clockOutAt: '2026-10-01T16:00:00Z',
            reason: 'Backfill worked day',
            requestId: 'req-admin-1',
          },
        }),
        env
      );
      expect(res.status).toBe(200);
      const data = await res.json() as { success: boolean; durationSeconds: number };
      expect(data.success).toBe(true);
      expect(data.durationSeconds).toBe(8 * 3600);

      // Verify pair created in D1
      expect(mockDb.events).toHaveLength(2);
      expect(mockDb.events[0].source).toBe('admin_manual');
      expect(mockDb.events[1].source).toBe('admin_manual');
    });

    it('rejects overlapping shift with existing shifts', async () => {
      // First backfill
      await worker.fetch(
        createRequest('/api/v1/admin/events/manual', {
          method: 'POST',
          token: adminToken,
          body: {
            clockInAt: '2026-10-01T08:00:00Z',
            clockOutAt: '2026-10-01T16:00:00Z',
            reason: 'Initial shift',
            requestId: 'req-admin-initial',
          },
        }),
        env
      );

      // Overlapping backfill (12:00 to 18:00)
      const res = await worker.fetch(
        createRequest('/api/v1/admin/events/manual', {
          method: 'POST',
          token: adminToken,
          body: {
            clockInAt: '2026-10-01T12:00:00Z',
            clockOutAt: '2026-10-01T18:00:00Z',
            reason: 'Overlapping shift',
            requestId: 'req-admin-overlap',
          },
        }),
        env
      );

      expect(res.status).toBe(400);
      const data = await res.json() as { error: { code: string } };
      expect(data.error.code).toBe('OVERLAPPING_SHIFT');
    });
  });
});
