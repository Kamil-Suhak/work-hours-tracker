import { describe, it, expect } from 'vitest';
import type { EventRow } from '../src/types';
import {
  cleanMarkdownForExcel,
  pairEventsIntoReportShifts,
  computeReportStats,
  generateExcelWorkbook,
  computeCrc32,
} from '../src/reports/excel_generator';
import { validateReportRequest } from '../src/reports/report_service';

describe('Reports Engine Unit Tests', () => {
  it('cleanMarkdownForExcel strips headings, bullet markers, and formatting', () => {
    const raw = '# Daily Notes\n- Fixed bug in auth\n- **Deployed** updates\n*Reviewed* PRs';
    const cleaned = cleanMarkdownForExcel(raw);
    expect(cleaned).toBe('Daily Notes; • Fixed bug in auth; • Deployed updates; Reviewed PRs');
  });

  it('pairEventsIntoReportShifts pairs clock-in and clock-out events correctly', () => {
    const mockEvents: EventRow[] = [
      {
        id: 'evt-1',
        request_id: 'req-1',
        user_id: 'default_user',
        device_id: 'dev-1',
        event_type: 'clock_in',
        source: 'flutter_app',
        occurred_at_utc: '2026-10-01T08:00:00.000Z',
        created_at_utc: '2026-10-01T08:00:00.000Z',
        reason: null,
        note: null,
      },
      {
        id: 'evt-2',
        request_id: 'req-2',
        user_id: 'default_user',
        device_id: 'dev-1',
        event_type: 'clock_out',
        source: 'flutter_app',
        occurred_at_utc: '2026-10-01T16:30:00.000Z',
        created_at_utc: '2026-10-01T16:30:00.000Z',
        reason: null,
        note: '- Wrapped up sprint tasks',
      },
    ];

    const shifts = pairEventsIntoReportShifts(mockEvents);
    expect(shifts).toHaveLength(1);
    expect(shifts[0].date).toBe('2026-10-01');
    expect(shifts[0].startTimeLocal).toBe('08:00');
    expect(shifts[0].endTimeLocal).toBe('16:30');
    expect(shifts[0].durationMinutes).toBe(510);
    expect(shifts[0].durationHoursDecimal).toBe(8.5);
    expect(shifts[0].durationFormatted).toBe('8h 30m');
    expect(shifts[0].note).toBe('• Wrapped up sprint tasks');
    expect(shifts[0].source).toBe('flutter_app');
  });

  it('computeReportStats computes totals and averages across shifts', () => {
    const mockShifts = [
      {
        date: '2026-10-01',
        clockInUtc: '2026-10-01T08:00:00Z',
        clockOutUtc: '2026-10-01T16:00:00Z',
        startTimeLocal: '08:00',
        endTimeLocal: '16:00',
        durationMinutes: 480,
        durationHoursDecimal: 8.0,
        durationFormatted: '8h 0m',
        source: 'flutter_app' as const,
      },
      {
        date: '2026-10-02',
        clockInUtc: '2026-10-02T08:00:00Z',
        clockOutUtc: '2026-10-02T12:00:00Z',
        startTimeLocal: '08:00',
        endTimeLocal: '12:00',
        durationMinutes: 240,
        durationHoursDecimal: 4.0,
        durationFormatted: '4h 0m',
        source: 'android_widget' as const,
      },
    ];

    const stats = computeReportStats(mockShifts);
    expect(stats.totalHours).toBe(12.0);
    expect(stats.totalHoursFormatted).toBe('12h 0m');
    expect(stats.totalShifts).toBe(2);
    expect(stats.totalDays).toBe(2);
    expect(stats.averageShiftMinutes).toBe(360);
    expect(stats.averageShiftFormatted).toBe('6h 0m');
    expect(stats.longestShiftMinutes).toBe(480);
    expect(stats.longestShiftFormatted).toBe('8h 0m');
  });

  it('generateExcelWorkbook produces valid OpenXML ZIP buffer for Formal preset', () => {
    const mockEvents: EventRow[] = [
      {
        id: 'evt-1',
        request_id: 'req-1',
        user_id: 'default_user',
        device_id: 'dev-1',
        event_type: 'clock_in',
        source: 'flutter_app',
        occurred_at_utc: '2026-10-01T09:00:00.000Z',
        created_at_utc: '2026-10-01T09:00:00.000Z',
        reason: null,
        note: null,
      },
      {
        id: 'evt-2',
        request_id: 'req-2',
        user_id: 'default_user',
        device_id: 'dev-1',
        event_type: 'clock_out',
        source: 'flutter_app',
        occurred_at_utc: '2026-10-01T17:00:00.000Z',
        created_at_utc: '2026-10-01T17:00:00.000Z',
        reason: null,
        note: null,
      },
    ];

    const result = generateExcelWorkbook(mockEvents, {
      startDate: '2026-10-01T00:00:00.000Z',
      endDate: '2026-10-31T23:59:59.999Z',
      preset: 'formal',
    });

    expect(result.shifts).toHaveLength(1);
    expect(result.buffer).toBeInstanceOf(Uint8Array);
    expect(result.buffer.length).toBeGreaterThan(100);

    // Verify standard ZIP magic bytes: 'PK\x03\x04'
    expect(result.buffer[0]).toBe(0x50);
    expect(result.buffer[1]).toBe(0x4b);
    expect(result.buffer[2]).toBe(0x03);
    expect(result.buffer[3]).toBe(0x04);
  });

  it('generateExcelWorkbook produces valid Full preset with notes and stats', () => {
    const mockEvents: EventRow[] = [
      {
        id: 'evt-1',
        request_id: 'req-1',
        user_id: 'default_user',
        device_id: 'dev-1',
        event_type: 'clock_in',
        source: 'flutter_app',
        occurred_at_utc: '2026-10-01T09:00:00.000Z',
        created_at_utc: '2026-10-01T09:00:00.000Z',
        reason: null,
        note: null,
      },
      {
        id: 'evt-2',
        request_id: 'req-2',
        user_id: 'default_user',
        device_id: 'dev-1',
        event_type: 'clock_out',
        source: 'flutter_app',
        occurred_at_utc: '2026-10-01T17:00:00.000Z',
        created_at_utc: '2026-10-01T17:00:00.000Z',
        reason: null,
        note: 'Customer meeting and architecture review',
      },
    ];

    const result = generateExcelWorkbook(mockEvents, {
      startDate: '2026-10-01T00:00:00.000Z',
      endDate: '2026-10-31T23:59:59.999Z',
      preset: 'full',
      options: { includeNotes: true, includeStats: true, includeSource: true },
    });

    expect(result.shifts).toHaveLength(1);
    expect(result.shifts[0].note).toBe('Customer meeting and architecture review');
    expect(result.buffer.length).toBeGreaterThan(200);
  });

  it('validateReportRequest validates and defaults parameters', () => {
    const valid = validateReportRequest({
      startDate: '2026-10-01',
      endDate: '2026-10-31',
      preset: 'formal',
      options: { includeNotes: true },
    });

    expect(valid.preset).toBe('formal');
    expect(valid.startDate).toContain('2026-10-01');
    expect(valid.endDate).toContain('2026-10-31');
    expect(valid.options?.includeNotes).toBe(true);

    // Rejects invalid date
    expect(() =>
      validateReportRequest({
        startDate: 'not-a-date',
        endDate: '2026-10-31',
        preset: 'formal',
      })
    ).toThrowError(/valid dates/);

    // Rejects backwards range
    expect(() =>
      validateReportRequest({
        startDate: '2026-10-31',
        endDate: '2026-10-01',
        preset: 'formal',
      })
    ).toThrowError(/on or after/);
  });

  it('computeCrc32 calculates expected checksum', () => {
    const testData = new TextEncoder().encode('123456789');
    const crc = computeCrc32(testData);
    // Standard CRC-32 for "123456789" is 0xcbf43926 (3421780262)
    expect(crc).toBe(0xcbf43926);
  });
});
