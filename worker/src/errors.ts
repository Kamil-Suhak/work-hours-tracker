import type { ApiErrorResponse } from './types';

export class AppError extends Error {
  constructor(
    public readonly code: string,
    message: string,
    public readonly status: number = 400,
    public readonly requestId?: string
  ) {
    super(message);
    this.name = 'AppError';
  }
}

export function jsonResponse<T>(data: T, status = 200, headers: HeadersInit = {}): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      'Content-Type': 'application/json',
      ...headers,
    },
  });
}

export function errorResponse(
  code: string,
  message: string,
  status = 400,
  requestId?: string
): Response {
  const payload: ApiErrorResponse = {
    error: {
      code,
      message,
      ...(requestId ? { requestId } : {}),
    },
  };
  return jsonResponse(payload, status);
}
