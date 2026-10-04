import { describe, it, expect } from 'vitest';
import type { EventRow } from '../src/types';
import {
  cleanMarkdownForExcel,
  pairEventsIntoReportShifts,
  computeReportStats,
  generateExcelWorkbook,
  computeCrc32,
  sanitizeFormulaCell,
  buildWorksheetXml,
} from '../src/reports/excel_generator';
import { validateReportRequest } from '../src/reports/report_service';
import { getPreviousWarsawMonthRangeUtc, warsawWallClockToUtc } from '../src/status';

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
    // Warsaw is UTC+2 (CEST) on 2026-10-01
    expect(shifts[0].startTimeLocal).toBe('10:00');
    expect(shifts[0].endTimeLocal).toBe('18:30');
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

  it('sanitizeFormulaCell neutralizes formula prefixes with a single quote', () => {
    expect(sanitizeFormulaCell('=SUM(A1:A10)')).toBe("'=SUM(A1:A10)");
    expect(sanitizeFormulaCell('+123456')).toBe("'+123456");
    expect(sanitizeFormulaCell('-5+10')).toBe("'-5+10");
    expect(sanitizeFormulaCell('@cmd|')).toBe("'@cmd|");
    expect(sanitizeFormulaCell('\tmalicious')).toBe("'\tmalicious");
    expect(sanitizeFormulaCell('Safe normal note')).toBe('Safe normal note');
    expect(sanitizeFormulaCell('')).toBe('');
    expect(sanitizeFormulaCell(null)).toBe('');
  });

  it('buildWorksheetXml neutralizes formula-like notes in sheet data', () => {
    const mockShifts = [
      {
        date: '2026-10-01',
        clockInUtc: '2026-10-01T08:00:00Z',
        clockOutUtc: '2026-10-01T16:00:00Z',
        startTimeLocal: '10:00',
        endTimeLocal: '18:00',
        durationMinutes: 480,
        durationHoursDecimal: 8.0,
        durationFormatted: '8h 0m',
        note: '=cmd|\'/C calc\'!A0',
        source: 'flutter_app' as const,
      },
    ];

    const stats = computeReportStats(mockShifts);
    const xml = buildWorksheetXml(mockShifts, stats, 'full');
    expect(xml).toContain("t=\"inlineStr\"><is><t>&apos;=cmd|&apos;/C calc&apos;!A0</t></is>");
  });

  it('warsawWallClockToUtc correctly computes UTC instant for summer (CEST) and winter (CET)', () => {
    // Summer time (CEST): Warsaw is UTC+2
    // 2026-07-01 00:00:00 Warsaw is 2026-06-30 22:00:00 UTC
    const summerUtc = warsawWallClockToUtc(2026, 7, 1, 0, 0, 0);
    expect(summerUtc.toISOString()).toBe('2026-06-30T22:00:00.000Z');

    // Winter time (CET): Warsaw is UTC+1
    // 2026-01-01 00:00:00 Warsaw is 2025-12-31 23:00:00 UTC
    const winterUtc = warsawWallClockToUtc(2026, 1, 1, 0, 0, 0);
    expect(winterUtc.toISOString()).toBe('2025-12-31T23:00:00.000Z');
  });

  it('getPreviousWarsawMonthRangeUtc calculates half-open boundaries for previous month', () => {
    // Simulated cron trigger: 2026-10-01 00:00:00 UTC (which is 02:00:00 CEST in Warsaw)
    // Previous month in Warsaw: September 2026 (2026-09)
    // Start: 2026-09-01 00:00:00 Warsaw -> 2026-08-31T22:00:00.000Z
    // End:   2026-10-01 00:00:00 Warsaw -> 2026-09-30T22:00:00.000Z
    const cronTime = new Date('2026-10-01T00:00:00.000Z');
    const range = getPreviousWarsawMonthRangeUtc(cronTime);

    expect(range.monthString).toBe('2026-09');
    expect(range.startIso).toBe('2026-08-31T22:00:00.000Z');
    expect(range.endIso).toBe('2026-09-30T22:00:00.000Z');

    const janCron = new Date('2026-01-01T00:00:00.000Z');
    const janRange = getPreviousWarsawMonthRangeUtc(janCron);
    expect(janRange.monthString).toBe('2025-12');
    expect(janRange.startIso).toBe('2025-11-30T23:00:00.000Z');
    expect(janRange.endIso).toBe('2025-12-31T23:00:00.000Z');
  });

  it('handles March and October DST transitions correctly for Warsaw wall clock and shift pairing', () => {
    // 1. March transition (CET UTC+1 -> CEST UTC+2)
    // 2026-03-28 is before DST transition (CET, UTC+1)
    const marchBeforeUtc = warsawWallClockToUtc(2026, 3, 28, 9, 0, 0);
    expect(marchBeforeUtc.toISOString()).toBe('2026-03-28T08:00:00.000Z');

    // 2026-03-30 is after DST transition (CEST, UTC+2)
    const marchAfterUtc = warsawWallClockToUtc(2026, 3, 30, 9, 0, 0);
    expect(marchAfterUtc.toISOString()).toBe('2026-03-30T07:00:00.000Z');

    // 2. October transition (CEST UTC+2 -> CET UTC+1)
    // 2026-10-24 is before DST transition (CEST, UTC+2)
    const octBeforeUtc = warsawWallClockToUtc(2026, 10, 24, 9, 0, 0);
    expect(octBeforeUtc.toISOString()).toBe('2026-10-24T07:00:00.000Z');

    // 2026-10-26 is after DST transition (CET, UTC+1)
    const octAfterUtc = warsawWallClockToUtc(2026, 10, 26, 9, 0, 0);
    expect(octAfterUtc.toISOString()).toBe('2026-10-26T08:00:00.000Z');

    // 3. Shift pairing across DST shifts
    const dstEvents: EventRow[] = [
      // Shift on 2026-03-28 (CET): 08:00 UTC - 16:00 UTC -> 09:00 - 17:00 Warsaw
      {
        id: 'evt-m1',
        request_id: 'req-m1',
        user_id: 'default_user',
        device_id: 'dev-1',
        event_type: 'clock_in',
        source: 'flutter_app',
        occurred_at_utc: '2026-03-28T08:00:00.000Z',
        created_at_utc: '2026-03-28T08:00:00.000Z',
        reason: null,
        note: null,
      },
      {
        id: 'evt-m2',
        request_id: 'req-m2',
        user_id: 'default_user',
        device_id: 'dev-1',
        event_type: 'clock_out',
        source: 'flutter_app',
        occurred_at_utc: '2026-03-28T16:00:00.000Z',
        created_at_utc: '2026-03-28T16:00:00.000Z',
        reason: null,
        note: null,
      },
      // Shift on 2026-03-30 (CEST): 07:00 UTC - 15:00 UTC -> 09:00 - 17:00 Warsaw
      {
        id: 'evt-m3',
        request_id: 'req-m3',
        user_id: 'default_user',
        device_id: 'dev-1',
        event_type: 'clock_in',
        source: 'flutter_app',
        occurred_at_utc: '2026-03-30T07:00:00.000Z',
        created_at_utc: '2026-03-30T07:00:00.000Z',
        reason: null,
        note: null,
      },
      {
        id: 'evt-m4',
        request_id: 'req-m4',
        user_id: 'default_user',
        device_id: 'dev-1',
        event_type: 'clock_out',
        source: 'flutter_app',
        occurred_at_utc: '2026-03-30T15:00:00.000Z',
        created_at_utc: '2026-03-30T15:00:00.000Z',
        reason: null,
        note: null,
      },
    ];

    const paired = pairEventsIntoReportShifts(dstEvents);
    expect(paired).toHaveLength(2);

    expect(paired[0].date).toBe('2026-03-28');
    expect(paired[0].startTimeLocal).toBe('09:00');
    expect(paired[0].endTimeLocal).toBe('17:00');

    expect(paired[1].date).toBe('2026-03-30');
    expect(paired[1].startTimeLocal).toBe('09:00');
    expect(paired[1].endTimeLocal).toBe('17:00');
  });
});

