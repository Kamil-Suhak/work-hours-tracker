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
    const eventsSnapshot = this.events.map((e) => ({ ...e }));
    const workStateSnapshot = new Map(
      Array.from(this.workState.entries()).map(([k, v]) => [k, { ...v }])
    );
    const processedSnapshot = new Map(
      Array.from(this.processedRequests.entries()).map(([k, v]) => [k, { ...v }])
    );

    const results: D1Result<T>[] = [];
    try {
      // Execute all statements synchronously in one JS turn to match SQLite atomic transactions.
      for (const stmt of statements) {
        const mockStmt = stmt as unknown as MockPreparedStatement;
        const res = mockStmt.runSync();
        results.push(res as unknown as D1Result<T>);
      }
      return results;
    } catch (err) {
      this.events = eventsSnapshot;
      this.workState = workStateSnapshot;
      this.processedRequests = processedSnapshot;
      throw err;
    }
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

  private normalizedQuery(): string {
    return this.query.replace(/\s+/g, ' ').trim();
  }

  private assertBindCount(q: string): void {
    const stripped = q.replace(/'(?:''|[^'])*'/g, "''");
    const placeholders = (stripped.match(/\?/g) ?? []).length;
    if (placeholders !== this.boundArgs.length) {
      throw new Error(
        `MockD1Database bind count mismatch: expected ${placeholders} argument(s), got ${this.boundArgs.length} for query: ${q}`
      );
    }
  }

  private sortEventsDesc(predicate: (e: EventRow) => boolean): EventRow[] {
    return this.db.events
      .map((event, rowid) => ({ event, rowid }))
      .filter(({ event }) => predicate(event))
      .sort(
        (a, b) =>
          b.event.occurred_at_utc.localeCompare(a.event.occurred_at_utc) ||
          b.event.created_at_utc.localeCompare(a.event.created_at_utc) ||
          b.rowid - a.rowid
      )
      .map(({ event }) => event);
  }

  private sortEventsAsc(predicate: (e: EventRow) => boolean): EventRow[] {
    return this.db.events
      .map((event, rowid) => ({ event, rowid }))
      .filter(({ event }) => predicate(event))
      .sort(
        (a, b) =>
          a.event.occurred_at_utc.localeCompare(b.event.occurred_at_utc) ||
          a.event.created_at_utc.localeCompare(b.event.created_at_utc) ||
          a.rowid - b.rowid
      )
      .map(({ event }) => event);
  }

  async first<T = Record<string, unknown>>(colName?: string): Promise<T | null> {
    const q = this.normalizedQuery();
    this.assertBindCount(q);

    if (q.includes('FROM devices WHERE token_hash = ?')) {
      const hash = this.boundArgs[0] as string;
      const found = this.db.devices.find((d) => d.token_hash === hash);
      if (colName && found) {
        return ((found as unknown as Record<string, unknown>)[colName] as T) ?? null;
      }
      return (found as unknown as T) ?? null;
    }

    if (q.includes('FROM processed_requests WHERE request_id = ?')) {
      const reqId = this.boundArgs[0] as string;
      const found = this.db.processedRequests.get(reqId);
      const row = found ? { response_json: found.response_json } : null;
      if (colName && row) {
        return ((row as Record<string, unknown>)[colName] as T) ?? null;
      }
      return row as unknown as T;
    }

    if (q.includes('FROM work_state WHERE user_id = ?')) {
      const userId = this.boundArgs[0] as string;
      const found = this.db.workState.get(userId);
      if (colName && found) {
        return ((found as unknown as Record<string, unknown>)[colName] as T) ?? null;
      }
      return (found as unknown as T) ?? null;
    }

    if (q.includes('FROM events WHERE user_id = ? AND id != ?')) {
      const userId = this.boundArgs[0] as string;
      const excludeId = this.boundArgs[1] as string;
      const sorted = this.sortEventsDesc((e) => e.user_id === userId && e.id !== excludeId);
      return (sorted[0] as unknown as T) ?? null;
    }

    if (q.includes('FROM events WHERE user_id = ?') && q.includes('ORDER BY occurred_at_utc DESC')) {
      const userId = this.boundArgs[0] as string;
      const requireClockIn = q.includes("event_type = 'clock_in'");
      const sorted = this.sortEventsDesc(
        (e) => e.user_id === userId && (!requireClockIn || e.event_type === 'clock_in')
      );
      return (sorted[0] as unknown as T) ?? null;
    }

    if (q.includes('FROM events WHERE id = ? AND user_id = ?')) {
      const id = this.boundArgs[0] as string;
      const userId = this.boundArgs[1] as string;
      const found = this.db.events.find((e) => e.id === id && e.user_id === userId);
      return (found as unknown as T) ?? null;
    }

    throw new Error(`MockD1Database: unrecognized first() query: ${q}`);
  }

  async all<T = Record<string, unknown>>(): Promise<D1Result<T>> {
    const q = this.normalizedQuery();
    this.assertBindCount(q);

    if (
      q.includes('FROM events') &&
      q.includes('occurred_at_utc >= ?') &&
      (q.includes('occurred_at_utc <= ?') || q.includes('occurred_at_utc < ?'))
    ) {
      const userId = this.boundArgs[0] as string;
      const from = this.boundArgs[1] as string;
      const to = this.boundArgs[2] as string;
      const isLessEqual = q.includes('occurred_at_utc <= ?');

      const filtered = this.sortEventsAsc(
        (e) =>
          e.user_id === userId &&
          e.occurred_at_utc >= from &&
          (isLessEqual ? e.occurred_at_utc <= to : e.occurred_at_utc < to)
      );

      return {
        results: filtered as unknown as T[],
        success: true,
        meta: {} as D1Response['meta'],
      };
    }

    if (q.includes('FROM events') && q.includes('occurred_at_utc >= ?')) {
      const userId = this.boundArgs[0] as string;
      const from = this.boundArgs[1] as string;

      const filtered = this.sortEventsAsc((e) => e.user_id === userId && e.occurred_at_utc >= from);

      return {
        results: filtered as unknown as T[],
        success: true,
        meta: {} as D1Response['meta'],
      };
    }

    throw new Error(`MockD1Database: unrecognized all() query: ${q}`);
  }

  async run(): Promise<D1Response> {
    return this.runSync();
  }

  runSync(): D1Response {
    const q = this.normalizedQuery();
    this.assertBindCount(q);
    let changes = 0;

    if (q.includes('DELETE FROM events') && q.includes('WHERE id = ?')) {
      const id = this.boundArgs[0] as string;
      let canDelete = true;

      if (q.includes('AND EXISTS') && q.includes('AND NOT EXISTS')) {
        const userId = this.boundArgs[1] as string;
        const wsUserId = this.boundArgs[2] as string;
        const expectedVersion = this.boundArgs[3] as number;
        const e2UserId = this.boundArgs[4] as string;
        const e2ExcludeId = this.boundArgs[5] as string;
        const occ = this.boundArgs[6] as string;
        const created = this.boundArgs[8] as string;
        const ws = this.db.workState.get(wsUserId);
        const hasNewer = this.db.events.some(
          (e2) =>
            e2.user_id === e2UserId &&
            e2.id !== e2ExcludeId &&
            (e2.occurred_at_utc > occ || (e2.occurred_at_utc === occ && e2.created_at_utc > created))
        );
        canDelete =
          Boolean(ws && ws.version === expectedVersion) &&
          !hasNewer &&
          this.db.events.some((e) => e.id === id && e.user_id === userId);
      } else if (q.includes('AND NOT EXISTS (SELECT 1 FROM work_state') && q.includes('AND NOT EXISTS')) {
        const userId = this.boundArgs[1] as string;
        const wsUserId = this.boundArgs[2] as string;
        const e2UserId = this.boundArgs[3] as string;
        const e2ExcludeId = this.boundArgs[4] as string;
        const occ = this.boundArgs[5] as string;
        const created = this.boundArgs[7] as string;
        const hasNewer = this.db.events.some(
          (e2) =>
            e2.user_id === e2UserId &&
            e2.id !== e2ExcludeId &&
            (e2.occurred_at_utc > occ || (e2.occurred_at_utc === occ && e2.created_at_utc > created))
        );
        canDelete =
          !this.db.workState.has(wsUserId) &&
          !hasNewer &&
          this.db.events.some((e) => e.id === id && e.user_id === userId);
      }

      if (canDelete) {
        const idx = this.db.events.findIndex((e) => e.id === id);
        if (idx !== -1) {
          this.db.events.splice(idx, 1);
          changes = 1;
        }
      }
    } else if (q.includes('UPDATE events SET note = ?')) {
      const note = (this.boundArgs[0] as string) ?? null;
      const id = this.boundArgs[1] as string;
      const userId = q.includes('AND user_id = ?') ? (this.boundArgs[2] as string) : null;
      const event = this.db.events.find((e) => e.id === id && (userId === null || e.user_id === userId));
      if (event) {
        event.note = note;
        changes = 1;
      }
    } else if (q.includes('INSERT INTO events')) {
      if (q.includes("'Auto-stopped at target'") && q.includes('WHERE EXISTS')) {
        const id = this.boundArgs[0] as string;
        const requestId = this.boundArgs[1] as string;
        const userId = this.boundArgs[2] as string;
        const deviceId = this.boundArgs[3] as string | null;
        const source = this.boundArgs[4] as EventRow['source'];
        const occurredAtUtc = this.boundArgs[5] as string;
        const createdAtUtc = this.boundArgs[6] as string;
        const location = (this.boundArgs[7] as EventRow['location']) ?? 'remote';
        const whereUserId = this.boundArgs[8] as string;
        const expectedVersion = this.boundArgs[9] as number;
        const expectedTarget = this.boundArgs[10] as string;

        const ws = this.db.workState.get(whereUserId);
        if (
          ws &&
          ws.state === 'clocked_in' &&
          ws.version === expectedVersion &&
          ws.target_clock_out_utc === expectedTarget
        ) {
          if (this.db.events.some((e) => e.request_id === requestId)) {
            throw new Error('UNIQUE constraint failed: events.request_id');
          }
          this.db.events.push({
            id,
            request_id: requestId,
            user_id: userId,
            device_id: deviceId,
            event_type: 'clock_out',
            source,
            occurred_at_utc: occurredAtUtc,
            created_at_utc: createdAtUtc,
            reason: 'Auto-stopped at target',
            note: null,
            location,
          });
          changes = 1;
        }
      } else if (q.includes('WHERE EXISTS')) {
        const eventType = q.includes("'clock_in'") ? 'clock_in' : 'clock_out';
        const expectedState = q.includes("state = 'clocked_out'") ? 'clocked_out' : 'clocked_in';
        const id = this.boundArgs[0] as string;
        const requestId = this.boundArgs[1] as string;
        const userId = this.boundArgs[2] as string;
        const deviceId = this.boundArgs[3] as string | null;
        const source = this.boundArgs[4] as EventRow['source'];
        const occurredAtUtc = this.boundArgs[5] as string;
        const createdAtUtc = this.boundArgs[6] as string;
        const note = (this.boundArgs[7] as string) ?? null;
        const location = (this.boundArgs[8] as EventRow['location']) ?? 'remote';
        const whereUserId = this.boundArgs[9] as string;
        const expectedVersion = this.boundArgs[10] as number;

        const ws = this.db.workState.get(whereUserId);
        if (ws && ws.state === expectedState && ws.version === expectedVersion) {
          if (this.db.events.some((e) => e.request_id === requestId)) {
            throw new Error('UNIQUE constraint failed: events.request_id');
          }
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
            location,
          });
          changes = 1;
        }
      } else if (q.includes('WHERE NOT EXISTS')) {
        const eventType = q.includes("'clock_in'") ? 'clock_in' : 'clock_out';
        const id = this.boundArgs[0] as string;
        const requestId = this.boundArgs[1] as string;
        const userId = this.boundArgs[2] as string;
        const deviceId = this.boundArgs[3] as string | null;
        const source = this.boundArgs[4] as EventRow['source'];
        const occurredAtUtc = this.boundArgs[5] as string;
        const createdAtUtc = this.boundArgs[6] as string;
        const note = (this.boundArgs[7] as string) ?? null;
        const location = (this.boundArgs[8] as EventRow['location']) ?? 'remote';
        const whereUserId = this.boundArgs[9] as string;

        if (!this.db.workState.has(whereUserId)) {
          if (this.db.events.some((e) => e.request_id === requestId)) {
            throw new Error('UNIQUE constraint failed: events.request_id');
          }
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
            location,
          });
          changes = 1;
        }
      } else {
        const eventType = q.includes("'clock_in'") ? 'clock_in' : 'clock_out';
        const id = this.boundArgs[0] as string;
        const requestId = this.boundArgs[1] as string;
        const userId = this.boundArgs[2] as string;
        const deviceId = this.boundArgs[3] as string | null;
        const source = this.boundArgs[4] as EventRow['source'];
        const occurredAtUtc = this.boundArgs[5] as string;
        const createdAtUtc = this.boundArgs[6] as string;
        const note = (this.boundArgs[7] as string) ?? null;
        const location = (this.boundArgs[8] as EventRow['location']) ?? 'remote';

        if (this.db.events.some((e) => e.request_id === requestId)) {
          throw new Error('UNIQUE constraint failed: events.request_id');
        }

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
          location,
        });
        changes = 1;
      }
    } else if (q.includes('INSERT INTO work_state')) {
      const userId = this.boundArgs[0] as string;
      const doNothingOnConflict = q.includes('ON CONFLICT(user_id) DO NOTHING');
      const excludedEventId = q.includes('WHERE NOT EXISTS (SELECT 1 FROM events WHERE id = ?)')
        ? (this.boundArgs[5] as string)
        : null;
      const whereOk = excludedEventId === null || !this.db.events.some((e) => e.id === excludedEventId);

      if (whereOk && (!doNothingOnConflict || !this.db.workState.has(userId))) {
        let state: WorkStateRow['state'];
        let activeSince: string | null;
        let targetClockOutUtc: string | null;
        let version: number;
        let updatedAt: string;

        if (q.includes("'clocked_in'")) {
          state = 'clocked_in';
          activeSince = this.boundArgs[1] as string;
          targetClockOutUtc = (this.boundArgs[2] as string) ?? null;
          version = this.boundArgs[3] as number;
          updatedAt = this.boundArgs[4] as string;
        } else if (q.includes("'clocked_out'")) {
          state = 'clocked_out';
          activeSince = null;
          targetClockOutUtc = null;
          version = this.boundArgs[1] as number;
          updatedAt = this.boundArgs[2] as string;
        } else {
          state = this.boundArgs[1] as WorkStateRow['state'];
          activeSince = (this.boundArgs[2] as string) ?? null;
          targetClockOutUtc = null;
          version = this.boundArgs[3] as number;
          updatedAt = this.boundArgs[4] as string;
        }

        this.db.workState.set(userId, {
          user_id: userId,
          state,
          active_since_utc: activeSince,
          target_clock_out_utc: targetClockOutUtc,
          version,
          updated_at_utc: updatedAt,
        });
        changes = 1;
      }
    } else if (q.includes('UPDATE work_state')) {
      if (q.includes("SET state = 'clocked_out'") && q.includes('AND target_clock_out_utc = ?')) {
        const nextVersion = this.boundArgs[0] as number;
        const updatedAt = this.boundArgs[1] as string;
        const userId = this.boundArgs[2] as string;
        const expectedVersion = this.boundArgs[3] as number;
        const expectedTarget = this.boundArgs[4] as string;
        const existing = this.db.workState.get(userId);
        if (
          existing &&
          existing.state === 'clocked_in' &&
          existing.version === expectedVersion &&
          existing.target_clock_out_utc === expectedTarget
        ) {
          this.db.workState.set(userId, {
            ...existing,
            state: 'clocked_out',
            active_since_utc: null,
            target_clock_out_utc: null,
            version: nextVersion,
            updated_at_utc: updatedAt,
          });
          changes = 1;
        }
      } else if (q.includes("SET state = 'clocked_out'")) {
        const nextVersion = this.boundArgs[0] as number;
        const updatedAt = this.boundArgs[1] as string;
        const userId = this.boundArgs[2] as string;
        const expectedVersion = this.boundArgs[3] as number;
        const existing = this.db.workState.get(userId);
        if (
          existing &&
          existing.state === 'clocked_in' &&
          existing.version === expectedVersion
        ) {
          this.db.workState.set(userId, {
            ...existing,
            state: 'clocked_out',
            active_since_utc: null,
            target_clock_out_utc: null,
            version: nextVersion,
            updated_at_utc: updatedAt,
          });
          changes = 1;
        }
      } else if (q.includes("SET state = 'clocked_in'")) {
        const activeSince = this.boundArgs[0] as string;
        const targetClockOutUtc = (this.boundArgs[1] as string) ?? null;
        const nextVersion = this.boundArgs[2] as number;
        const updatedAt = this.boundArgs[3] as string;
        const userId = this.boundArgs[4] as string;
        const expectedVersion = this.boundArgs[5] as number;
        const existing = this.db.workState.get(userId);
        if (
          existing &&
          existing.state === 'clocked_out' &&
          existing.version === expectedVersion
        ) {
          this.db.workState.set(userId, {
            ...existing,
            state: 'clocked_in',
            active_since_utc: activeSince,
            target_clock_out_utc: targetClockOutUtc,
            version: nextVersion,
            updated_at_utc: updatedAt,
          });
          changes = 1;
        }
      } else if (q.includes('SET state = ?')) {
        const state = this.boundArgs[0] as WorkStateRow['state'];
        const activeSince = (this.boundArgs[1] as string) ?? null;
        const nextVersion = this.boundArgs[2] as number;
        const updatedAt = this.boundArgs[3] as string;
        const userId = this.boundArgs[4] as string;
        const expectedVersion = this.boundArgs[5] as number;
        const deletedEventId = this.boundArgs[6] as string;
        const existing = this.db.workState.get(userId);
        if (
          existing &&
          existing.version === expectedVersion &&
          !this.db.events.some((e) => e.id === deletedEventId)
        ) {
          this.db.workState.set(userId, {
            ...existing,
            state,
            active_since_utc: activeSince,
            target_clock_out_utc: null,
            version: nextVersion,
            updated_at_utc: updatedAt,
          });
          changes = 1;
        }
      } else if (q.includes('SET target_clock_out_utc = ?')) {
        const nextTarget = (this.boundArgs[0] as string) ?? null;
        const nextVersion = this.boundArgs[1] as number;
        const updatedAt = this.boundArgs[2] as string;
        const userId = this.boundArgs[3] as string;
        const expectedVersion = this.boundArgs[4] as number;
        const existing = this.db.workState.get(userId);
        if (
          existing &&
          existing.state === 'clocked_in' &&
          existing.version === expectedVersion
        ) {
          this.db.workState.set(userId, {
            ...existing,
            target_clock_out_utc: nextTarget,
            version: nextVersion,
            updated_at_utc: updatedAt,
          });
          changes = 1;
        }
      } else {
        throw new Error(`MockD1Database: unrecognized UPDATE work_state query: ${q}`);
      }
    } else if (q.includes('INSERT INTO processed_requests') || q.includes('INSERT OR IGNORE INTO processed_requests')) {
      const requestId = this.boundArgs[0] as string;
      const userId = this.boundArgs[1] as string;
      let operation = 'unknown';
      let responseJson = '';
      let createdAtUtc = '';

      if (this.boundArgs.length >= 5) {
        operation = this.boundArgs[2] as string;
        responseJson = this.boundArgs[3] as string;
        createdAtUtc = this.boundArgs[4] as string;
      } else {
        if (q.includes("'clock_in'")) operation = 'clock_in';
        else if (q.includes("'clock_out'")) operation = 'clock_out';
        responseJson = this.boundArgs[2] as string;
        createdAtUtc = this.boundArgs[3] as string;
      }

      let whereOk = true;
      if (q.includes('WHERE EXISTS (SELECT 1 FROM events WHERE id = ?)')) {
        const requiredEventId = this.boundArgs[5] as string;
        whereOk = this.db.events.some((e) => e.id === requiredEventId);
      } else if (q.includes('WHERE NOT EXISTS (SELECT 1 FROM events WHERE id = ?)')) {
        const deletedEventId = this.boundArgs[5] as string;
        const wsUserId = this.boundArgs[6] as string;
        const expectedVersion = this.boundArgs[7] as number;
        const expectedUpdatedAt = this.boundArgs[8] as string;
        const prUserId = this.boundArgs[9] as string;
        const undoneEventId = this.boundArgs[10] as string;
        const ws = this.db.workState.get(wsUserId);
        const alreadyUndone = Array.from(this.db.processedRequests.values()).some((pr) => {
          if (pr.user_id !== prUserId || pr.operation !== 'undo') return false;
          try {
            return (JSON.parse(pr.response_json) as { undoneEventId?: string }).undoneEventId === undoneEventId;
          } catch {
            return false;
          }
        });
        whereOk =
          !this.db.events.some((e) => e.id === deletedEventId) &&
          Boolean(ws && ws.version === expectedVersion && ws.updated_at_utc === expectedUpdatedAt) &&
          !alreadyUndone;
      }

      if (whereOk) {
        if (!this.db.processedRequests.has(requestId)) {
          this.db.processedRequests.set(requestId, {
            request_id: requestId,
            user_id: userId,
            operation,
            response_json: responseJson,
            created_at_utc: createdAtUtc,
          });
          changes = 1;
        } else if (!q.includes('INSERT OR IGNORE')) {
          throw new Error('UNIQUE constraint failed: processed_requests.request_id');
        }
      }
    } else {
      throw new Error(`MockD1Database: unrecognized run() query: ${q}`);
    }

    return {
      success: true,
      meta: { changes } as unknown as D1Response['meta'],
    };
  }
}
