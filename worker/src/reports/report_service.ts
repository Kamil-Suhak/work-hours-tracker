import type { D1Database, R2Bucket } from '@cloudflare/workers-types';
import type {
  EventRow,
  GenerateReportRequestBody,
  ReportMetadata,
  ReportPreset,
  ReportStats,
  ShiftSummaryItem,
} from '../types';
import { AppError } from '../errors';
import { DEFAULT_USER_ID } from '../clock';
import { generateExcelWorkbook } from './excel_generator';

export function validateReportRequest(body: unknown): GenerateReportRequestBody {
  if (!body || typeof body !== 'object') {
    throw new AppError('VALIDATION_ERROR', 'Request body must be a JSON object.', 400);
  }

  const { startDate, endDate, preset, options } = body as Record<string, unknown>;

  if (typeof startDate !== 'string' || !startDate.trim()) {
    throw new AppError('VALIDATION_ERROR', 'startDate is required.', 400);
  }

  if (typeof endDate !== 'string' || !endDate.trim()) {
    throw new AppError('VALIDATION_ERROR', 'endDate is required.', 400);
  }

  const startParsed = new Date(startDate.includes('T') ? startDate : `${startDate}T00:00:00.000Z`);
  const endParsed = new Date(endDate.includes('T') ? endDate : `${endDate}T23:59:59.999Z`);

  if (isNaN(startParsed.getTime()) || isNaN(endParsed.getTime())) {
    throw new AppError('VALIDATION_ERROR', 'startDate and endDate must be valid dates.', 400);
  }

  if (endParsed.getTime() < startParsed.getTime()) {
    throw new AppError('INVALID_DATE_RANGE', 'endDate must be on or after startDate.', 400);
  }

  const validPreset: ReportPreset = preset === 'full' ? 'full' : 'formal';

  const validatedOptions = options && typeof options === 'object'
    ? {
        includeNotes: Boolean((options as Record<string, unknown>).includeNotes),
        includeStats: Boolean((options as Record<string, unknown>).includeStats),
        includeSource: Boolean((options as Record<string, unknown>).includeSource),
      }
    : undefined;

  return {
    startDate: startParsed.toISOString(),
    endDate: endParsed.toISOString(),
    preset: validPreset,
    options: validatedOptions,
  };
}

export async function fetchEventsForRange(
  db: D1Database,
  userId: string,
  startIso: string,
  endIso: string
): Promise<EventRow[]> {
  const { results } = await db
    .prepare(
      `SELECT * FROM events
       WHERE user_id = ? AND occurred_at_utc >= ? AND occurred_at_utc <= ?
       ORDER BY occurred_at_utc ASC, id ASC`
    )
    .bind(userId, startIso, endIso)
    .all<EventRow>();

  return results ?? [];
}

export async function generateReport(
  db: D1Database,
  userId: string,
  request: GenerateReportRequestBody
): Promise<{
  buffer: Uint8Array;
  filename: string;
  shifts: ShiftSummaryItem[];
  stats: ReportStats;
}> {
  const events = await fetchEventsForRange(db, userId, request.startDate, request.endDate);
  const result = generateExcelWorkbook(events, request);

  const startDay = request.startDate.slice(0, 10);
  const endDay = request.endDate.slice(0, 10);
  const filename = `work-hours-${startDay}-to-${endDay}-${request.preset}.xlsx`;

  return {
    buffer: result.buffer,
    filename,
    shifts: result.shifts,
    stats: result.stats,
  };
}

export async function saveReportToR2(
  bucket: R2Bucket,
  filename: string,
  buffer: Uint8Array,
  customMetadata: Record<string, string> = {}
): Promise<void> {
  await bucket.put(filename, buffer, {
    httpMetadata: {
      contentType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      contentDisposition: `attachment; filename="${filename.split('/').pop()}"`,
    },
    customMetadata,
  });
}

export async function getLatestReport(
  bucket?: R2Bucket
): Promise<ReportMetadata | null> {
  if (!bucket) {
    return null;
  }

  // 1. Try reading metadata index pointer
  const indexObj = await bucket.get('reports/latest.json');
  if (indexObj) {
    const text = await indexObj.text();
    try {
      return JSON.parse(text) as ReportMetadata;
    } catch (_) {}
  }

  // 2. Fallback: list objects under reports/ and pick newest
  const listing = await bucket.list({ prefix: 'reports/', limit: 20 });
  const xlsxFiles = listing.objects.filter((obj) => obj.key.endsWith('.xlsx'));
  if (xlsxFiles.length === 0) {
    return null;
  }

  xlsxFiles.sort((a, b) => b.uploaded.getTime() - a.uploaded.getTime());
  const newest = xlsxFiles[0];
  const filename = newest.key;
  const monthMatch = filename.match(/\d{4}-\d{2}/);

  return {
    filename,
    sizeBytes: newest.size,
    uploadedAtUtc: newest.uploaded.toISOString(),
    preset: filename.includes('formal') ? 'formal' : 'full',
    month: monthMatch ? monthMatch[0] : 'Unknown',
  };
}

export async function runScheduledMonthlyReport(
  db: D1Database,
  bucket?: R2Bucket,
  now: Date = new Date()
): Promise<{ formalFilename: string; fullFilename: string } | null> {
  // Determine previous month range in UTC
  const year = now.getUTCFullYear();
  const month = now.getUTCMonth(); // 0-indexed: current month
  // Previous month start: day 1 of month - 1
  const prevMonthStart = new Date(Date.UTC(year, month - 1, 1, 0, 0, 0, 0));
  // Previous month end: day 0 of current month at 23:59:59.999
  const prevMonthEnd = new Date(Date.UTC(year, month, 0, 23, 59, 59, 999));

  const monthStr = prevMonthStart.toISOString().slice(0, 7); // YYYY-MM
  const events = await fetchEventsForRange(
    db,
    DEFAULT_USER_ID,
    prevMonthStart.toISOString(),
    prevMonthEnd.toISOString()
  );

  // Generate Formal report
  const formal = generateExcelWorkbook(events, {
    startDate: prevMonthStart.toISOString(),
    endDate: prevMonthEnd.toISOString(),
    preset: 'formal',
  });

  // Generate Full report
  const full = generateExcelWorkbook(events, {
    startDate: prevMonthStart.toISOString(),
    endDate: prevMonthEnd.toISOString(),
    preset: 'full',
    options: { includeNotes: true, includeStats: true, includeSource: true },
  });

  const formalFilename = `reports/work-hours-${monthStr}-formal.xlsx`;
  const fullFilename = `reports/work-hours-${monthStr}-full.xlsx`;

  if (bucket) {
    await saveReportToR2(bucket, formalFilename, formal.buffer, {
      preset: 'formal',
      month: monthStr,
      shifts: String(formal.shifts.length),
      totalHours: String(formal.stats.totalHours),
    });

    await saveReportToR2(bucket, fullFilename, full.buffer, {
      preset: 'full',
      month: monthStr,
      shifts: String(full.shifts.length),
      totalHours: String(full.stats.totalHours),
    });

    // Update latest.json metadata pointer
    const latestMeta: ReportMetadata = {
      filename: fullFilename,
      sizeBytes: full.buffer.length,
      uploadedAtUtc: new Date().toISOString(),
      preset: 'full',
      month: monthStr,
    };

    await bucket.put('reports/latest.json', JSON.stringify(latestMeta), {
      httpMetadata: { contentType: 'application/json' },
    });
  }

  return { formalFilename, fullFilename };
}
