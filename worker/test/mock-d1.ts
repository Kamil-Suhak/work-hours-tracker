import type { D1Database, D1PreparedStatement, D1Result, D1Response } from '@cloudflare/workers-types';
import type { DeviceRow, EventRow, ProcessedRequestRow, WorkStateRow } from '../src/types';

export class MockD1Database implements Partial<D1Database> {
  public devices: DeviceRow[] = [];
  public workState: Map<string, WorkStateRow> = new Map();
  public events: EventRow[] = [];
  public processedRequests: Map<string, ProcessedRequestRow> = new Map();

  prepare(query: string): D1PreparedStatement {
    return new MockPreparedStatement(this, query) as unknown as D1PreparedStatement;
  }

  async batch<T = unknown>(statements: D1PreparedStatement[]): Promise<D1Result<T>[]> {
    const results: D1Result<T>[] = [];
    for (const stmt of statements) {
      const mockStmt = stmt as unknown as MockPreparedStatement;
      const res = await mockStmt.run();
      results.push(res as unknown as D1Result<T>);
    }
    return results;
  }
}

export class MockPreparedStatement {
  private boundArgs: unknown[] = [];

  constructor(
    private db: MockD1Database,
    private query: string
  ) {}

  bind(...args: unknown[]): this {
    this.boundArgs = args;
    return this;
  }

  async first<T = Record<string, unknown>>(colName?: string): Promise<T | null> {
    const q = this.query.trim();

    if (q.includes('FROM devices WHERE token_hash = ?')) {
      const hash = this.boundArgs[0] as string;
      const found = this.db.devices.find((d) => d.token_hash === hash);
      return (found as unknown as T) ?? null;
    }

    if (q.includes('FROM processed_requests WHERE request_id = ?')) {
      const reqId = this.boundArgs[0] as string;
      const found = this.db.processedRequests.get(reqId);
      return (found ? { response_json: found.response_json } : null) as unknown as T;
    }

    if (q.includes('FROM work_state WHERE user_id = ?')) {
      const userId = this.boundArgs[0] as string;
      const found = this.db.workState.get(userId);
      return (found as unknown as T) ?? null;
    }

    if (q.includes('FROM events WHERE user_id = ? AND id != ?')) {
      const userId = this.boundArgs[0] as string;
      const excludeId = this.boundArgs[1] as string;
      const matching = this.db.events.filter((e) => e.user_id === userId && e.id !== excludeId);
      const sorted = [...matching].reverse().sort((a, b) => b.occurred_at_utc.localeCompare(a.occurred_at_utc));
      return (sorted[0] as unknown as T) ?? null;
    }

    if (q.includes('FROM events WHERE user_id = ? ORDER BY occurred_at_utc DESC')) {
      const userId = this.boundArgs[0] as string;
      const matching = this.db.events.filter((e) => e.user_id === userId);
      const sorted = [...matching].reverse().sort((a, b) => b.occurred_at_utc.localeCompare(a.occurred_at_utc));
      return (sorted[0] as unknown as T) ?? null;
    }

    return null;
  }

  async all<T = Record<string, unknown>>(): Promise<D1Result<T>> {
    const q = this.query.trim();

    if (q.includes('FROM events') && q.includes('occurred_at_utc >= ?') && q.includes('occurred_at_utc <= ?')) {
      const userId = this.boundArgs[0] as string;
      const from = this.boundArgs[1] as string;
      const to = this.boundArgs[2] as string;

      const filtered = this.db.events
        .filter((e) => e.user_id === userId && e.occurred_at_utc >= from && e.occurred_at_utc <= to)
        .sort((a, b) => a.occurred_at_utc.localeCompare(b.occurred_at_utc) || a.id.localeCompare(b.id));

      return {
        results: filtered as unknown as T[],
        success: true,
        meta: {} as D1Response['meta'],
      };
    }

    if (q.includes('FROM events') && q.includes('occurred_at_utc >= ?')) {
      const userId = this.boundArgs[0] as string;
      const from = this.boundArgs[1] as string;

      const filtered = this.db.events
        .filter((e) => e.user_id === userId && e.occurred_at_utc >= from)
        .sort((a, b) => a.occurred_at_utc.localeCompare(b.occurred_at_utc) || a.id.localeCompare(b.id));

      return {
        results: filtered as unknown as T[],
        success: true,
        meta: {} as D1Response['meta'],
      };
    }

    return {
      results: [] as T[],
      success: true,
      meta: {} as D1Response['meta'],
    };
  }

  async run(): Promise<D1Response> {
    const q = this.query.trim();

    if (q.includes('DELETE FROM events WHERE id = ?')) {
      const id = this.boundArgs[0] as string;
      const idx = this.db.events.findIndex((e) => e.id === id);
      if (idx !== -1) {
        this.db.events.splice(idx, 1);
      }
    }

    if (q.includes('INSERT INTO events')) {
      const eventType = q.includes("'clock_in'") ? 'clock_in' : 'clock_out';

      if (q.includes("'admin_manual'")) {
        const id = this.boundArgs[0] as string;
        const requestId = this.boundArgs[1] as string;
        const userId = this.boundArgs[2] as string;
        const occurredAtUtc = this.boundArgs[3] as string;
        const createdAtUtc = this.boundArgs[4] as string;
        const reason = (this.boundArgs[5] as string) ?? null;
        const note = (this.boundArgs[6] as string) ?? null;

        this.db.events.push({
          id,
          request_id: requestId,
          user_id: userId,
          device_id: null,
          event_type: eventType,
          source: 'admin_manual',
          occurred_at_utc: occurredAtUtc,
          created_at_utc: createdAtUtc,
          reason,
          note,
        });
      } else {
        const id = this.boundArgs[0] as string;
        const requestId = this.boundArgs[1] as string;
        const userId = this.boundArgs[2] as string;
        const deviceId = this.boundArgs[3] as string | null;
        const source = this.boundArgs[4] as EventRow['source'];
        const occurredAtUtc = this.boundArgs[5] as string;
        const createdAtUtc = this.boundArgs[6] as string;
        const note = (this.boundArgs[7] as string) ?? null;

        this.db.events.push({
          id,
          request_id: requestId,
          user_id: userId,
          device_id: deviceId,
          event_type: eventType,
          source,
          occurred_at_utc: occurredAtUtc,
          created_at_utc: createdAtUtc,
          reason: null,
          note,
        });
      }
    }

    if (q.includes('INSERT INTO work_state')) {
      const userId = this.boundArgs[0] as string;
      const isClockIn = q.includes("'clocked_in'");
      const activeSince = isClockIn ? (this.boundArgs[1] as string) : null;
      const version = (isClockIn ? this.boundArgs[2] : this.boundArgs[1]) as number;
      const updatedAt = (isClockIn ? this.boundArgs[3] : this.boundArgs[2]) as string;

      this.db.workState.set(userId, {
        user_id: userId,
        state: isClockIn ? 'clocked_in' : 'clocked_out',
        active_since_utc: activeSince,
        version,
        updated_at_utc: updatedAt,
      });
    }

    if (q.includes('INSERT INTO processed_requests') || q.includes('INSERT OR IGNORE INTO processed_requests')) {
      const requestId = this.boundArgs[0] as string;
      const userId = this.boundArgs[1] as string;
      let operation = 'unknown';
      let responseJson = '';
      let createdAtUtc = '';

      if (this.boundArgs.length === 5) {
        operation = this.boundArgs[2] as string;
        responseJson = this.boundArgs[3] as string;
        createdAtUtc = this.boundArgs[4] as string;
      } else {
        if (q.includes("'clock_in'")) operation = 'clock_in';
        else if (q.includes("'clock_out'")) operation = 'clock_out';
        else if (q.includes("'admin_manual'")) operation = 'admin_manual';
        responseJson = this.boundArgs[2] as string;
        createdAtUtc = this.boundArgs[3] as string;
      }

      if (!this.db.processedRequests.has(requestId)) {
        this.db.processedRequests.set(requestId, {
          request_id: requestId,
          user_id: userId,
          operation,
          response_json: responseJson,
          created_at_utc: createdAtUtc,
        });
      }
    }

    return {
      success: true,
      meta: {} as D1Response['meta'],
    };
  }
}
