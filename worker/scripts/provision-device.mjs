/**
 * Helper script to generate a secure random device token and its database record.
 * Run directly with Node (no build step or tsx required):
 *   node scripts/provision-device.mjs [device-name] [pepper]
 *   or: npm run provision -- [device-name] [pepper]
 */
import { randomBytes, createHash } from 'node:crypto';

const deviceName = process.argv[2] || 'android-primary';
const pepper = process.argv[3] || process.env.DEVICE_TOKEN_PEPPER || '';

const tokenBytes = randomBytes(32);
const deviceToken = tokenBytes.toString('hex');

const hash = createHash('sha256').update(deviceToken + pepper).digest('hex');
const deviceId = randomBytes(16).toString('hex');
const nowIso = new Date().toISOString();

console.log('================================================================');
console.log('                    DEVICE PROVISIONING');
console.log('================================================================');
console.log(`Device ID:    ${deviceId}`);
console.log(`Device Name:  ${deviceName}`);
console.log(`Pepper used:  ${pepper ? '[SET]' : '[NONE - empty string]'}`);
if (!pepper) {
  console.log('  -> NOTE: If your remote Cloudflare Worker has a secret DEVICE_TOKEN_PEPPER,');
  console.log('     pass it as the 2nd argument: npm run provision -- <device-name> <pepper>');
}
console.log('----------------------------------------------------------------');
console.log('STEP 1: CLIENT SETTINGS (Web app or Android app)');
console.log('----------------------------------------------------------------');
console.log(`Device Bearer Token:`);
console.log(`  ${deviceToken}`);
console.log('\n* Paste THIS token into your Web or Android App settings dialog.');
console.log('* Do NOT paste the hashed token into the client!');
console.log('----------------------------------------------------------------');
console.log('STEP 2: DATABASE INSERTION (Cloudflare D1)');
console.log('----------------------------------------------------------------');
console.log(`Token SHA-256 Hash stored in DB:`);
console.log(`  ${hash}\n`);
console.log('Remote execution command:');
console.log(
  `  npx wrangler d1 execute work-hours-prod --remote --command "INSERT INTO devices (id, name, token_hash, enabled, created_at_utc) VALUES ('${deviceId}', '${deviceName}', '${hash}', 1, '${nowIso}');"`
);
console.log('\nLocal execution command (for local wrangler dev only):');
console.log(
  `  npx wrangler d1 execute work-hours-prod --local --command "INSERT INTO devices (id, name, token_hash, enabled, created_at_utc) VALUES ('${deviceId}', '${deviceName}', '${hash}', 1, '${nowIso}');"`
);
console.log('================================================================\n');
