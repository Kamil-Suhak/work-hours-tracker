# Work Hours Tracker: Ground-Truth Design Document

**Document version:** 1.0  
**Application target:** v0.1 onward  
**Primary goal:** Record personal work start and end times with minimal friction, preserve the data across releases, show current/month-to-date state, and later generate monthly Excel reports by email.

> This document is the source of truth for implementation decisions. If generated code conflicts with this document, either fix the code or deliberately update this document in the same pull request.

---

## 1. Product principles

1. **The API and database are the source of truth.** The Flutter app and Android widget are independent API clients.
2. **Use explicit commands.** There are separate clock-in and clock-out operations. There is no toggle endpoint.
3. **Store raw events.** Totals and shifts are derived from clock events rather than stored as permanent monthly totals.
4. **Server time is authoritative.** Normal clock-in/out requests do not supply their own timestamps.
5. **Every request is safe to retry.** Repeated or concurrent requests must not create duplicate or contradictory events.
6. **Production data survives deployments.** Schema changes use versioned migrations. Production database files are never recreated during deployment.
7. **Keep it small.** This is a single-user personal tool, not a general workforce-management platform.

---

## 2. Chosen architecture

```text
Android home-screen widget (Kotlin/Jetpack Glance)
                    |
                    | HTTPS JSON API
                    v
Flutter app (Riverpod) ---> Cloudflare Worker (TypeScript)
                                  |
                                  v
                          Cloudflare D1 database

Later:
GitHub Actions scheduled workflow
        |
        +--> protected report API
        +--> Python/openpyxl workbook
        +--> email provider
```

### Technology choices

- **Mobile app:** Flutter and Riverpod
- **Android widget:** Kotlin, preferably Jetpack Glance
- **HTTP client:** Dio or Dart's standard HTTP client; choose one and use it consistently
- **Backend:** TypeScript on Cloudflare Workers
- **Database:** Cloudflare D1
- **Deployment:** Wrangler through GitHub Actions
- **Reporting:** Python and openpyxl in GitHub Actions
- **Email:** Resend or an equivalent transactional-email provider
- **Time zone for display/reporting:** `Europe/Warsaw`
- **Time storage:** UTC ISO 8601 strings, for example `2026-10-03T13:42:17.000Z`

### Explicit non-goals

Unless promoted into a later version, do not add:

- break tracking;
- projects, clients, or categories;
- GPS or location tracking;
- multiple users or teams;
- payroll calculations;
- calendar integration;
- native iOS widgets;
- offline event queues;
- real-time sockets or constant polling.

---

## 3. Version and feature plan

## v0.1: Monday-testable vertical slice

The purpose of v0.1 is to prove the entire clocking path with production-persistent data.

### Required

- Cloudflare Worker deployed to one production environment.
- D1 production database created once and bound to the Worker.
- Versioned migration `0001_initial.sql`.
- Device-token authentication.
- `POST /api/v1/clock-in`.
- `POST /api/v1/clock-out`.
- `GET /api/v1/status`.
- `GET /api/v1/events?from=...&to=...`.
- `POST /api/v1/admin/events/manual` for authenticated historical entries and recovery.
- Request IDs and duplicate-request protection.
- Explicit `source` on every event.
- Flutter app with:
  - current state;
  - Clock In and Clock Out buttons;
  - active-since time;
  - today's derived duration;
  - refresh on startup, foreground resume, pull-to-refresh, and successful command.
- Basic Kotlin Android widget with separate Clock In and Clock Out actions. If widget UI work slips, an Android shortcut or the Flutter app is an acceptable temporary Monday test client, but the API contract must not change.
- Structured error responses and useful client feedback.
- A small test suite for transition and duration rules.
- Deployment workflow that applies pending migrations and then deploys the Worker.

### Deliberately excluded from v0.1

- charts;
- email reports;
- Excel generation;
- full correction UI;
- offline queuing;
- multiple devices management UI;
- polished visual design.

### Definition of done

- Clocking in twice creates one event, not two.
- Clocking out twice creates one clock-out event, not two.
- App and widget observe the same server state after refreshing.
- A duplicate `requestId` returns the original effective result without another insert.
- A historical shift can be entered manually.
- Redeploying the Worker does not erase events.
- A schema migration can be applied to production without recreating the database.
- Monday's events can be queried and manually inspected.

## v0.2: Usable daily tracker

- Month-to-date and per-day totals.
- Recent shifts list in the Flutter app.
- Manual add/correct flow in the app, protected by admin authentication or an explicit elevated mode.
- Validation and warning for unmatched events.
- Better widget state label and last-successful-sync time.
- Undo last action for a short period, implemented as a server operation.
- Improved automated tests, including concurrency and daylight-saving cases.

## v0.3: Reporting

- Python report generator.
- Excel workbook with `Summary`, `Daily Hours`, and `Raw Events` sheets.
- Daily-hours, weekly-hours, and cumulative-hours charts.
- Monthly summary email and workbook attachment.
- Scheduled GitHub Actions workflow plus manual dispatch.
- Report-run record in D1 to prevent duplicate emails.
- Download-current-month endpoint or app action.

## v0.4: Reliability and polish

- Device-token creation, rotation, and revocation.
- Better audit trail for corrections.
- Expected-hours progress and optional clock-out reminder.
- Dashboard/PWA only if it still adds value after using the Flutter app.
- Export/backup command.
- Monitoring and alerting for failed scheduled reports.

## v1.0: Stable personal release

- Stable API contract.
- Documented restore and token-rotation procedures.
- Proven migration process.
- Complete monthly reporting flow.
- Reliable edit/recovery workflow.
- No known event-loss or duplicate-event defects.

---

## 4. Repository layout

```text
work-hours/
├── worker/
│   ├── src/
│   │   ├── index.ts
│   │   ├── auth.ts
│   │   ├── clock.ts
│   │   ├── events.ts
│   │   ├── status.ts
│   │   ├── errors.ts
│   │   └── types.ts
│   ├── migrations/
│   │   └── 0001_initial.sql
│   ├── test/
│   ├── package.json
│   ├── tsconfig.json
│   └── wrangler.jsonc
├── mobile/
│   ├── lib/
│   │   ├── api/
│   │   ├── features/clock/
│   │   ├── features/history/
│   │   └── main.dart
│   └── android/              # Kotlin widget code lives here
├── reporting/               # added in v0.3
│   ├── generate_report.py
│   ├── send_report.py
│   └── requirements.txt
├── .github/workflows/
│   ├── ci.yml
│   ├── deploy-worker.yml
│   └── monthly-report.yml    # added in v0.3
├── DESIGN.md
└── README.md
```

Keep the Worker and mobile app in one repository until there is a concrete reason to split them.

---

## 5. API contract

All endpoints use HTTPS and JSON. Successful command responses return the resulting authoritative state.

### Authentication

```http
Authorization: Bearer <device-token>
```

- Generate a cryptographically random token.
- Store only a keyed hash or strong hash of the token in D1.
- Store the original token in Android secure storage.
- Do not put tokens in URLs, source control, logs, screenshots, or Flutter compile-time constants.
- Use a separate admin credential for manual historical entries and corrections.

### `POST /api/v1/clock-in`

```json
{
  "requestId": "uuid-v4",
  "source": "flutter_app"
}
```

Rules:

- If currently clocked out, insert a `clock_in` event and return `changed: true`.
- If already clocked in, insert nothing and return `changed: false`.
- If `requestId` was already processed, return the prior outcome and insert nothing.
- The event timestamp comes from the server.

### `POST /api/v1/clock-out`

Same request body and retry rules as clock-in.

- If currently clocked in, insert a `clock_out` event.
- If already clocked out, insert nothing and return the current state.

### Command response

```json
{
  "state": "clocked_in",
  "changed": true,
  "activeSince": "2026-10-03T06:13:42.000Z",
  "serverTime": "2026-10-03T06:13:42.000Z",
  "todaySeconds": 0,
  "monthSeconds": 231480
}
```

Do not return floating-point hours. Return integer seconds and format them in the client.

### `GET /api/v1/status`

Returns the same state shape without `changed`.

### `GET /api/v1/events`

Query parameters:

- `from`: required ISO timestamp;
- `to`: required ISO timestamp;
- optional pagination cursor when needed later.

The server must limit the maximum range even for a single-user app.

### `POST /api/v1/admin/events/manual`

Purpose: enter a past shift, repair data after a missed clock action, or recover from an app/API failure.

```json
{
  "clockInAt": "2026-10-02T06:00:00.000Z",
  "clockOutAt": "2026-10-02T14:00:00.000Z",
  "reason": "Backfill for first work day",
  "requestId": "uuid-v4"
}
```

Rules:

- Requires the separate admin token.
- Inserts a matched pair in one database transaction/batch.
- Uses source `admin_manual`.
- Requires a non-empty reason.
- Rejects `clockOutAt <= clockInAt`.
- Rejects unreasonable durations, initially more than 24 hours.
- Warns or rejects overlap with an existing shift.
- Stores `created_at_utc` separately from `occurred_at_utc`.
- Never rewrites the historical creation time to pretend the event was recorded earlier.

For the first backfill, this endpoint may be called with `curl`, Bruno, Postman, or a tiny local script. A UI is not required in v0.1.

### Error shape

```json
{
  "error": {
    "code": "ALREADY_CLOCKED_OUT",
    "message": "No state change was required.",
    "requestId": "uuid-v4"
  }
}
```

Use stable machine-readable codes. Do not expose stack traces, SQL, token values, or internal binding names.

---

## 6. Database design

### Initial schema outline

```sql
CREATE TABLE devices (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    token_hash TEXT NOT NULL UNIQUE,
    enabled INTEGER NOT NULL DEFAULT 1 CHECK (enabled IN (0, 1)),
    created_at_utc TEXT NOT NULL
);

CREATE TABLE work_state (
    user_id TEXT PRIMARY KEY,
    state TEXT NOT NULL CHECK (state IN ('clocked_in', 'clocked_out')),
    active_since_utc TEXT,
    version INTEGER NOT NULL DEFAULT 0,
    updated_at_utc TEXT NOT NULL
);

CREATE TABLE events (
    id TEXT PRIMARY KEY,
    request_id TEXT NOT NULL UNIQUE,
    user_id TEXT NOT NULL,
    device_id TEXT,
    event_type TEXT NOT NULL CHECK (event_type IN ('clock_in', 'clock_out')),
    source TEXT NOT NULL CHECK (
        source IN ('flutter_app', 'android_widget', 'admin_manual', 'web_dashboard')
    ),
    occurred_at_utc TEXT NOT NULL,
    created_at_utc TEXT NOT NULL,
    reason TEXT,
    FOREIGN KEY (device_id) REFERENCES devices(id)
);

CREATE INDEX idx_events_user_occurred
ON events(user_id, occurred_at_utc);

CREATE TABLE processed_requests (
    request_id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    operation TEXT NOT NULL,
    response_json TEXT NOT NULL,
    created_at_utc TEXT NOT NULL
);
```

`events` is the long-term record. `work_state` is a fast current-state projection. They must be updated atomically.

For a single-user v0.1, use a constant internal user ID such as `default-user`; do not build account management.

### Shift derivation

1. Sort raw events by `occurred_at_utc`, then by ID as a deterministic tiebreaker.
2. Pair each `clock_in` with the following valid `clock_out`.
3. Calculate duration from UTC timestamps.
4. Convert timestamps to `Europe/Warsaw` only for display and report grouping.
5. Flag unmatched or invalid sequences. Do not silently invent missing times.

---

## 7. Database persistence and migrations

This section is mandatory implementation policy.

### Rules

- Create the production D1 database **once**.
- Commit every schema change as a new numbered SQL migration.
- Never edit a migration that has already been applied to production.
- Never put `DROP TABLE`, database recreation, or destructive reset commands into the normal deployment workflow.
- Never run seed data against production automatically.
- Test migrations locally first, then apply them remotely.
- Back up/export important data before a risky or destructive migration.
- Application deployments and database contents are separate. Deploying Worker code must not recreate D1.

Cloudflare D1 tracks applied migration files in its migrations table, so only pending migrations are applied. Migration files are ordered and committed with the codebase.

### Typical commands

```bash
# Create the database once
npx wrangler d1 create work-hours-prod

# Create the first migration
npx wrangler d1 migrations create work-hours-prod initial_schema

# Apply locally during development
npx wrangler d1 migrations apply work-hours-prod --local

# Inspect unapplied migrations
npx wrangler d1 migrations list work-hours-prod --remote

# Apply to production
npx wrangler d1 migrations apply work-hours-prod --remote
```

Use the immutable database name in migration commands where possible, not only a binding name that might later be changed.

### Safe migration pattern

For additive changes:

```sql
ALTER TABLE events ADD COLUMN app_version TEXT;
CREATE INDEX IF NOT EXISTS idx_events_source ON events(source);
```

For a complex or destructive schema change:

1. Create a new table with the new schema.
2. Copy and validate data.
3. Update application code compatibly.
4. Rename or retire the old table in a later migration.
5. Do not combine all risky steps into an untested production deploy.

### Production backup habit

Before a meaningful migration, export or copy production data and retain the backup outside the repository. Never commit a backup containing tokens or personal records.

---

## 8. State transitions and concurrency

Allowed transitions:

```text
clocked_out + clock-in  -> clocked_in  + insert clock_in event
clocked_in  + clock-in  -> clocked_in  + no insert
clocked_in  + clock-out -> clocked_out + insert clock_out event
clocked_out + clock-out -> clocked_out + no insert
```

The state check, event insert, processed-request insert, and state update must act as one logical unit. Protect against this race:

```text
widget: clock-in request starts
app:    clock-in request starts before widget finishes
```

Required protections:

- unique `request_id`;
- atomic D1 batch/transaction behavior where supported by the chosen Worker/D1 API;
- conditional state/version update or another single-writer strategy;
- retry-safe responses;
- tests that fire two equivalent requests concurrently.

Never depend on the widget or app cache to decide whether a server transition is legal.

---

## 9. Edge cases checklist

### Requests and state

- Same request delivered twice.
- Two different clock-in requests arrive nearly simultaneously.
- Clock-in while already clocked in.
- Clock-out while already clocked out.
- App succeeds but loses the HTTP response.
- Client times out while the server commits successfully.
- User taps both widget buttons rapidly.
- Widget displays stale cached state.
- Invalid or unknown `source`.
- Missing, malformed, reused, or extremely long request ID.

### Time

- Device clock is wrong.
- Daylight-saving transition in `Europe/Warsaw`.
- Shift crosses midnight.
- Shift crosses a month boundary.
- Historical manual time includes an explicit offset or is converted carefully from local time.
- Extremely long shift.
- Clock-out timestamp precedes clock-in.
- Two events have the same timestamp.

Initial reporting rule: pair in UTC, calculate duration in UTC, and assign the full shift to the local date on which it started. Revisit only if real usage requires split-at-midnight reporting.

### Data quality

- Unmatched clock-in.
- Consecutive clock-ins in imported/manual data.
- Consecutive clock-outs.
- Manual shift overlaps an existing shift.
- Duplicate manual backfill.
- Correction required after an incorrect clock action.
- Database migration partially fails.

### Mobile and network

- No internet connection.
- API returns 401, 409, 429, or 500.
- Flutter app is resumed after widget use.
- Widget process is recreated by Android.
- Authentication token is absent after reinstall.
- User taps while a request is already in progress.

In v0.1, do not queue offline clock actions. Show failure clearly and allow retry. An offline queue introduces difficult timestamp and duplicate semantics.

---

## 10. Security requirements

### Required for v0.1

- HTTPS only.
- Long random bearer token for the device.
- Separate admin token for historical/manual operations.
- Tokens stored as Worker secrets where relevant, never regular repository variables.
- Device token stored securely on Android.
- Token hash, not plaintext token, stored in D1.
- Constant-time token/hash comparison where practical.
- Server-generated normal event timestamps.
- Request body size limit.
- Strict JSON schema validation.
- Fixed allow-list for `source` and `event_type`.
- Parameterized D1 statements only.
- Rate limits for write and admin endpoints.
- No secrets or full authorization headers in logs.
- No stack traces in production responses.
- Minimal CORS policy. Native mobile clients do not need permissive browser CORS.
- Spreadsheet formula-injection protection later: escape text cells beginning with `=`, `+`, `-`, or `@`.

### Credential model

- A token identifies the device server-side.
- The `source` field is telemetry, not authentication. A caller can lie about it.
- The admin token must not be embedded in the production app or widget.
- Keep manual-entry tooling on the development machine or invoke it from a protected workflow.

### If a token leaks

1. Disable the affected device record.
2. Generate a new token.
3. Store its hash in D1.
4. Update secure storage on the device.
5. Review events created since the suspected leak.

---

## 11. Flutter and Riverpod design

Recommended layers:

```text
UI
  -> Riverpod AsyncNotifier/Provider
      -> TimeTrackingRepository
          -> ApiClient
              -> Worker API
```

Suggested providers:

- `apiClientProvider`
- `timeTrackingRepositoryProvider`
- `currentStatusProvider`
- `todaySummaryProvider`
- `monthSummaryProvider` in v0.2
- `recentEventsProvider` in v0.2

Refresh status:

- at startup;
- when the app returns to foreground;
- after an in-app clock command;
- after manual correction;
- on pull-to-refresh.

After an in-app command, use the returned authoritative state immediately. Do not require an unnecessary second request, but refetch on later resume.

Disable the pressed action while its request is in flight. If a response is uncertain because of timeout, refetch status before offering another action.

---

## 12. Android widget design

The widget is an independent API client. It does not send a message through Flutter to record an event.

Responsibilities:

1. Generate a UUID request ID.
2. Call the explicit clock-in or clock-out endpoint.
3. Wait for the server response.
4. Cache the returned display state for convenience.
5. Show success, already-in-state, or failure clearly.
6. Refresh from `GET /status` when Android refreshes the widget.

The widget's displayed state may be stale. Only the API can authorize a transition.

Keep v0.1 visually simple:

```text
Work Hours
Clocked in since 08:13
[ CLOCK IN ] [ CLOCK OUT ]
Last synced 08:13
```

Do not claim success optimistically before a 2xx response.

---

## 13. Cloudflare setup

### One-time setup

```bash
cd worker
npm install
npx wrangler login
npx wrangler d1 create work-hours-prod
```

Copy the returned D1 database ID into `wrangler.jsonc`:

```jsonc
{
  "name": "work-hours-api",
  "main": "src/index.ts",
  "compatibility_date": "2026-10-03",
  "d1_databases": [
    {
      "binding": "DB",
      "database_name": "work-hours-prod",
      "database_id": "REPLACE_WITH_REAL_DATABASE_ID",
      "migrations_dir": "migrations"
    }
  ]
}
```

Use a separate local D1 database automatically created by Wrangler for local development. Do not point routine local tests at production.

### Worker secrets

Set server-only secrets from the terminal:

```bash
npx wrangler secret put ADMIN_API_TOKEN
npx wrangler secret put DEVICE_TOKEN_PEPPER
```

Do not write their values into `wrangler.jsonc`.

### Initial database setup

```bash
npx wrangler d1 migrations apply work-hours-prod --local
npm test
npx wrangler d1 migrations apply work-hours-prod --remote
npx wrangler deploy
```

Create the first device record through a one-time local provisioning script or a carefully executed parameterized command. Do not create an unauthenticated public registration route just to simplify setup.

### Environments

For v0.1, keep it simple:

- local development database;
- one remote production database.

Add a remote staging environment only when production changes become risky enough to justify it.

---

## 14. GitHub Actions setup

### Repository secrets

In GitHub: **Settings -> Secrets and variables -> Actions**, add:

- `CLOUDFLARE_API_TOKEN`
- `CLOUDFLARE_ACCOUNT_ID`

Later, for reports:

- `REPORT_API_TOKEN`
- `RESEND_API_KEY`
- `REPORT_EMAIL_TO`

Create a narrowly scoped Cloudflare API token that can deploy the intended Worker and manage the intended D1 resource. Do not use a global API key.

### CI workflow

`.github/workflows/ci.yml` should run on pull requests and pushes:

```yaml
name: CI

on:
  push:
  pull_request:

permissions:
  contents: read

jobs:
  worker:
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: worker
    steps:
      - uses: actions/checkout@v6
      - uses: actions/setup-node@v6
        with:
          node-version: 24
          cache: npm
          cache-dependency-path: worker/package-lock.json
      - run: npm ci
      - run: npm run typecheck
      - run: npm test

  flutter:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
      - uses: subosito/flutter-action@v2
        with:
          channel: stable
          cache: true
      - working-directory: mobile
        run: flutter pub get
      - working-directory: mobile
        run: flutter analyze
      - working-directory: mobile
        run: flutter test
```

Pin action versions more strictly later if desired. Do not expose deployment secrets to pull-request jobs.

### Deployment workflow

`.github/workflows/deploy-worker.yml`:

```yaml
name: Deploy Worker

on:
  push:
    branches: [main]
    paths:
      - "worker/**"
      - ".github/workflows/deploy-worker.yml"
  workflow_dispatch:

permissions:
  contents: read

concurrency:
  group: work-hours-production
  cancel-in-progress: false

jobs:
  deploy:
    runs-on: ubuntu-latest
    environment: production
    defaults:
      run:
        working-directory: worker
    steps:
      - uses: actions/checkout@v6
      - uses: actions/setup-node@v6
        with:
          node-version: 24
          cache: npm
          cache-dependency-path: worker/package-lock.json
      - run: npm ci
      - run: npm run typecheck
      - run: npm test

      - name: Apply pending D1 migrations
        run: npx wrangler d1 migrations apply work-hours-prod --remote
        env:
          CLOUDFLARE_API_TOKEN: ${{ secrets.CLOUDFLARE_API_TOKEN }}
          CLOUDFLARE_ACCOUNT_ID: ${{ secrets.CLOUDFLARE_ACCOUNT_ID }}

      - name: Deploy Worker
        uses: cloudflare/wrangler-action@v4
        with:
          apiToken: ${{ secrets.CLOUDFLARE_API_TOKEN }}
          accountId: ${{ secrets.CLOUDFLARE_ACCOUNT_ID }}
          workingDirectory: worker
          command: deploy
```

Rationale for migration before deploy: additive, backward-compatible migrations make the new schema available before new code requires it. For breaking changes, use an expand-and-contract sequence across multiple releases.

### Monthly report workflow for v0.3

Run it daily and let the script decide whether a report is due and already sent. Include `workflow_dispatch` for testing. GitHub scheduled workflows use UTC, so scheduling daily avoids fragile month-end and daylight-saving calculations.

```yaml
name: Monthly Report

on:
  schedule:
    - cron: "15 7 * * *"
  workflow_dispatch:
    inputs:
      month:
        description: "Optional month in YYYY-MM format"
        required: false

permissions:
  contents: read

jobs:
  report:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
      - uses: actions/setup-python@v6
        with:
          python-version: "3.13"
          cache: pip
      - run: pip install -r reporting/requirements.txt
      - run: python reporting/send_report.py
        env:
          REPORT_API_TOKEN: ${{ secrets.REPORT_API_TOKEN }}
          RESEND_API_KEY: ${{ secrets.RESEND_API_KEY }}
          REPORT_EMAIL_TO: ${{ secrets.REPORT_EMAIL_TO }}
          REQUESTED_MONTH: ${{ inputs.month }}
```

The report script must use a D1 report-run record or protected API operation to guarantee that retries do not send the same scheduled report twice.

---

## 15. Testing requirements

### Worker unit/integration tests

At minimum:

- clock-in from clocked-out;
- repeated clock-in;
- clock-out from clocked-in;
- repeated clock-out;
- duplicate request ID;
- two simultaneous clock-ins;
- unauthorized request;
- disabled device;
- invalid source;
- malformed body;
- manual valid shift;
- manual reversed timestamps;
- manual overlapping shift;
- unmatched event detection;
- month boundary;
- daylight-saving boundary.

### Flutter tests

- loading, success, already-in-state, unauthorized, and network-error UI;
- button disabled while request runs;
- state refresh on successful command;
- duration formatting from integer seconds;
- resume-triggered refresh.

### Before Monday live use

1. Test against local D1.
2. Deploy production.
3. Create the production device credential.
4. Clock in and out several times with test data.
5. Confirm duplicate handling by repeating a request ID.
6. Remove only the test events using a deliberate admin operation or recreate the production database **only before real data begins**.
7. Backfill the already-worked first day.
8. Query events and verify local display times.
9. Use the Flutter app or widget for the Monday test.
10. Keep a manual note that day as a temporary comparison, not as the primary workflow.

---

## 16. Logging and observability

Log:

- generated server request/correlation ID;
- operation name;
- authenticated device ID;
- source;
- result such as `changed`, `no_change`, `unauthorized`, or `validation_error`;
- latency;
- event ID when created.

Do not log:

- bearer tokens;
- token hashes;
- full authorization headers;
- complete request bodies containing secrets;
- SQL statements with sensitive values.

For v0.1, Cloudflare logs plus direct D1 inspection are enough. Do not add a separate monitoring product yet.

---

## 17. Implementation rules for Copilot-assisted coding

When asking Copilot to implement a task:

1. Reference this document and the exact version scope.
2. Ask for one vertical change at a time.
3. Require tests with every state-transition change.
4. Do not accept code that recreates or seeds the production database during deploy.
5. Do not accept client-calculated authoritative timestamps.
6. Do not accept a toggle endpoint.
7. Do not expose the admin token to Flutter or the widget.
8. Review generated SQL and workflow permissions manually.
9. Keep API models shared within each codebase, but do not over-engineer cross-language code generation in v0.1.
10. Update this document when a deliberate architecture decision changes.

Suggested task order:

1. Scaffold Worker and local D1.
2. Add migration and repository layer.
3. Add authentication.
4. Implement status.
5. Implement clock-in and clock-out with idempotency.
6. Add manual historical-entry endpoint.
7. Test races and transition rules.
8. Deploy and seed one device safely.
9. Build minimal Flutter client.
10. Add Android widget.
11. Add CI and production deployment automation.
12. Backfill the first work day and perform Monday test.

---

## 18. Decisions that must remain explicit

Before implementing reporting, record these values in configuration rather than scattering them through code:

- report day of month;
- recipient email;
- expected monthly/weekly hours, if used;
- whether a cross-midnight shift belongs entirely to start date or is split;
- maximum accepted shift length;
- manual-overlap policy;
- retention period for processed request responses;
- report time zone.

Initial defaults:

```text
Time zone: Europe/Warsaw
Cross-midnight attribution: start date
Maximum shift length: 24 hours
Offline queue: disabled
Normal timestamps: server-generated
Manual timestamps: admin-only, explicit ISO 8601
```

---

## 19. Reference documentation

- Cloudflare D1 migrations: https://developers.cloudflare.com/d1/reference/migrations/
- Cloudflare Workers GitHub Actions: https://developers.cloudflare.com/workers/ci-cd/external-cicd/github-actions/
- GitHub Actions secrets: https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/use-secrets

These references should be rechecked when upgrading Wrangler or GitHub Action major versions.
