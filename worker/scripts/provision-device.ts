/**
 * Helper script to generate a secure random device token and its database record.
 * Run with: npx tsx scripts/provision-device.ts <device-name> [pepper]
 */
import { randomBytes, createHash } from 'node:crypto';

const deviceName = process.argv[2] || 'android-primary';
const pepper = process.argv[3] || process.env.DEVICE_TOKEN_PEPPER || '';

const tokenBytes = randomBytes(32);
const deviceToken = tokenBytes.toString('hex');

const hash = createHash('sha256').update(deviceToken + pepper).digest('hex');
const deviceId = randomBytes(16).toString('hex');
const nowIso = new Date().toISOString();

console.log('=== Device Provisioning ===');
console.log(`Device ID:    ${deviceId}`);
console.log(`Device Name:  ${deviceName}`);
console.log(`Bearer Token: ${deviceToken}`);
console.log('\n[CRITICAL] Save this Bearer Token in your client / Android secure storage now.');
console.log('It will NEVER be shown again and is NOT stored in the database.\n');

console.log('SQL to insert into D1:');
console.log(
  `INSERT INTO devices (id, name, token_hash, enabled, created_at_utc) VALUES ('${deviceId}', '${deviceName}', '${hash}', 1, '${nowIso}');\n`
);

console.log('Wrangler command (local):');
console.log(
  `npx wrangler d1 execute work-hours-prod --local --command "INSERT INTO devices (id, name, token_hash, enabled, created_at_utc) VALUES ('${deviceId}', '${deviceName}', '${hash}', 1, '${nowIso}');"`
);
console.log('\nWrangler command (remote):');
console.log(
  `npx wrangler d1 execute work-hours-prod --remote --command "INSERT INTO devices (id, name, token_hash, enabled, created_at_utc) VALUES ('${deviceId}', '${deviceName}', '${hash}', 1, '${nowIso}');"`
);
