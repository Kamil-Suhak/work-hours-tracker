import type { Env } from './types';
import { AppError, errorResponse, jsonResponse } from './errors';
import { authenticateDevice, authenticateAdmin } from './auth';
import {
  handleClockIn,
  handleClockOut,
  validateClockRequest,
  DEFAULT_USER_ID,
} from './clock';
import { getStatus } from './status';
import {
  handleGetEvents,
  handleAdminManualEvent,
  validateManualEventRequest,
} from './events';

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

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const startTime = Date.now();
    const correlationId = getCorrelationId(request);
    const url = new URL(request.url);
    const pathname = url.pathname;
    const method = request.method.toUpperCase();

    // Restrictive CORS headers for API clients
    const standardHeaders = {
      'X-Correlation-ID': correlationId,
    };

    if (method === 'OPTIONS') {
      return new Response(null, {
        status: 204,
        headers: {
          ...standardHeaders,
          'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
          'Access-Control-Allow-Headers': 'Authorization, Content-Type',
        },
      });
    }

    try {
      if (pathname === '/api/v1/status' && method === 'GET') {
        const { deviceId } = await authenticateDevice(request, env);
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
      }

      if (pathname === '/api/v1/clock-in' && method === 'POST') {
        const { deviceId } = await authenticateDevice(request, env);
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
      }

      if (pathname === '/api/v1/clock-out' && method === 'POST') {
        const { deviceId } = await authenticateDevice(request, env);
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
      }

      if (pathname === '/api/v1/events' && method === 'GET') {
        const { deviceId } = await authenticateDevice(request, env);
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
      }

      if (pathname === '/api/v1/admin/events/manual' && method === 'POST') {
        await authenticateAdmin(request, env);
        const rawBody = await parseJsonBody(request, correlationId);
        const manualReq = validateManualEventRequest(rawBody);
        const result = await handleAdminManualEvent(env.DB, manualReq);

        console.log(
          JSON.stringify({
            correlationId,
            operation: 'admin-manual-event',
            clockInAt: manualReq.clockInAt,
            clockOutAt: manualReq.clockOutAt,
            latencyMs: Date.now() - startTime,
            result: 'ok',
          })
        );

        return jsonResponse(result, 200, standardHeaders);
      }

      return errorResponse('NOT_FOUND', 'The requested resource was not found.', 404, correlationId);
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
        return errorResponse(err.code, err.message, err.status, err.requestId ?? correlationId);
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
      return errorResponse('INTERNAL_ERROR', 'An unexpected error occurred.', 500, correlationId);
    }
  },
};
