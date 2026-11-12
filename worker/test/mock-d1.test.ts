import { describe, expect, it } from 'vitest';
import { MockD1Database } from './mock-d1';

describe('MockD1Database strict SQL guards', () => {
  it('throws on unrecognized queries across first(), all(), and run()', async () => {
    const db = new MockD1Database();
    await expect(db.prepare('SELECT * FROM unknown_table WHERE id = ?').bind('1').first()).rejects.toThrow(
      /unrecognized first\(\) query/
    );
    await expect(db.prepare('SELECT * FROM unknown_table').all()).rejects.toThrow(/unrecognized all\(\) query/);
    await expect(db.prepare('DELETE FROM unknown_table WHERE id = ?').bind('1').run()).rejects.toThrow(
      /unrecognized run\(\) query/
    );
  });

  it('throws on bind placeholder count mismatch', async () => {
    const db = new MockD1Database();
    await expect(db.prepare('SELECT * FROM work_state WHERE user_id = ?').first()).rejects.toThrow(
      /bind count mismatch/
    );
    await expect(
      db.prepare('SELECT * FROM work_state WHERE user_id = ?').bind('u1', 'extra').first()
    ).rejects.toThrow(/bind count mismatch/);
  });

  it('breaks equal occurred_at_utc and created_at_utc ties using insertion order (rowid)', async () => {
    const db = new MockD1Database();
    db.events.push(
      {
        id: 'evt-first',
        request_id: 'req-1',
        user_id: 'u1',
        device_id: 'd1',
        event_type: 'clock_in',
        source: 'flutter_app',
        occurred_at_utc: '2026-10-03T08:00:00.000Z',
        created_at_utc: '2026-10-03T08:00:00.000Z',
        reason: null,
        note: null,
        location: 'remote',
      },
      {
        id: 'evt-second',
        request_id: 'req-2',
        user_id: 'u1',
        device_id: 'd1',
        event_type: 'clock_out',
        source: 'flutter_app',
        occurred_at_utc: '2026-10-03T08:00:00.000Z',
        created_at_utc: '2026-10-03T08:00:00.000Z',
        reason: null,
        note: null,
        location: 'remote',
      }
    );

    const asc = await db
      .prepare(
        `SELECT *
         FROM   events
         WHERE  user_id = ? AND occurred_at_utc >= ?
         ORDER BY occurred_at_utc ASC, created_at_utc ASC, rowid ASC`
      )
      .bind('u1', '2026-10-01T00:00:00.000Z')
      .all<{ id: string }>();
    expect(asc.results.map((r) => r.id)).toEqual(['evt-first', 'evt-second']);

    const latest = await db
      .prepare('SELECT * FROM events WHERE user_id = ? ORDER BY occurred_at_utc DESC, created_at_utc DESC, rowid DESC')
      .bind('u1')
      .first<{ id: string }>();
    expect(latest?.id).toBe('evt-second');
  });
});
