/**
 * Helper script to generate a secure random device token and its database record.
 * Run directly with Node (no build step or tsx required):
 *   DEVICE_TOKEN_PEPPER="..." node scripts/provision-device.mjs [device-name]
 *   or: DEVICE_TOKEN_PEPPER="..." npm run provision -- [device-name]
 */
import { randomBytes, createHash } from 'node:crypto';

if (process.argv[3]) {
  console.error(
    'Error: Passing pepper as a CLI argument exposes it in shell history and process lists.\n' +
      'Set the DEVICE_TOKEN_PEPPER environment variable instead.'
  );
  process.exit(1);
}

const deviceName = (process.argv[2] || 'android-primary').trim() || 'android-primary';
const pepper = process.env.DEVICE_TOKEN_PEPPER || '';
const sqlEscapedDeviceName = deviceName.replace(/'/g, "''");

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
  console.log('     set it in the environment: DEVICE_TOKEN_PEPPER=... npm run provision -- <device-name>');
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
  `  npx wrangler d1 execute work-hours-prod --remote --command "INSERT INTO devices (id, name, token_hash, enabled, created_at_utc) VALUES ('${deviceId}', '${sqlEscapedDeviceName}', '${hash}', 1, '${nowIso}');"`
);
console.log('\nLocal execution command (for local wrangler dev only):');
console.log(
  `  npx wrangler d1 execute work-hours-prod --local --command "INSERT INTO devices (id, name, token_hash, enabled, created_at_utc) VALUES ('${deviceId}', '${sqlEscapedDeviceName}', '${hash}', 1, '${nowIso}');"`
);
console.log('================================================================\n');
