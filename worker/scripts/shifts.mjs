#!/usr/bin/env node
/**
 * Direct D1 shift management CLI for Work Hours Tracker.
 *
 * Usage:
 *   node scripts/shifts.mjs list [--limit 20] [--staging|--local]
 *   node scripts/shifts.mjs add --in "2026-11-10 08:00" --out "2026-11-10 10:00" --reason "..." [--location remote|in-office] [--note "..."] [--apply]
 *   node scripts/shifts.mjs edit --id <eventId> [--in "..."] [--out "..."] [--location remote|in-office] [--note "..." | --clear-note] [--reason "..."] [--apply]
 *   node scripts/shifts.mjs close --out "2026-11-10 12:00" [--reason "..."] [--note "..."] [--location remote|in-office] [--apply]
 *   node scripts/shifts.mjs delete --id <eventId> [--apply]
 */

import { execFileSync } from 'node:child_process';
import { createRequire } from 'node:module';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const WORKER_DIR = path.resolve(__dirname, '..');
const DEFAULT_USER_ID = 'default-user';
const MAX_SHIFT_SECONDS = 24 * 60 * 60;
const VALID_LOCATIONS = new Set(['remote', 'in-office']);
const TIMEZONE = 'Europe/Warsaw';

const require = createRequire(import.meta.url);

const WARSAW_PARTS_FORMATTER = new Intl.DateTimeFormat('en-CA', {
  timeZone: TIMEZONE,
  year: 'numeric',
  month: '2-digit',
  day: '2-digit',
  hour: '2-digit',
  minute: '2-digit',
  second: '2-digit',
  hour12: false,
});

function printHelp() {
  console.log(`Work Hours D1 Shift Helper (dry-run by default; pass --apply to write)

Commands:
  list    List recent shifts and current work_state (read-only)
  add     Insert a completed (clock_in + clock_out) shift pair
  edit    Update start/end times, location, reason, or note on a shift
  close   Close a currently open clocked_in shift with a clock_out event
  delete  Delete a shift (or open clock_in) and resync work_state

Target flags (default: production remote DB "work-hours-prod"):
  --staging         Target staging DB ("work-hours-staging" via --env staging)
  --local           Target local Wrangler D1 state instead of --remote
  --user <id>       User ID (default: "${DEFAULT_USER_ID}")
  --apply           Execute SQL writes (without --apply, prints dry-run SQL only)
  --help, -h        Show this help message

Timestamps:
  - ISO 8601 with offset or Z: "2026-11-10T09:00:00Z", "2026-11-10T10:00+01:00"
  - Europe/Warsaw local time:  "2026-11-10 10:00" or "2026-11-10T10:00"

Examples:
  node scripts/shifts.mjs list
  node scripts/shifts.mjs edit --id <event-id> --out "2026-11-09 12:00" --reason "Forgot to clock out" --apply
  node scripts/shifts.mjs close --out "2026-11-10 12:00" --reason "Late manual close" --apply
  node scripts/shifts.mjs add --in "2026-11-08 09:00" --out "2026-11-08 17:00" --reason "Missed shift" --apply
  node scripts/shifts.mjs delete --id <event-id> --apply
`);
}

function getWarsawParts(epochMs) {
  const map = {};
  for (const part of WARSAW_PARTS_FORMATTER.formatToParts(new Date(epochMs))) {
    if (part.type !== 'literal') {
      map[part.type] = Number(part.value);
    }
  }
  const hour = map.hour === 24 ? 0 : map.hour;
  return {
    year: map.year,
    month: map.month,
    day: map.day,
    hour,
    minute: map.minute,
    second: map.second,
  };
}

/**
 * Formats an ISO UTC timestamp as "YYYY-MM-DD HH:MM" in Europe/Warsaw.
 */
function formatWarsaw(isoString) {
  if (!isoString) return 'null';
  const p = getWarsawParts(Date.parse(isoString));
  const pad = (n) => String(n).padStart(2, '0');
  return `${p.year}-${pad(p.month)}-${pad(p.day)} ${pad(p.hour)}:${pad(p.minute)} (${TIMEZONE})`;
}

/**
 * Parses either an explicit timezone ISO string or an Europe/Warsaw local
 * datetime string, returning a minute-truncated UTC Date.
 */
function parseTimestamp(raw, label) {
  const input = String(raw ?? '').trim();
  if (!input) {
    throw new Error(`Missing required timestamp for ${label}.`);
  }

  // Explicit UTC/offset ISO 8601
  if (/(Z|[+-]\d{2}:\d{2})$/i.test(input)) {
    const ms = Date.parse(input);
    if (!Number.isFinite(ms)) {
      throw new Error(`Invalid ISO timestamp for ${label}: "${input}"`);
    }
    return new Date(Math.floor(ms / 60_000) * 60_000);
  }

  // Local Europe/Warsaw datetime: YYYY-MM-DD[ T]HH:MM(:SS)?
  const match = input.match(/^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2})(?::(\d{2}))?$/);
  if (!match) {
    throw new Error(
      `Invalid timestamp for ${label}: "${input}". Expected "YYYY-MM-DD HH:MM" (${TIMEZONE}) or ISO 8601 with Z/offset.`
    );
  }

  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  const hour = Number(match[4]);
  const minute = Number(match[5]);

  if (month < 1 || month > 12 || day < 1 || day > 31 || hour > 23 || minute > 59) {
    throw new Error(`Out-of-range date/time components for ${label}: "${input}"`);
  }

  // Reject impossible calendar dates (e.g. Feb 31 -> Mar 3) before DST fixed-point solving
  const targetUtcView = Date.UTC(year, month - 1, day, hour, minute, 0, 0);
  const utcCheck = new Date(targetUtcView);
  if (
    utcCheck.getUTCFullYear() !== year ||
    utcCheck.getUTCMonth() + 1 !== month ||
    utcCheck.getUTCDate() !== day
  ) {
    throw new Error(`Invalid calendar date for ${label}: "${input}".`);
  }

  // Fixed-point solve for Warsaw DST offset
  let guessMs = targetUtcView - 60 * 60_000;
  for (let i = 0; i < 3; i += 1) {
    const p = getWarsawParts(guessMs);
    const seenUtcView = Date.UTC(p.year, p.month - 1, p.day, p.hour, p.minute, 0, 0);
    guessMs += targetUtcView - seenUtcView;
  }

  const verify = getWarsawParts(guessMs);
  if (
    verify.year !== year ||
    verify.month !== month ||
    verify.day !== day ||
    verify.hour !== hour ||
    verify.minute !== minute
  ) {
    throw new Error(
      `Local time "${input}" does not exist in ${TIMEZONE} (likely spring DST gap).`
    );
  }

  const matchesTarget = (p) =>
    p.year === year &&
    p.month === month &&
    p.day === day &&
    p.hour === hour &&
    p.minute === minute;

  if (
    matchesTarget(getWarsawParts(guessMs - 60 * 60_000)) ||
    matchesTarget(getWarsawParts(guessMs + 60 * 60_000))
  ) {
    console.warn(
      `[WARN] Ambiguous autumn DST local time "${input}" (${TIMEZONE}); resolved to ${new Date(guessMs).toISOString()}. Pass an explicit ISO 8601 offset (e.g. +02:00 or +01:00) if you intended the other occurrence.`
    );
  }

  return new Date(guessMs);
}

function sqlVal(value) {
  if (value === null || value === undefined) return 'NULL';
  const str = String(value);
  if (str.includes('\0')) {
    throw new Error('String values must not contain NUL bytes.');
  }
  const escaped = str
    .replaceAll("'", "''")
    .replaceAll('\r', "' || char(13) || '")
    .replaceAll('\n', "' || char(10) || '");
  return `'${escaped}'`;
}

function formatDuration(seconds) {
  const totalMins = Math.max(0, Math.floor(seconds / 60));
  const h = Math.floor(totalMins / 60);
  const m = totalMins % 60;
  return `${h}h ${m}m`;
}

function resolveWranglerBin() {
  try {
    const pkgPath = require.resolve('wrangler/package.json', { paths: [WORKER_DIR] });
    const pkg = JSON.parse(fs.readFileSync(pkgPath, 'utf8'));
    const binRel = typeof pkg.bin === 'string' ? pkg.bin : pkg.bin?.wrangler;
    if (binRel) {
      return path.resolve(path.dirname(pkgPath), binRel);
    }
  } catch {
    // Fallback below
  }
  const fallback = path.join(WORKER_DIR, 'node_modules', 'wrangler', 'bin', 'wrangler.js');
  if (!fs.existsSync(fallback)) {
    throw new Error('Could not locate wrangler CLI in worker/node_modules. Run npm install first.');
  }
  return fallback;
}

function parseWranglerJson(stdout) {
  const trimmed = String(stdout ?? '').trim();
  try {
    return JSON.parse(trimmed);
  } catch {
    // Extract the JSON array/object block if Wrangler emitted extra status lines on stdout.
    const lines = trimmed.split(/\r?\n/);
    for (let i = 0; i < lines.length; i += 1) {
      const line = lines[i].trimStart();
      if (line.startsWith('[') || line.startsWith('{')) {
        const candidate = lines.slice(i).join('\n');
        try {
          return JSON.parse(candidate);
        } catch {
          const lastBracket = Math.max(candidate.lastIndexOf(']'), candidate.lastIndexOf('}'));
          if (lastBracket !== -1) {
            try {
              return JSON.parse(candidate.slice(0, lastBracket + 1));
            } catch {
              // continue scanning
            }
          }
        }
      }
    }
    throw new Error(`Invalid JSON output from Wrangler:\n${trimmed}`);
  }
}

function runWranglerSql(sql, targetOpts) {
  const wranglerBin = resolveWranglerBin();
  const dbName = targetOpts.staging ? 'work-hours-staging' : 'work-hours-prod';
  // Use --command instead of --file so --remote executes via /query (returning rows + meta.changes)
  // rather than the interactive R2 bulk-import flow that prints progress spinners to stdout.
  const compactSql = sql.replaceAll('\r\n', ' ').replaceAll('\n', ' ').trim();
  const args = [wranglerBin, 'd1', 'execute', dbName];
  if (targetOpts.staging) {
    args.push('--env', 'staging');
  }
  args.push(targetOpts.local ? '--local' : '--remote');
  args.push('--yes', '--json', `--command=${compactSql}`);

  try {
    const stdout = execFileSync(process.execPath, args, {
      cwd: WORKER_DIR,
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe'],
    });
    const parsed = parseWranglerJson(stdout);
    return Array.isArray(parsed) ? parsed : [parsed];
  } catch (err) {
    const stderr = err?.stderr ? String(err.stderr) : '';
    const stdout = err?.stdout ? String(err.stdout) : '';
    throw new Error(
      `Wrangler D1 command failed: ${err instanceof Error ? err.message : String(err)}\n${stderr || stdout}`.trim()
    );
  }
}

function fetchSnapshot(userId, targetOpts) {
  const sql = [
    `SELECT * FROM work_state WHERE user_id = ${sqlVal(userId)};`,
    `SELECT id, request_id, user_id, device_id, event_type, source, occurred_at_utc, created_at_utc, reason, note, location FROM events WHERE user_id = ${sqlVal(userId)} ORDER BY occurred_at_utc ASC, created_at_utc ASC, rowid ASC;`,
  ].join('\n');
  const results = runWranglerSql(sql, targetOpts);
  const workState = results[0]?.results?.[0] ?? null;
  const events = results[1]?.results ?? [];
  return { workState, events };
}

/**
 * Pairs chronological events into completed shifts plus an optional open shift.
 */
function buildShifts(events) {
  const shifts = [];
  let openClockIn = null;

  for (const ev of events) {
    if (ev.event_type === 'clock_in') {
      openClockIn = ev;
    } else if (ev.event_type === 'clock_out' && openClockIn) {
      const startMs = Date.parse(openClockIn.occurred_at_utc);
      const endMs = Date.parse(ev.occurred_at_utc);
      shifts.push({
        clockIn: openClockIn,
        clockOut: ev,
        startMs,
        endMs,
        durationSeconds: Math.max(0, Math.floor((endMs - startMs) / 1000)),
      });
      openClockIn = null;
    }
  }

  return { shifts, openClockIn };
}

function assertNoOverlap(candidateStartMs, candidateEndMs, shifts, openClockIn, ignoreShiftIndex = -1) {
  if (candidateEndMs === null) {
    for (let i = 0; i < shifts.length; i += 1) {
      if (i === ignoreShiftIndex) continue;
      const s = shifts[i];
      if (candidateStartMs <= s.endMs) {
        throw new Error(
          `Open shift start (${formatWarsaw(new Date(candidateStartMs).toISOString())}) must be strictly after existing shift ${s.clockIn.id} ended at ${formatWarsaw(s.clockOut.occurred_at_utc)}.`
        );
      }
    }
    return;
  }

  for (let i = 0; i < shifts.length; i += 1) {
    if (i === ignoreShiftIndex) continue;
    const s = shifts[i];
    // Disallow touching same-minute boundaries (<= / >=) so created_at_utc ties never invert shift pairing.
    if (candidateStartMs <= s.endMs && candidateEndMs >= s.startMs) {
      throw new Error(
        `Shift [${formatWarsaw(new Date(candidateStartMs).toISOString())} -> ${formatWarsaw(new Date(candidateEndMs).toISOString())}] overlaps or touches existing shift ${s.clockIn.id} (${formatWarsaw(s.clockIn.occurred_at_utc)} -> ${formatWarsaw(s.clockOut.occurred_at_utc)}).`
      );
    }
  }

  if (openClockIn) {
    const openStartMs = Date.parse(openClockIn.occurred_at_utc);
    if (candidateEndMs >= openStartMs) {
      throw new Error(
        `Shift end (${formatWarsaw(new Date(candidateEndMs).toISOString())}) conflicts with currently open clock_in ${openClockIn.id} started at ${formatWarsaw(openClockIn.occurred_at_utc)}.`
      );
    }
  }
}

function workStateGuardClause(snapshot, userId) {
  const ws = snapshot.workState;
  if (!ws) {
    return `NOT EXISTS (SELECT 1 FROM work_state WHERE user_id = ${sqlVal(userId)})`;
  }
  return `EXISTS (SELECT 1 FROM work_state WHERE user_id = ${sqlVal(userId)} AND version = ${ws.version})`;
}

function validateLocation(rawLocation, fallback = 'remote') {
  if (rawLocation === undefined) return fallback;
  if (!VALID_LOCATIONS.has(rawLocation)) {
    throw new Error(`Invalid --location "${rawLocation}". Must be "remote" or "in-office".`);
  }
  return rawLocation;
}

function validateShiftBounds(startDate, endDate, force) {
  if (endDate.getTime() <= startDate.getTime()) {
    throw new Error('Clock-out time must be strictly after clock-in time.');
  }
  const durationSeconds = Math.floor((endDate.getTime() - startDate.getTime()) / 1000);
  if (!force && durationSeconds > MAX_SHIFT_SECONDS) {
    throw new Error(
      `Shift duration (${formatDuration(durationSeconds)}) exceeds 24h limit. Pass --force to override.`
    );
  }
  return durationSeconds;
}

function targetLabel(opts) {
  const db = opts.staging ? 'work-hours-staging' : 'work-hours-prod';
  const mode = opts.local ? 'local' : 'remote';
  return `${db} (${mode})`;
}

function executeOrPrintDryRun(
  sqlStatements,
  summaryLines,
  opts,
  expectedMinChanges = sqlStatements.map(() => 1)
) {
  const sql = `${sqlStatements.join('\n')}\n`;
  console.log(`\nTarget DB: ${targetLabel(opts)}`);
  console.log('Planned Changes:');
  for (const line of summaryLines) {
    console.log(`  ${line}`);
  }
  console.log('\nSQL:');
  console.log(sql.trimEnd());

  if (!opts.apply) {
    console.log('\n[DRY-RUN] No changes written to D1. Re-run with --apply to execute.');
    return;
  }

  const results = runWranglerSql(sql, opts);
  for (let i = 0; i < expectedMinChanges.length; i += 1) {
    const minExpected = expectedMinChanges[i];
    const actualChanges = results[i]?.meta?.changes;
    if (typeof actualChanges === 'number' && actualChanges < minExpected) {
      throw new Error(
        `Concurrent modification or missing target detected (statement ${i + 1} expected >= ${minExpected} change(s), got ${actualChanges}). Re-run "list" to inspect current DB state.`
      );
    }
  }
  console.log('\n[APPLIED] D1 update completed successfully.');
}

function findShiftById(shifts, openClockIn, eventId) {
  for (let i = 0; i < shifts.length; i += 1) {
    if (shifts[i].clockIn.id === eventId || shifts[i].clockOut.id === eventId) {
      return { index: i, shift: shifts[i], isOpen: false };
    }
  }
  if (openClockIn && openClockIn.id === eventId) {
    return { index: -1, shift: { clockIn: openClockIn, clockOut: null }, isOpen: true };
  }
  throw new Error(`No shift or open clock_in found matching event id "${eventId}".`);
}

function handleList(snapshot, flags, opts) {
  const limitRaw = flags.limit !== undefined ? Number(flags.limit) : 20;
  const limit = Number.isInteger(limitRaw) && limitRaw > 0 ? limitRaw : 20;
  const { shifts, openClockIn } = buildShifts(snapshot.events);

  console.log(`\nTarget DB: ${targetLabel(opts)}`);
  const ws = snapshot.workState;
  console.log(
    `Work State: ${ws ? `${ws.state} (v${ws.version})` : 'none'}${
      ws?.active_since_utc ? ` | since: ${formatWarsaw(ws.active_since_utc)}` : ''
    }${ws?.target_clock_out_utc ? ` | target: ${formatWarsaw(ws.target_clock_out_utc)}` : ''}`
  );

  if (openClockIn) {
    console.log(
      `\n[OPEN SHIFT] in=${openClockIn.id} | start=${formatWarsaw(openClockIn.occurred_at_utc)} | loc=${openClockIn.location}`
    );
  }

  const recent = shifts.slice(-limit).reverse();
  console.log(`\nShowing ${recent.length} of ${shifts.length} completed shift(s):`);
  for (const s of recent) {
    const parts = [
      `${formatWarsaw(s.clockIn.occurred_at_utc)} -> ${formatWarsaw(s.clockOut.occurred_at_utc)}`,
      `(${formatDuration(s.durationSeconds)})`,
      `[${s.clockIn.location}]`,
      `in=${s.clockIn.id}`,
      `out=${s.clockOut.id}`,
    ];
    if (s.clockOut.reason) parts.push(`reason="${s.clockOut.reason}"`);
    if (s.clockOut.note) parts.push(`note="${s.clockOut.note.replaceAll('\n', '\\n')}"`);
    console.log(`  - ${parts.join(' | ')}`);
  }
}

function handleAdd(snapshot, flags, opts) {
  if (!flags.in || !flags.out || !flags.reason) {
    throw new Error('add requires --in "<time>", --out "<time>", and --reason "<text>".');
  }

  const startDate = parseTimestamp(flags.in, '--in');
  const endDate = parseTimestamp(flags.out, '--out');
  const durationSeconds = validateShiftBounds(startDate, endDate, Boolean(flags.force));
  const location = validateLocation(flags.location, 'remote');
  const reason = String(flags.reason).trim();
  if (!reason) throw new Error('--reason must not be empty.');
  const note = flags.note !== undefined ? String(flags.note).trim() || null : null;

  const { shifts, openClockIn } = buildShifts(snapshot.events);
  assertNoOverlap(startDate.getTime(), endDate.getTime(), shifts, openClockIn);

  const nowIso = new Date().toISOString();
  const inIso = startDate.toISOString();
  const outIso = endDate.toISOString();
  const inId = crypto.randomUUID();
  const outId = crypto.randomUUID();
  const reqBase = `cli_add_${crypto.randomUUID()}`;
  const wsGuard = workStateGuardClause(snapshot, opts.user);

  const sql = [
    `INSERT INTO events (id, request_id, user_id, device_id, event_type, source, occurred_at_utc, created_at_utc, reason, note, location) SELECT ${sqlVal(inId)}, ${sqlVal(`${reqBase}_in`)}, ${sqlVal(opts.user)}, NULL, 'clock_in', 'admin_manual', ${sqlVal(inIso)}, ${sqlVal(nowIso)}, ${sqlVal(reason)}, NULL, ${sqlVal(location)} WHERE ${wsGuard};`,
    `INSERT INTO events (id, request_id, user_id, device_id, event_type, source, occurred_at_utc, created_at_utc, reason, note, location) SELECT ${sqlVal(outId)}, ${sqlVal(`${reqBase}_out`)}, ${sqlVal(opts.user)}, NULL, 'clock_out', 'admin_manual', ${sqlVal(outIso)}, ${sqlVal(nowIso)}, ${sqlVal(reason)}, ${sqlVal(note)}, ${sqlVal(location)} WHERE ${wsGuard} AND EXISTS (SELECT 1 FROM events WHERE id = ${sqlVal(inId)});`,
  ];

  executeOrPrintDryRun(
    sql,
    [
      `ADD shift ${formatWarsaw(inIso)} -> ${formatWarsaw(outIso)} (${formatDuration(durationSeconds)}, ${location})`,
      `clock_in id: ${inId}, clock_out id: ${outId}`,
      `reason: ${reason}`,
    ],
    opts
  );
}

function handleEdit(snapshot, flags, opts) {
  if (!flags.id) {
    throw new Error('edit requires --id <clock_in_or_clock_out_event_id>.');
  }
  if (flags.reason !== undefined && !String(flags.reason).trim()) {
    throw new Error('--reason must not be empty.');
  }

  const { shifts, openClockIn } = buildShifts(snapshot.events);
  const found = findShiftById(shifts, openClockIn, String(flags.id).trim());
  const { shift, isOpen, index } = found;

  if (isOpen && flags.out !== undefined) {
    throw new Error('Cannot set --out on an open shift with edit; use "close --out ..." instead.');
  }
  if (isOpen && (flags.note !== undefined || flags['clear-note'] || flags.reason !== undefined)) {
    throw new Error('Cannot set --note, --clear-note, or --reason on an open shift; close it first or omit those flags.');
  }

  const nextInDate =
    flags.in !== undefined
      ? parseTimestamp(flags.in, '--in')
      : new Date(shift.clockIn.occurred_at_utc);

  const nextLocation = validateLocation(flags.location, shift.clockIn.location);
  const nowIso = new Date().toISOString();
  const nextInIso = nextInDate.toISOString();
  const wsGuard = workStateGuardClause(snapshot, opts.user);
  const sql = [];
  const summary = [];

  if (isOpen) {
    if (flags.in !== undefined && snapshot.workState?.state !== 'clocked_in') {
      throw new Error(
        `Cannot update open clock_in time because work_state is "${snapshot.workState?.state ?? 'missing'}" (expected clocked_in).`
      );
    }
    assertNoOverlap(nextInDate.getTime(), null, shifts, null);

    if (flags.in !== undefined && snapshot.workState?.state === 'clocked_in') {
      const nextVersion = (snapshot.workState.version ?? 0) + 1;
      const targetMs = snapshot.workState.target_clock_out_utc
        ? Date.parse(snapshot.workState.target_clock_out_utc)
        : null;
      const clearInvalidTarget = targetMs !== null && targetMs <= nextInDate.getTime();
      sql.push(
        `UPDATE events SET occurred_at_utc = ${sqlVal(nextInIso)}, location = ${sqlVal(nextLocation)} WHERE id = ${sqlVal(shift.clockIn.id)} AND user_id = ${sqlVal(opts.user)} AND ${wsGuard};`
      );
      sql.push(
        `UPDATE work_state SET active_since_utc = ${sqlVal(nextInIso)}${clearInvalidTarget ? ', target_clock_out_utc = NULL' : ''}, version = ${nextVersion}, updated_at_utc = ${sqlVal(nowIso)} WHERE user_id = ${sqlVal(opts.user)} AND state = 'clocked_in' AND version = ${snapshot.workState.version};`
      );
      summary.push(
        `EDIT open clock_in ${shift.clockIn.id}: ${formatWarsaw(shift.clockIn.occurred_at_utc)} -> ${formatWarsaw(nextInIso)} [${nextLocation}]`
      );
    } else {
      sql.push(
        `UPDATE events SET location = ${sqlVal(nextLocation)} WHERE id = ${sqlVal(shift.clockIn.id)} AND user_id = ${sqlVal(opts.user)} AND ${wsGuard};`
      );
      summary.push(`EDIT open clock_in ${shift.clockIn.id}: location=${nextLocation}`);
    }
    executeOrPrintDryRun(sql, summary, opts);
    return;
  }

  const nextOutDate =
    flags.out !== undefined
      ? parseTimestamp(flags.out, '--out')
      : new Date(shift.clockOut.occurred_at_utc);

  const nextDuration = validateShiftBounds(nextInDate, nextOutDate, Boolean(flags.force));
  assertNoOverlap(nextInDate.getTime(), nextOutDate.getTime(), shifts, openClockIn, index);

  const nextOutIso = nextOutDate.toISOString();
  const nextNote = flags['clear-note']
    ? null
    : flags.note !== undefined
      ? String(flags.note).trim() || null
      : shift.clockOut.note;
  const nextReason =
    flags.reason !== undefined ? String(flags.reason).trim() : shift.clockOut.reason;

  sql.push(
    `UPDATE events SET occurred_at_utc = ${sqlVal(nextInIso)}, location = ${sqlVal(nextLocation)}${flags.reason !== undefined ? `, reason = ${sqlVal(nextReason)}` : ''} WHERE id = ${sqlVal(shift.clockIn.id)} AND user_id = ${sqlVal(opts.user)} AND ${wsGuard};`
  );
  sql.push(
    `UPDATE events SET occurred_at_utc = ${sqlVal(nextOutIso)}, location = ${sqlVal(nextLocation)}, note = ${sqlVal(nextNote)}, reason = ${sqlVal(nextReason)} WHERE id = ${sqlVal(shift.clockOut.id)} AND user_id = ${sqlVal(opts.user)} AND ${wsGuard};`
  );

  summary.push(
    `BEFORE: ${formatWarsaw(shift.clockIn.occurred_at_utc)} -> ${formatWarsaw(shift.clockOut.occurred_at_utc)} (${formatDuration(shift.durationSeconds)}, ${shift.clockIn.location})`
  );
  summary.push(
    `AFTER:  ${formatWarsaw(nextInIso)} -> ${formatWarsaw(nextOutIso)} (${formatDuration(nextDuration)}, ${nextLocation})`
  );
  executeOrPrintDryRun(sql, summary, opts);
}

function handleClose(snapshot, flags, opts) {
  if (!flags.out) {
    throw new Error('close requires --out "<time>".');
  }

  const ws = snapshot.workState;
  const { shifts, openClockIn } = buildShifts(snapshot.events);
  if (!ws || ws.state !== 'clocked_in' || !openClockIn) {
    throw new Error('No currently clocked_in shift to close.');
  }

  const startDate = new Date(openClockIn.occurred_at_utc);
  const endDate = parseTimestamp(flags.out, '--out');
  const durationSeconds = validateShiftBounds(startDate, endDate, Boolean(flags.force));
  assertNoOverlap(startDate.getTime(), endDate.getTime(), shifts, null);
  const location = validateLocation(flags.location, openClockIn.location ?? 'remote');
  if (flags.reason !== undefined && !String(flags.reason).trim()) {
    throw new Error('--reason must not be empty.');
  }
  const reason = flags.reason !== undefined ? String(flags.reason).trim() : 'Closed via D1 shift script';
  const note = flags.note !== undefined ? String(flags.note).trim() || null : null;

  const nowIso = new Date().toISOString();
  const outIso = endDate.toISOString();
  const outId = crypto.randomUUID();
  const nextVersion = (ws.version ?? 0) + 1;

  const sql = [
    `INSERT INTO events (id, request_id, user_id, device_id, event_type, source, occurred_at_utc, created_at_utc, reason, note, location) SELECT ${sqlVal(outId)}, ${sqlVal(`cli_close_${crypto.randomUUID()}`)}, ${sqlVal(opts.user)}, ${sqlVal(openClockIn.device_id)}, 'clock_out', ${sqlVal(openClockIn.source ?? 'flutter_app')}, ${sqlVal(outIso)}, ${sqlVal(nowIso)}, ${sqlVal(reason)}, ${sqlVal(note)}, ${sqlVal(location)} WHERE EXISTS (SELECT 1 FROM work_state WHERE user_id = ${sqlVal(opts.user)} AND state = 'clocked_in' AND version = ${ws.version});`,
    `UPDATE work_state SET state = 'clocked_out', active_since_utc = NULL, target_clock_out_utc = NULL, version = ${nextVersion}, updated_at_utc = ${sqlVal(nowIso)} WHERE user_id = ${sqlVal(opts.user)} AND state = 'clocked_in' AND version = ${ws.version};`,
  ];

  executeOrPrintDryRun(
    sql,
    [
      `CLOSE open shift ${openClockIn.id}: ${formatWarsaw(openClockIn.occurred_at_utc)} -> ${formatWarsaw(outIso)} (${formatDuration(durationSeconds)}, ${location})`,
      `clock_out id: ${outId}`,
      `work_state: clocked_in (v${ws.version}) -> clocked_out (v${nextVersion})`,
    ],
    opts
  );
}

function handleDelete(snapshot, flags, opts) {
  if (!flags.id) {
    throw new Error('delete requires --id <clock_in_or_clock_out_event_id>.');
  }

  const targetId = String(flags.id).trim();
  const { shifts, openClockIn } = buildShifts(snapshot.events);
  const wsGuard = workStateGuardClause(snapshot, opts.user);
  const nowIso = new Date().toISOString();
  const sql = [];
  const summary = [];

  let found = null;
  try {
    found = findShiftById(shifts, openClockIn, targetId);
  } catch {
    found = null;
  }

  if (!found) {
    const rawOrphan = snapshot.events.find((e) => e.id === targetId);
    if (!rawOrphan) {
      throw new Error(`No shift or event found matching event id "${targetId}".`);
    }
    sql.push(
      `DELETE FROM events WHERE user_id = ${sqlVal(opts.user)} AND id = ${sqlVal(rawOrphan.id)} AND ${wsGuard};`
    );
    summary.push(
      `DELETE unpaired orphan event (${rawOrphan.event_type}) ${rawOrphan.id} (${formatWarsaw(rawOrphan.occurred_at_utc)})`
    );
    executeOrPrintDryRun(sql, summary, opts, [1]);
    return;
  }

  const { shift, isOpen } = found;
  const expectedMinChanges = [];

  if (isOpen) {
    sql.push(
      `DELETE FROM events WHERE user_id = ${sqlVal(opts.user)} AND id = ${sqlVal(shift.clockIn.id)} AND ${wsGuard};`
    );
    expectedMinChanges.push(1);
    if (snapshot.workState?.state === 'clocked_in') {
      const nextVersion = (snapshot.workState.version ?? 0) + 1;
      sql.push(
        `UPDATE work_state SET state = 'clocked_out', active_since_utc = NULL, target_clock_out_utc = NULL, version = ${nextVersion}, updated_at_utc = ${sqlVal(nowIso)} WHERE user_id = ${sqlVal(opts.user)} AND state = 'clocked_in' AND version = ${snapshot.workState.version} AND NOT EXISTS (SELECT 1 FROM events WHERE id = ${sqlVal(shift.clockIn.id)});`
      );
      expectedMinChanges.push(1);
      summary.push(`work_state: clocked_in -> clocked_out (v${nextVersion})`);
    }
    summary.unshift(`DELETE open clock_in ${shift.clockIn.id} (${formatWarsaw(shift.clockIn.occurred_at_utc)})`);
  } else {
    sql.push(
      `DELETE FROM events WHERE user_id = ${sqlVal(opts.user)} AND id IN (${sqlVal(shift.clockIn.id)}, ${sqlVal(shift.clockOut.id)}) AND ${wsGuard};`
    );
    expectedMinChanges.push(2);
    summary.push(
      `DELETE shift (${formatWarsaw(shift.clockIn.occurred_at_utc)} -> ${formatWarsaw(shift.clockOut.occurred_at_utc)}, ${formatDuration(shift.durationSeconds)}): in=${shift.clockIn.id}, out=${shift.clockOut.id}`
    );
  }

  executeOrPrintDryRun(sql, summary, opts, expectedMinChanges);
}

function parseCliArgs(argv) {
  const BOOLEAN_FLAGS = new Set(['staging', 'local', 'apply', 'force', 'clear-note', 'help', 'h']);
  const VALUE_FLAGS = new Set(['user', 'id', 'in', 'out', 'location', 'reason', 'note', 'limit']);
  const flags = {};
  let command = null;

  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === '-h' || arg === '--help') {
      flags.help = true;
      continue;
    }
    if (arg.startsWith('--')) {
      const eqIdx = arg.indexOf('=');
      if (eqIdx !== -1) {
        const key = arg.slice(2, eqIdx);
        if (BOOLEAN_FLAGS.has(key)) {
          throw new Error(`Flag --${key} does not take a value.`);
        }
        if (!VALUE_FLAGS.has(key)) {
          throw new Error(`Unknown flag --${key}. Run with --help to see supported options.`);
        }
        flags[key] = arg.slice(eqIdx + 1);
      } else {
        const key = arg.slice(2);
        if (BOOLEAN_FLAGS.has(key)) {
          flags[key] = true;
        } else if (VALUE_FLAGS.has(key)) {
          if (i + 1 >= argv.length || argv[i + 1].startsWith('--')) {
            throw new Error(`Flag --${key} expects a value (use --${key}=... if the value starts with "--").`);
          }
          flags[key] = argv[++i];
        } else {
          throw new Error(`Unknown flag --${key}. Run with --help to see supported options.`);
        }
      }
      continue;
    }
    if (!command) {
      command = arg;
    } else {
      throw new Error(`Unexpected positional argument: "${arg}"`);
    }
  }

  return { command, flags };
}

function main() {
  const { command, flags } = parseCliArgs(process.argv.slice(2));
  if (flags.help || !command) {
    printHelp();
    process.exit(flags.help ? 0 : 1);
  }

  const opts = {
    staging: Boolean(flags.staging),
    local: Boolean(flags.local),
    apply: Boolean(flags.apply),
    user: flags.user ? String(flags.user).trim() : DEFAULT_USER_ID,
  };

  if (!opts.user) {
    throw new Error('--user cannot be empty.');
  }

  const snapshot = fetchSnapshot(opts.user, opts);

  switch (command) {
    case 'list':
      handleList(snapshot, flags, opts);
      break;
    case 'add':
      handleAdd(snapshot, flags, opts);
      break;
    case 'edit':
      handleEdit(snapshot, flags, opts);
      break;
    case 'close':
      handleClose(snapshot, flags, opts);
      break;
    case 'delete':
      handleDelete(snapshot, flags, opts);
      break;
    default:
      throw new Error(`Unknown command "${command}". Expected one of: list, add, edit, close, delete.`);
  }
}

try {
  main();
} catch (err) {
  console.error(`Error: ${err instanceof Error ? err.message : String(err)}`);
  process.exit(1);
}
