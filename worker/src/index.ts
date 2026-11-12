import type { Env } from './types';
import { AppError, errorResponse, jsonResponse } from './errors';
import { authenticateDevice } from './auth';
import {
  handleClockIn,
  handleClockOut,
  handleUndo,
  handleUpdateTarget,
  materializeAutoClockOutIfDue,
  validateClockRequest,
  validateUndoRequest,
  validateUpdateTargetRequest,
  DEFAULT_USER_ID,
} from './clock';
import { getStatus } from './status';
import {
  handleGetEvents,
  handleUpdateEventNote,
  validateUpdateNoteRequest,
} from './events';
import {
  validateReportRequest,
  generateReport,
  getLatestReport,
  getContractProfile,
  runScheduledMonthlyReport,
} from './reports/report_service';

const MAX_BODY_BYTES = 64 * 1024; // 64 KB

function getCorrelationId(request: Request): string {
  return request.headers.get('cf-ray') ?? crypto.randomUUID();
}

async function parseJsonBody(request: Request, correlationId: string): Promise<unknown> {
  const contentLength = request.headers.get('content-length');
  if (contentLength && parseInt(contentLength, 10) > MAX_BODY_BYTES) {
    throw new AppError('PAYLOAD_TOO_LARGE', 'Request body exceeds size limit.', 413, correlationId);
  }

  const text = await request.text();
  if (text.length > MAX_BODY_BYTES) {
    throw new AppError('PAYLOAD_TOO_LARGE', 'Request body exceeds size limit.', 413, correlationId);
  }

  if (!text.trim()) {
    throw new AppError('VALIDATION_ERROR', 'Request body cannot be empty.', 400, correlationId);
  }

  try {
    return JSON.parse(text);
  } catch {
    throw new AppError('VALIDATION_ERROR', 'Malformed JSON in request body.', 400, correlationId);
  }
}

function safeDecodePathSegment(raw: string, correlationId: string): string {
  try {
    return decodeURIComponent(raw);
  } catch {
    throw new AppError('VALIDATION_ERROR', 'Malformed URL encoding in path segment.', 400, correlationId);
  }
}

function getAllowedOrigin(request: Request, env: Env): string | null {
  const origin = request.headers.get('Origin');
  if (!origin) return null;

  try {
    const originUrl = new URL(origin);
    const requestUrl = new URL(request.url);

    // 1. Same-origin (e.g. Flutter Web hosted on the same worker via ASSETS)
    if (originUrl.origin === requestUrl.origin) {
      return origin;
    }

    // 2. Local development origins
    if (
      originUrl.hostname === 'localhost' ||
      originUrl.hostname === '127.0.0.1' ||
      originUrl.hostname === '[::1]'
    ) {
      return origin;
    }

    // 3. Configured allowed origins (comma-separated list in env)
    if (env.ALLOWED_ORIGINS) {
      const allowed = env.ALLOWED_ORIGINS.split(',').map((o) => o.trim());
      if (allowed.includes(origin)) {
        return origin;
      }
    }
  } catch {
    return null;
  }

  return null;
}

interface ApiRouteContext {
  request: Request;
  env: Env;
  url: URL;
  pathname: string;
  method: string;
  correlationId: string;
  startTime: number;
  standardHeaders: Record<string, string>;
}

type AuthenticatedRouteHandler = (deviceId: string) => Promise<Response>;

/**
 * Matches an API pathname + method to its authenticated route handler so that
 * every matched endpoint passes through device authentication and lazy
 * auto-clock-out materialization in one uniform place.
 */
function matchAuthenticatedApiRoute(ctx: ApiRouteContext): AuthenticatedRouteHandler | null {
  const { request, env, url, pathname, method, correlationId, startTime, standardHeaders } = ctx;

  if (pathname === '/api/v1/status' && method === 'GET') {
    return async (deviceId) => {
      const status = await getStatus(env.DB, DEFAULT_USER_ID);
      console.log(
        JSON.stringify({
          correlationId,
          operation: 'status',
          deviceId,
          latencyMs: Date.now() - startTime,
          result: 'ok',
        })
      );
      return jsonResponse(status, 200, standardHeaders);
    };
  }

  if (pathname === '/api/v1/clock-in' && method === 'POST') {
    return async (deviceId) => {
      const rawBody = await parseJsonBody(request, correlationId);
      const clockReq = validateClockRequest(rawBody);
      const result = await handleClockIn(env.DB, deviceId, clockReq);

      console.log(
        JSON.stringify({
          correlationId,
          operation: 'clock-in',
          deviceId,
          source: clockReq.source,
          changed: result.changed,
          latencyMs: Date.now() - startTime,
          result: result.changed ? 'changed' : 'no_change',
        })
      );

      return jsonResponse(result, 200, standardHeaders);
    };
  }

  if (pathname === '/api/v1/clock-out' && method === 'POST') {
    return async (deviceId) => {
      const rawBody = await parseJsonBody(request, correlationId);
      const clockReq = validateClockRequest(rawBody);
      const result = await handleClockOut(env.DB, deviceId, clockReq);

      console.log(
        JSON.stringify({
          correlationId,
          operation: 'clock-out',
          deviceId,
          source: clockReq.source,
          changed: result.changed,
          latencyMs: Date.now() - startTime,
          result: result.changed ? 'changed' : 'no_change',
        })
      );

      return jsonResponse(result, 200, standardHeaders);
    };
  }

  if (pathname === '/api/v1/shift/target' && method === 'PATCH') {
    return async (deviceId) => {
      const rawBody = await parseJsonBody(request, correlationId);
      const targetReq = validateUpdateTargetRequest(rawBody);
      const result = await handleUpdateTarget(env.DB, targetReq);

      console.log(
        JSON.stringify({
          correlationId,
          operation: 'update-shift-target',
          deviceId,
          targetClockOutUtc: result.targetClockOutUtc,
          latencyMs: Date.now() - startTime,
          result: 'ok',
        })
      );

      return jsonResponse(result, 200, standardHeaders);
    };
  }

  if (pathname === '/api/v1/undo' && method === 'POST') {
    return async (deviceId) => {
      const rawBody = await parseJsonBody(request, correlationId);
      const undoReq = validateUndoRequest(rawBody);
      const result = await handleUndo(env.DB, undoReq);

      console.log(
        JSON.stringify({
          correlationId,
          operation: 'undo',
          deviceId,
          undoneEventId: result.undoneEventId,
          restoredState: result.restoredState,
          latencyMs: Date.now() - startTime,
          result: 'ok',
        })
      );

      return jsonResponse(result, 200, standardHeaders);
    };
  }

  if (pathname === '/api/v1/events' && method === 'GET') {
    return async (deviceId) => {
      const events = await handleGetEvents(env.DB, DEFAULT_USER_ID, url);

      console.log(
        JSON.stringify({
          correlationId,
          operation: 'get-events',
          deviceId,
          count: events.length,
          latencyMs: Date.now() - startTime,
          result: 'ok',
        })
      );

      return jsonResponse(events, 200, standardHeaders);
    };
  }

  const eventNoteMatch = pathname.match(/^\/api\/v1\/events\/([^/]+)\/note$/);
  if (eventNoteMatch && (method === 'PATCH' || method === 'POST')) {
    return async (deviceId) => {
      const eventId = safeDecodePathSegment(eventNoteMatch[1], correlationId);
      const rawBody = await parseJsonBody(request, correlationId);
      const { note } = validateUpdateNoteRequest(rawBody);
      const result = await handleUpdateEventNote(env.DB, DEFAULT_USER_ID, eventId, note);

      console.log(
        JSON.stringify({
          correlationId,
          operation: 'update-event-note',
          deviceId,
          eventId,
          hasNote: Boolean(note),
          latencyMs: Date.now() - startTime,
          result: 'ok',
        })
      );

      return jsonResponse(result, 200, standardHeaders);
    };
  }

  if (pathname === '/api/v1/reports/generate' && method === 'POST') {
    return async (deviceId) => {
      const rawBody = await parseJsonBody(request, correlationId);
      const reportReq = validateReportRequest(rawBody);
      const reportResult = await generateReport(
        env.DB,
        DEFAULT_USER_ID,
        reportReq,
        env.REPORTS_BUCKET
      );

      console.log(
        JSON.stringify({
          correlationId,
          operation: 'generate-report',
          deviceId,
          format: reportReq.format ?? 'xlsx',
          preset: reportReq.preset,
          totalHours: reportResult.stats.totalHours,
          shiftsCount: reportResult.stats.totalShifts,
          latencyMs: Date.now() - startTime,
          result: 'ok',
        })
      );

      return new Response(reportResult.buffer, {
        status: 200,
        headers: {
          ...standardHeaders,
          'Content-Type': reportResult.contentType,
          'Content-Disposition': `attachment; filename="${reportResult.filename}"`,
          'X-Total-Hours': reportResult.stats.totalHours.toString(),
          'X-Total-Shifts': reportResult.stats.totalShifts.toString(),
        },
      });
    };
  }

  if (pathname === '/api/v1/reports/latest' && method === 'GET') {
    return async (deviceId) => {
      const latest = await getLatestReport(env.REPORTS_BUCKET);

      if (!latest) {
        throw new AppError(
          'NO_REPORTS_FOUND',
          'No automated reports have been generated yet.',
          404,
          correlationId
        );
      }

      console.log(
        JSON.stringify({
          correlationId,
          operation: 'get-latest-report',
          deviceId,
          filename: latest.filename,
          latencyMs: Date.now() - startTime,
          result: 'ok',
        })
      );

      return jsonResponse(latest, 200, standardHeaders);
    };
  }

  if (pathname === '/api/v1/reports/contract-profile' && method === 'GET') {
    return async (deviceId) => {
      const profile = await getContractProfile(env.REPORTS_BUCKET);

      console.log(
        JSON.stringify({
          correlationId,
          operation: 'get-contract-profile',
          deviceId,
          monthlyHours: profile?.monthlyHours ?? 80,
          latencyMs: Date.now() - startTime,
          result: 'ok',
        })
      );

      return jsonResponse(profile ?? { monthlyHours: 80 }, 200, standardHeaders);
    };
  }

  if (pathname.startsWith('/api/v1/reports/download/') && method === 'GET') {
    return async (deviceId) => {
      if (!env.REPORTS_BUCKET) {
        throw new AppError(
          'STORAGE_NOT_CONFIGURED',
          'Cloud storage bucket is not configured on the server.',
          503,
          correlationId
        );
      }

      const rawFilename = pathname.replace('/api/v1/reports/download/', '');
      const filename = safeDecodePathSegment(rawFilename, correlationId).trim();

      // Reject directory traversal or path separators
      if (filename.includes('/') || filename.includes('\\') || filename.includes('..')) {
        throw new AppError('INVALID_FILENAME', 'Invalid report filename requested.', 400, correlationId);
      }

      // Strict filename validation:
      // Matches work-hours-YYYY-MM-(formal|full).xlsx or work-hours-YYYY-MM-DD-to-YYYY-MM-DD-(formal|full).xlsx
      const SAFE_REPORT_FILENAME_REGEX =
        /^work-hours-(?:\d{4}-\d{2}|\d{4}-\d{2}-\d{2}-to-\d{4}-\d{2}-\d{2})-(?:formal|full)\.xlsx$/;
      if (!SAFE_REPORT_FILENAME_REGEX.test(filename)) {
        throw new AppError('INVALID_FILENAME', 'Invalid report filename requested.', 400, correlationId);
      }

      const key = `reports/${filename}`;
      const object = await env.REPORTS_BUCKET.get(key);

      if (!object) {
        throw new AppError('REPORT_NOT_FOUND', 'Requested report file was not found.', 404, correlationId);
      }

      console.log(
        JSON.stringify({
          correlationId,
          operation: 'download-report',
          deviceId,
          key,
          latencyMs: Date.now() - startTime,
          result: 'ok',
        })
      );

      return new Response(object.body, {
        status: 200,
        headers: {
          ...standardHeaders,
          'Content-Type': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          'Content-Disposition': `attachment; filename="${filename}"`,
        },
      });
    };
  }

  return null;
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const startTime = Date.now();
    const correlationId = getCorrelationId(request);
    const url = new URL(request.url);
    const pathname = url.pathname;
    const method = request.method.toUpperCase();

    // Serve static frontend assets for non-API routes when ASSETS binding is available
    if (!pathname.startsWith('/api/') && env.ASSETS) {
      return env.ASSETS.fetch(request);
    }

    const allowedOrigin = getAllowedOrigin(request, env);

    const standardHeaders: Record<string, string> = {
      'X-Correlation-ID': correlationId,
      'X-Content-Type-Options': 'nosniff',
      'Referrer-Policy': 'strict-origin-when-cross-origin',
      'Vary': 'Origin',
      'Cache-Control': 'no-store, no-cache, must-revalidate',
      'Access-Control-Allow-Methods': 'GET, POST, PATCH, OPTIONS',
      'Access-Control-Allow-Headers': 'Authorization, Content-Type, X-Correlation-ID',
      'Access-Control-Expose-Headers':
        'Content-Disposition, X-Total-Hours, X-Total-Shifts, X-Correlation-ID',
    };

    if (allowedOrigin) {
      standardHeaders['Access-Control-Allow-Origin'] = allowedOrigin;
    }

    if (method === 'OPTIONS') {
      return new Response(null, {
        status: 204,
        headers: standardHeaders,
      });
    }

    try {
      const { deviceId } = await authenticateDevice(request, env);

      const routeHandler = matchAuthenticatedApiRoute({
        request,
        env,
        url,
        pathname,
        method,
        correlationId,
        startTime,
        standardHeaders,
      });

      if (!routeHandler) {
        return errorResponse('NOT_FOUND', 'The requested resource was not found.', 404, correlationId, standardHeaders);
      }

      const autoStopped = await materializeAutoClockOutIfDue(env.DB, DEFAULT_USER_ID);
      if (autoStopped) {
        console.log(
          JSON.stringify({
            correlationId,
            operation: 'auto-clock-out',
            deviceId,
            userId: DEFAULT_USER_ID,
          })
        );
      }

      return await routeHandler(deviceId);
    } catch (err: unknown) {
      const latencyMs = Date.now() - startTime;
      if (err instanceof AppError) {
        console.warn(
          JSON.stringify({
            correlationId,
            pathname,
            method,
            code: err.code,
            status: err.status,
            latencyMs,
          })
        );
        return errorResponse(err.code, err.message, err.status, err.requestId ?? correlationId, standardHeaders);
      }

      console.error(
        JSON.stringify({
          correlationId,
          pathname,
          method,
          latencyMs,
          error: 'Unhandled server error',
        })
      );
      return errorResponse('INTERNAL_ERROR', 'An unexpected error occurred.', 500, correlationId, standardHeaders);
    }
  },

  async scheduled(
    event: { cron: string; scheduledTime: number },
    env: Env,
    ctx: { waitUntil: (promise: Promise<unknown>) => void }
  ): Promise<void> {
    ctx.waitUntil(
      materializeAutoClockOutIfDue(env.DB, DEFAULT_USER_ID)
        .then((autoStopped) => {
          if (autoStopped) {
            console.log(
              JSON.stringify({
                operation: 'auto-clock-out',
                trigger: 'scheduled',
                cron: event.cron,
                scheduledTime: event.scheduledTime,
                userId: DEFAULT_USER_ID,
              })
            );
          }
          return runScheduledMonthlyReport(env.DB, env.REPORTS_BUCKET);
        })
        .then((res) => {
          console.log(
            JSON.stringify({
              operation: 'scheduled-monthly-report',
              cron: event.cron,
              scheduledTime: event.scheduledTime,
              result: res ? 'ok' : 'skipped',
            })
          );
        })
        .catch((err) => {
          console.error(
            JSON.stringify({
              operation: 'scheduled-monthly-report',
              error: err instanceof Error ? err.message : String(err),
            })
          );
        })
    );
  },
};
