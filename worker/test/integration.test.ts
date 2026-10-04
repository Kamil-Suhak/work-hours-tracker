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
      headers?: Record<string, string>;
    } = {}
  ): Request {
    const { method = 'GET', token = validToken, body, headers: customHeaders } = options;
    const headers: Record<string, string> = { ...customHeaders };
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

    it('saves note on clock-out and returns it in events query', async () => {
      await worker.fetch(
        createRequest('/api/v1/clock-in', {
          method: 'POST',
          body: { requestId: 'req-in-note', source: 'flutter_app' },
        }),
        env
      );

      const noteText = '# Shift Recap\n- Finished sprint tickets\n- Reviewed **PR #42**';
      const resOut = await worker.fetch(
        createRequest('/api/v1/clock-out', {
          method: 'POST',
          body: { requestId: 'req-out-note', source: 'flutter_app', note: noteText },
        }),
        env
      );
      expect(resOut.status).toBe(200);

      const now = new Date();
      const from = new Date(now.getTime() - 24 * 60 * 60 * 1000).toISOString();
      const to = new Date(now.getTime() + 24 * 60 * 60 * 1000).toISOString();
      const eventsRes = await worker.fetch(
        createRequest(`/api/v1/events?from=${encodeURIComponent(from)}&to=${encodeURIComponent(to)}`),
        env
      );
      expect(eventsRes.status).toBe(200);
      const events = await eventsRes.json() as Array<{ event_type: string; note: string | null }>;
      const clockOutEvent = events.find((e) => e.event_type === 'clock_out');
      expect(clockOutEvent?.note).toBe(noteText);
    });

    it('rejects clock-out with note exceeding 4,000 characters', async () => {
      const res = await worker.fetch(
        createRequest('/api/v1/clock-out', {
          method: 'POST',
          body: {
            requestId: 'req-out-toolong',
            source: 'flutter_app',
            note: 'x'.repeat(4001),
          },
        }),
        env
      );
      expect(res.status).toBe(400);
      const data = await res.json() as { error: { code: string; message: string } };
      expect(data.error.code).toBe('NOTE_TOO_LONG');
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

  describe('Undo Operation Pipeline', () => {
    it('rejects undo request with invalid body', async () => {
      const res = await worker.fetch(
        createRequest('/api/v1/undo', {
          method: 'POST',
          body: { requestId: 'req-undo-invalid' },
        }),
        env
      );
      expect(res.status).toBe(400);
      const data = await res.json() as { error: { code: string } };
      expect(data.error.code).toBe('INVALID_EVENT_ID');
    });

    it('rejects undo when no events exist', async () => {
      const res = await worker.fetch(
        createRequest('/api/v1/undo', {
          method: 'POST',
          body: { requestId: 'req-undo-none', eventId: 'non-existent' },
        }),
        env
      );
      expect(res.status).toBe(404);
      const data = await res.json() as { error: { code: string } };
      expect(data.error.code).toBe('NO_EVENTS_FOUND');
    });

    it('reverts clock-in to clocked-out and removes event', async () => {
      // 1. Clock in
      const inRes = await worker.fetch(
        createRequest('/api/v1/clock-in', {
          method: 'POST',
          body: { requestId: 'req-in-undo', source: 'flutter_app' },
        }),
        env
      );
      expect(inRes.status).toBe(200);
      const inData = await inRes.json() as { state: string; eventId?: string };
      expect(mockDb.events).toHaveLength(1);
      const eventId = mockDb.events[0].id;

      // 2. Undo
      const undoRes = await worker.fetch(
        createRequest('/api/v1/undo', {
          method: 'POST',
          body: { requestId: 'req-undo-1', eventId },
        }),
        env
      );
      expect(undoRes.status).toBe(200);
      const undoData = await undoRes.json() as { success: boolean; restoredState: string; activeSince: string | null };
      expect(undoData.success).toBe(true);
      expect(undoData.restoredState).toBe('clocked_out');
      expect(undoData.activeSince).toBeNull();

      // Event should be deleted
      expect(mockDb.events).toHaveLength(0);

      // State should be clocked-out
      const state = mockDb.workState.get('default-user');
      expect(state?.state).toBe('clocked_out');
    });

    it('reverts clock-out back to clocked-in and restores activeSince', async () => {
      // 1. Clock in
      await worker.fetch(
        createRequest('/api/v1/clock-in', {
          method: 'POST',
          body: { requestId: 'req-in-1', source: 'flutter_app' },
        }),
        env
      );
      const inEvent = mockDb.events[0];

      // 2. Clock out
      await worker.fetch(
        createRequest('/api/v1/clock-out', {
          method: 'POST',
          body: { requestId: 'req-out-1', source: 'android_widget' },
        }),
        env
      );
      expect(mockDb.events).toHaveLength(2);
      const outEvent = mockDb.events[1];

      // 3. Undo the clock-out
      const undoRes = await worker.fetch(
        createRequest('/api/v1/undo', {
          method: 'POST',
          body: { requestId: 'req-undo-out', eventId: outEvent.id },
        }),
        env
      );
      expect(undoRes.status).toBe(200);
      const undoData = await undoRes.json() as { success: boolean; restoredState: string; activeSince: string | null };
      expect(undoData.success).toBe(true);
      expect(undoData.restoredState).toBe('clocked_in');
      expect(undoData.activeSince).toBe(inEvent.occurred_at_utc);

      // Only clock-in remains
      expect(mockDb.events).toHaveLength(1);
      expect(mockDb.events[0].id).toBe(inEvent.id);
    });

    it('rejects undo if event is not the latest event', async () => {
      await worker.fetch(
        createRequest('/api/v1/clock-in', {
          method: 'POST',
          body: { requestId: 'req-in-first', source: 'flutter_app' },
        }),
        env
      );
      const firstEventId = mockDb.events[0].id;

      await worker.fetch(
        createRequest('/api/v1/clock-out', {
          method: 'POST',
          body: { requestId: 'req-out-second', source: 'flutter_app' },
        }),
        env
      );

      // Attempt to undo the FIRST event instead of the latest
      const res = await worker.fetch(
        createRequest('/api/v1/undo', {
          method: 'POST',
          body: { requestId: 'req-undo-old', eventId: firstEventId },
        }),
        env
      );
      expect(res.status).toBe(409);
      const data = await res.json() as { error: { code: string } };
      expect(data.error.code).toBe('EVENT_MISMATCH');
    });

    it('replays cached response when repeating identical requestId (idempotency)', async () => {
      await worker.fetch(
        createRequest('/api/v1/clock-in', {
          method: 'POST',
          body: { requestId: 'req-in-idem', source: 'flutter_app' },
        }),
        env
      );
      const eventId = mockDb.events[0].id;

      const undoBody = { requestId: 'req-undo-idem', eventId };
      const res1 = await worker.fetch(
        createRequest('/api/v1/undo', { method: 'POST', body: undoBody }),
        env
      );
      const data1 = await res1.json();

      const res2 = await worker.fetch(
        createRequest('/api/v1/undo', { method: 'POST', body: undoBody }),
        env
      );
      const data2 = await res2.json();

      expect(data2).toEqual(data1);
    });
  });

  describe('Reports Pipeline & Scheduled Cron', () => {
    it('generates on-demand excel report with correct headers and binary payload', async () => {
      // Seed a shift pair
      mockDb.events.push(
        {
          id: 'ev-rep-in',
          request_id: 'r-in',
          user_id: 'default-user',
          device_id: 'dev-1',
          event_type: 'clock_in',
          source: 'flutter_app',
          occurred_at_utc: '2026-10-01T08:00:00.000Z',
          created_at_utc: '2026-10-01T08:00:00.000Z',
          reason: null,
          note: null,
        },
        {
          id: 'ev-rep-out',
          request_id: 'r-out',
          user_id: 'default-user',
          device_id: 'dev-1',
          event_type: 'clock_out',
          source: 'flutter_app',
          occurred_at_utc: '2026-10-01T16:00:00.000Z',
          created_at_utc: '2026-10-01T16:00:00.000Z',
          reason: null,
          note: 'Completed monthly goals',
        }
      );

      const res = await worker.fetch(
        createRequest('/api/v1/reports/generate', {
          method: 'POST',
          body: {
            startDate: '2026-10-01',
            endDate: '2026-10-31',
            preset: 'formal',
            options: { includeNotes: true },
          },
        }),
        env
      );

      expect(res.status).toBe(200);
      expect(res.headers.get('Content-Type')).toBe(
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
      );
      expect(res.headers.get('Content-Disposition')).toContain('attachment; filename="work-hours-');
      expect(res.headers.get('X-Total-Hours')).toBe('8');
      expect(res.headers.get('X-Total-Shifts')).toBe('1');

      const buffer = await res.arrayBuffer();
      expect(buffer.byteLength).toBeGreaterThan(100);
      const bytes = new Uint8Array(buffer);
      // Verify ZIP magic bytes
      expect(bytes[0]).toBe(0x50);
      expect(bytes[1]).toBe(0x4b);
      expect(bytes[2]).toBe(0x03);
      expect(bytes[3]).toBe(0x04);
    });

    it('returns 404 for latest report when bucket has no reports', async () => {
      const res = await worker.fetch(createRequest('/api/v1/reports/latest'), env);
      expect(res.status).toBe(404);
      const err = await res.json() as { error: { code: string } };
      expect(err.error.code).toBe('NO_REPORTS_FOUND');
    });

    it('scheduled cron handler executes successfully without throwing', async () => {
      let waited = false;
      const ctx = {
        waitUntil: (p: Promise<unknown>) => {
          waited = true;
          p.catch(() => {});
        },
      };

      await worker.scheduled(
        { cron: '0 0 1 * *', scheduledTime: Date.now() },
        env,
        ctx as any
      );

      expect(waited).toBe(true);
    });
  });

  describe('Report Download & Storage Hardening', () => {
    it('rejects download when REPORTS_BUCKET is not configured', async () => {
      const res = await worker.fetch(
        createRequest('/api/v1/reports/download/work-hours-2026-10-formal.xlsx'),
        env
      );
      expect(res.status).toBe(503);
      const data = await res.json() as { error: { code: string } };
      expect(data.error.code).toBe('STORAGE_NOT_CONFIGURED');
    });

    it('rejects path traversal and directory separators in download filename', async () => {
      const mockBucket: Record<string, Uint8Array> = {};
      const bucketEnv: Env = {
        ...env,
        REPORTS_BUCKET: {
          get: async (key: string) => {
            if (!mockBucket[key]) return null;
            return {
              body: mockBucket[key] as any,
              customMetadata: {},
            } as any;
          },
        } as any,
      };

      const traversalFilenames = [
        '..%2F..%2Fsecrets.json',
        'subfolder/work-hours-2026-10-formal.xlsx',
        '..%5Cwork-hours-2026-10-formal.xlsx',
      ];

      for (const name of traversalFilenames) {
        const res = await worker.fetch(
          createRequest(`/api/v1/reports/download/${name}`),
          bucketEnv
        );
        expect(res.status).toBe(400);
        const data = await res.json() as { error: { code: string } };
        expect(data.error.code).toBe('INVALID_FILENAME');
      }
    });

    it('rejects malformed filenames that do not match report naming convention', async () => {
      const bucketEnv: Env = {
        ...env,
        REPORTS_BUCKET: {
          get: async () => null,
        } as any,
      };

      const invalidNames = [
        'malicious-file.exe',
        'work-hours-notadate-formal.xlsx',
        'work-hours-2026-10.csv',
      ];

      for (const name of invalidNames) {
        const res = await worker.fetch(
          createRequest(`/api/v1/reports/download/${name}`),
          bucketEnv
        );
        expect(res.status).toBe(400);
        const data = await res.json() as { error: { code: string } };
        expect(data.error.code).toBe('INVALID_FILENAME');
      }
    });

    it('returns 404 when valid report filename is not present in bucket', async () => {
      const bucketEnv: Env = {
        ...env,
        REPORTS_BUCKET: {
          get: async () => null,
        } as any,
      };

      const res = await worker.fetch(
        createRequest('/api/v1/reports/download/work-hours-2026-10-formal.xlsx'),
        bucketEnv
      );
      expect(res.status).toBe(404);
      const data = await res.json() as { error: { code: string } };
      expect(data.error.code).toBe('REPORT_NOT_FOUND');
    });

    it('serves report with correct headers and Content-Disposition when present', async () => {
      const samplePayload = new Uint8Array([0x50, 0x4b, 0x03, 0x04, 0x00, 0x01]);
      const mockBucket: Record<string, Uint8Array> = {
        'reports/work-hours-2026-10-formal.xlsx': samplePayload,
      };

      const bucketEnv: Env = {
        ...env,
        REPORTS_BUCKET: {
          get: async (key: string) => {
            if (!mockBucket[key]) return null;
            return {
              body: mockBucket[key] as any,
              customMetadata: { generatedAt: '2026-10-01T00:00:00Z' },
            } as any;
          },
        } as any,
      };

      const res = await worker.fetch(
        createRequest('/api/v1/reports/download/work-hours-2026-10-formal.xlsx'),
        bucketEnv
      );

      expect(res.status).toBe(200);
      expect(res.headers.get('Content-Type')).toBe(
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
      );
      expect(res.headers.get('Content-Disposition')).toBe(
        'attachment; filename="work-hours-2026-10-formal.xlsx"'
      );
      const body = await res.arrayBuffer();
      expect(new Uint8Array(body)).toEqual(samplePayload);
    });
  });

  describe('CORS and Security Headers', () => {
    it('allows same-origin or localhost origins and adds security headers', async () => {
      const res = await worker.fetch(
        createRequest('/api/v1/status', {
          headers: {
            Origin: 'http://localhost:3000',
          },
        }),
        env
      );

      expect(res.status).toBe(200);
      expect(res.headers.get('Access-Control-Allow-Origin')).toBe('http://localhost:3000');
      expect(res.headers.get('Vary')).toContain('Origin');
      expect(res.headers.get('X-Content-Type-Options')).toBe('nosniff');
      expect(res.headers.get('Referrer-Policy')).toBe('strict-origin-when-cross-origin');
      expect(res.headers.get('Cache-Control')).toContain('no-store');
    });

    it('does not reflect disallowed third-party origin in Access-Control-Allow-Origin', async () => {
      const res = await worker.fetch(
        createRequest('/api/v1/status', {
          headers: {
            Origin: 'https://malicious-external-site.com',
          },
        }),
        env
      );

      expect(res.status).toBe(200);
      expect(res.headers.get('Access-Control-Allow-Origin')).toBeNull();
      expect(res.headers.get('Vary')).toContain('Origin');
    });

    it('responds with 204 to OPTIONS preflight requests', async () => {
      const res = await worker.fetch(
        createRequest('/api/v1/clock-in', {
          method: 'OPTIONS',
          headers: {
            Origin: 'http://localhost:8080',
          },
        }),
        env
      );

      expect(res.status).toBe(204);
      expect(res.headers.get('Access-Control-Allow-Origin')).toBe('http://localhost:8080');
      expect(res.headers.get('Access-Control-Allow-Methods')).toContain('POST');
    });
  });
});

