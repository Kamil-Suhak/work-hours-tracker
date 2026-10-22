import type { D1Database, R2Bucket } from '@cloudflare/workers-types';
import type {
  ContractProfile,
  EventRow,
  GenerateReportRequestBody,
  PlannedShiftItem,
  ReportFormat,
  ReportMetadata,
  ReportPreset,
  ReportStats,
  ShiftSummaryItem,
} from '../types';
import { AppError } from '../errors';
import { DEFAULT_USER_ID } from '../clock';
import {
  formatDuration,
  getCurrentWarsawMonthRangeUtc,
  getPreviousWarsawMonthRangeUtc,
  warsawDateRangeToUtc,
} from '../status';
import { formatWarsawDate, generateExcelWorkbook } from './excel_generator';
import { aggregateDailyContractHours, generateContractDocx } from './docx_generator';

export const EXCEL_MIME_TYPE =
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
export const DOCX_MIME_TYPE =
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document';

export function validateReportRequest(
  body: unknown,
  now: Date = new Date()
): GenerateReportRequestBody {
  if (!body || typeof body !== 'object') {
    throw new AppError('VALIDATION_ERROR', 'Request body must be a JSON object.', 400);
  }

  const {
    format: rawFormat,
    startDate,
    endDate,
    preset,
    options,
    plannedShifts: rawPlannedShifts,
  } = body as Record<string, unknown>;

  const format: ReportFormat = rawFormat === 'docx' ? 'docx' : 'xlsx';

  let validatedPlannedShifts: PlannedShiftItem[] | undefined;
  if (rawPlannedShifts !== undefined) {
    if (!Array.isArray(rawPlannedShifts)) {
      throw new AppError('VALIDATION_ERROR', 'plannedShifts must be an array.', 400);
    }
    validatedPlannedShifts = [];
    for (const item of rawPlannedShifts) {
      if (!item || typeof item !== 'object') {
        throw new AppError('VALIDATION_ERROR', 'Each plannedShift must be an object.', 400);
      }
      const { date, durationMinutes } = item as Record<string, unknown>;
      if (typeof date !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(date.trim())) {
        throw new AppError(
          'VALIDATION_ERROR',
          'Each plannedShift date must be in YYYY-MM-DD format.',
          400
        );
      }
      if (
        typeof durationMinutes !== 'number' ||
        !Number.isInteger(durationMinutes) ||
        durationMinutes < 0 ||
        durationMinutes > 1440
      ) {
        throw new AppError(
          'VALIDATION_ERROR',
          'Each plannedShift durationMinutes must be an integer between 0 and 1440.',
          400
        );
      }
      if (durationMinutes > 0) {
        validatedPlannedShifts.push({
          date: date.trim(),
          durationMinutes,
        });
      }
    }
  }

  // Formal .docx reports always use the fixed, full current Warsaw calendar month
  if (format === 'docx') {
    const { startIso, endIso } = getCurrentWarsawMonthRangeUtc(now);
    return {
      format: 'docx',
      startDate: startIso,
      endDate: endIso,
      preset: 'formal',
      ...(validatedPlannedShifts ? { plannedShifts: validatedPlannedShifts } : {}),
    };
  }

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

  const validPreset: ReportPreset = preset === 'formal' ? 'formal' : 'full';

  const validatedOptions =
    options && typeof options === 'object'
      ? {
          includeNotes: Boolean((options as Record<string, unknown>).includeNotes),
          includeStats: Boolean((options as Record<string, unknown>).includeStats),
          includeSource: Boolean((options as Record<string, unknown>).includeSource),
        }
      : {
          includeNotes: true,
          includeStats: true,
          includeSource: true,
        };

  return {
    format: 'xlsx',
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
  endIso: string,
  inclusiveEnd = true
): Promise<EventRow[]> {
  const query = inclusiveEnd
    ? `SELECT * FROM events
       WHERE user_id = ? AND occurred_at_utc >= ? AND occurred_at_utc <= ?
       ORDER BY occurred_at_utc ASC, id ASC`
    : `SELECT * FROM events
       WHERE user_id = ? AND occurred_at_utc >= ? AND occurred_at_utc < ?
       ORDER BY occurred_at_utc ASC, id ASC`;

  const { results } = await db
    .prepare(query)
    .bind(userId, startIso, endIso)
    .all<EventRow>();

  return results ?? [];
}

export async function generateReport(
  db: D1Database,
  userId: string,
  request: GenerateReportRequestBody,
  bucket?: R2Bucket,
  now: Date = new Date()
): Promise<{
  buffer: Uint8Array;
  filename: string;
  contentType: string;
  shifts: ShiftSummaryItem[];
  stats: ReportStats;
}> {
  if (request.format === 'docx') {
    if (!bucket) {
      throw new AppError(
        'STORAGE_NOT_CONFIGURED',
        'Cloud storage bucket is required to load formal .docx templates.',
        503
      );
    }

    const [templateObj, profileObj, signatureObj] = await Promise.all([
      bucket.get('templates/umowa-zlecenie.docx'),
      bucket.get('templates/contract-profile.json'),
      bucket.get('templates/signature.png'),
    ]);

    if (!templateObj) {
      throw new AppError(
        'TEMPLATE_NOT_FOUND',
        'Missing templates/umowa-zlecenie.docx in R2 bucket.',
        404
      );
    }
    if (!profileObj) {
      throw new AppError(
        'TEMPLATE_NOT_FOUND',
        'Missing templates/contract-profile.json in R2 bucket.',
        404
      );
    }
    if (!signatureObj) {
      throw new AppError(
        'TEMPLATE_NOT_FOUND',
        'Missing templates/signature.png in R2 bucket.',
        404
      );
    }

    const [templateBuf, profileText, signatureBuf] = await Promise.all([
      templateObj.arrayBuffer(),
      profileObj.text(),
      signatureObj.arrayBuffer(),
    ]);

    let profile: ContractProfile;
    try {
      profile = JSON.parse(profileText) as ContractProfile;
    } catch {
      throw new AppError(
        'INVALID_TEMPLATE_PROFILE',
        'templates/contract-profile.json is not valid JSON.',
        500
      );
    }

    const { startIso, endIso, monthString } = getCurrentWarsawMonthRangeUtc(now);
    // Include +24h query tail so a shift starting on the last day of the month and ending after midnight pairs with its clock_out
    const queryEndIso = new Date(new Date(endIso).getTime() + 24 * 60 * 60 * 1000).toISOString();
    const events = await fetchEventsForRange(db, userId, startIso, queryEndIso, false);
    const dailyRows = aggregateDailyContractHours(
      events,
      request.plannedShifts ?? [],
      monthString
    );

    const issueDateWarsaw = formatWarsawDate(now);
    const docxBuffer = await generateContractDocx({
      templateDocxBytes: new Uint8Array(templateBuf),
      signaturePngBytes: new Uint8Array(signatureBuf),
      profile,
      dailyRows,
      issueDateWarsaw,
    });

    const totalMinutes = dailyRows.reduce((acc, r) => acc + r.durationMinutes, 0);
    const totalHours = Math.round((totalMinutes / 60) * 100) / 100;
    const avgMinutes = dailyRows.length > 0 ? Math.round(totalMinutes / dailyRows.length) : 0;
    const longestMinutes =
      dailyRows.length > 0 ? Math.max(...dailyRows.map((r) => r.durationMinutes)) : 0;

    return {
      buffer: docxBuffer,
      filename: `zalaczniki-umowa-zlecenie-${monthString}.docx`,
      contentType: DOCX_MIME_TYPE,
      shifts: [],
      stats: {
        totalHours,
        totalHoursFormatted: formatDuration(totalMinutes * 60),
        totalShifts: dailyRows.length,
        totalDays: dailyRows.length,
        averageShiftMinutes: avgMinutes,
        averageShiftFormatted: formatDuration(avgMinutes * 60),
        longestShiftMinutes: longestMinutes,
        longestShiftFormatted: formatDuration(longestMinutes * 60),
      },
    };
  }

  const startDay = request.startDate.slice(0, 10);
  const endDay = request.endDate.slice(0, 10);
  const { startIso: warsawStartIso, endIso: warsawEndIso } = warsawDateRangeToUtc(startDay, endDay);
  const queryEndIso = new Date(new Date(warsawEndIso).getTime() + 24 * 60 * 60 * 1000).toISOString();

  const rawEvents = await fetchEventsForRange(db, userId, warsawStartIso, queryEndIso, false);
  const result = generateExcelWorkbook(
    rawEvents,
    {
      ...request,
      preset: 'full',
      options: { includeNotes: true, includeStats: true, includeSource: true },
    },
    { startDay, endDay }
  );

  const filename = `work-hours-${startDay}-to-${endDay}-full.xlsx`;

  return {
    buffer: result.buffer,
    filename,
    contentType: EXCEL_MIME_TYPE,
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
): Promise<{ fullFilename: string } | null> {
  // Determine previous calendar month range in Europe/Warsaw
  const { startIso, endIso, monthString: monthStr } = getPreviousWarsawMonthRangeUtc(now);
  const queryEndIso = new Date(new Date(endIso).getTime() + 24 * 60 * 60 * 1000).toISOString();

  const events = await fetchEventsForRange(
    db,
    DEFAULT_USER_ID,
    startIso,
    queryEndIso,
    false
  );

  // Generate comprehensive Full Excel report with all fields and summary statistics
  const full = generateExcelWorkbook(
    events,
    {
      startDate: startIso,
      endDate: endIso,
      preset: 'full',
      options: { includeNotes: true, includeStats: true, includeSource: true },
    },
    { monthString: monthStr }
  );

  const fullFilename = `reports/work-hours-${monthStr}-full.xlsx`;

  if (bucket) {
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

  return { fullFilename };
}
