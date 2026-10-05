/**
 * Helper script to purge reports from Cloudflare R2 bucket.
 * Run directly with Node:
 *   node worker/scripts/purge-reports.mjs
 *   or:
 *   npm --prefix worker run r2:purge
 */
import { execSync } from 'node:child_process';

const BUCKET_NAME = 'work-hours-reports';

console.log('================================================================');
console.log('                  PURGE R2 REPORTS RUNBOOK');
console.log('================================================================');
console.log(`Target Bucket: ${BUCKET_NAME}`);
console.log('----------------------------------------------------------------');

// 1. Delete latest report index
try {
  console.log('Attempting to delete cached reports/latest.json pointer...');
  execSync(`npx wrangler r2 object delete ${BUCKET_NAME}/reports/latest.json`, {
    stdio: 'inherit',
  });
  console.log('Successfully deleted reports/latest.json');
} catch (err) {
  console.log('Notice: reports/latest.json was not found or already deleted.');
}

console.log('----------------------------------------------------------------');
console.log('To empty all generated .xlsx spreadsheet files from the bucket:');
console.log('Option 1 (Cloudflare Dashboard - Instant & Recommended):');
console.log(`  1. Log into dash.cloudflare.com -> R2 -> Overview`);
console.log(`  2. Click on '${BUCKET_NAME}'`);
console.log(`  3. Select 'Settings' -> 'Empty bucket' (or delete files in Objects tab).`);
console.log('\nOption 2 (Wrangler CLI for a specific file):');
console.log(`  npx wrangler r2 object delete ${BUCKET_NAME}/reports/<filename>.xlsx`);
console.log('================================================================\n');
