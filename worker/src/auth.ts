import type { Env, DeviceRow } from './types';
import { AppError } from './errors';

export async function hashDeviceToken(token: string, pepper = ''): Promise<string> {
  const encoder = new TextEncoder();
  const data = encoder.encode(token + pepper);
  const hashBuffer = await crypto.subtle.digest('SHA-256', data);
  return Array.from(new Uint8Array(hashBuffer))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

export function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) {
    return false;
  }
  let diff = 0;
  for (let i = 0; i < a.length; i++) {
    diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return diff === 0;
}

export function getBearerToken(request: Request): string | null {
  const authHeader = request.headers.get('Authorization');
  if (!authHeader) {
    return null;
  }
  const match = authHeader.match(/^Bearer\s+(\S+)$/i);
  return match ? match[1].trim() : null;
}

export async function authenticateDevice(
  request: Request,
  env: Env
): Promise<{ deviceId: string }> {
  const token = getBearerToken(request);
  if (!token) {
    throw new AppError('UNAUTHORIZED', 'Missing authorization token.', 401);
  }

  const tokenHash = await hashDeviceToken(token, env.DEVICE_TOKEN_PEPPER ?? '');

  const row = await env.DB.prepare(
    'SELECT id, token_hash, enabled FROM devices WHERE token_hash = ?'
  )
    .bind(tokenHash)
    .first<Pick<DeviceRow, 'id' | 'token_hash' | 'enabled'>>();

  if (!row || !timingSafeEqual(row.token_hash, tokenHash)) {
    throw new AppError('UNAUTHORIZED', 'Invalid device token.', 401);
  }

  if (row.enabled !== 1) {
    throw new AppError('DEVICE_DISABLED', 'This device has been disabled.', 403);
  }

  return { deviceId: row.id };
}

export async function authenticateAdmin(request: Request, env: Env): Promise<void> {
  const adminToken = env.ADMIN_API_TOKEN;
  if (!adminToken) {
    throw new AppError('SERVER_MISCONFIGURED', 'Admin token is not configured on server.', 500);
  }

  const token = getBearerToken(request);
  if (!token || !timingSafeEqual(token, adminToken)) {
    throw new AppError('UNAUTHORIZED', 'Invalid or missing admin token.', 401);
  }
}
