import { describe, it, expect } from 'vitest';
import { hashDeviceToken, timingSafeEqual, getBearerToken } from '../src/auth';

describe('Authentication & Token Security', () => {
  it('hashes device token using SHA-256', async () => {
    const hash1 = await hashDeviceToken('test-token');
    const hash2 = await hashDeviceToken('test-token');
    expect(hash1).toHaveLength(64);
    expect(hash1).toBe(hash2);

    const hashWithPepper = await hashDeviceToken('test-token', 'my-pepper');
    expect(hashWithPepper).not.toBe(hash1);
  });

  it('performs constant-time comparison correctly', () => {
    expect(timingSafeEqual('abcdef', 'abcdef')).toBe(true);
    expect(timingSafeEqual('abcdef', 'abcdeg')).toBe(false);
    expect(timingSafeEqual('abcdef', 'abcde')).toBe(false);
  });

  it('extracts Bearer tokens from authorization header', () => {
    const req1 = new Request('http://localhost', {
      headers: { Authorization: 'Bearer my-device-token-123' },
    });
    expect(getBearerToken(req1)).toBe('my-device-token-123');

    const req2 = new Request('http://localhost', {
      headers: { Authorization: 'Basic dXNlcjpwYXNz' },
    });
    expect(getBearerToken(req2)).toBeNull();

    const req3 = new Request('http://localhost');
    expect(getBearerToken(req3)).toBeNull();
  });
});
