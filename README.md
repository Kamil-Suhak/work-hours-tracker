# Work Hours Tracker

A low-friction, single-user work hours tracking platform with authoritative server time, Cloudflare D1 persistence, Cloudflare R2 automated reporting, a Flutter mobile client, and a native Android home-screen widget.

---

## Architecture Overview

```text
       +---------------------------------------------+
       |         Android Home-Screen Widget          |
       |             (Kotlin / RemoteViews)          |
       +----------------------+----------------------+
                              |
                              | HTTPS JSON API (Bearer Device Token)
                              v
+-----------------------------+-----------------------------+
|                     Flutter Mobile App                    |
|             (Riverpod State / Dark Modern UI)             |
+-----------------------------+-----------------------------+
                              |
                              | HTTPS JSON API (Device / Admin Token)
                              v
+-----------------------------------------------------------+
|               Cloudflare Worker (TypeScript)              |
|   - Timing-safe SHA-256 Auth & Request Idempotency        |
|   - 5-Minute Undo Grace Window & State Machine Engine     |
|   - Pure JS OpenXML Excel Generator (.xlsx)               |
|   - Scheduled Monthly Cron Worker                         |
+----------------------+----------------------+-------------+
                       |                      |
                       v                      v
          +-----------------------+ +--------------------+
          |     Cloudflare D1     | |   Cloudflare R2    |
          |   (SQLite Edge DB)    | |  (Reports Bucket)  |
          +-----------------------+ +--------------------+
```

---

## Features

### Core Time Tracking & State Engine
- **Authoritative Server Time:** Server generates UTC ISO 8601 timestamps, preventing client-side clock tampering or synchronization drift.
- **Warsaw Timezone Calculations:** Durations and day/month boundaries are accurately computed in `Europe/Warsaw` across daylight saving transitions.
- **Strict Idempotency:** Duplicate or replayed network requests with the same `requestId` return the cached result without creating duplicate database events.
- **Separate Clock In & Clock Out Endpoints:** Explicit state transitions prevent race conditions and accidental toggles.

### Flutter Mobile App
- **Live Elapsed Duration Timer:** Visual real-time ticker updating elapsed shift duration every second.
- **Month-to-Date & Daily Totals:** Clean hours & minutes formatting (`Xh Ym`, e.g. `8h 30m`) matching official reporting standards.
- **In-Shift Notes Card:** Markdown-friendly notes editor with live expanding preview, auto-save during ongoing shifts, and automatic server upload upon clock-out.
- **Undo Grace Window (5 Minutes):** Tapping Clock In or Clock Out reveals an animated undo button with countdown timer; allows 1-tap transactional reversion of accidental actions.
- **Recents Bottom Sheet:** Comprehensive past shifts view with expandable details, notes, and duration badges.
- **Admin Manual Shift Backfill:** Dialog with native date/time pickers and overlap validation to record past or missed shifts.
- **In-App Settings:** Manage API base URL, device token, admin token (with secure local storage), and vibration feedback.

### Native Android Home Screen Widget
- **Independent Kotlin Client:** Communicates directly with the Cloudflare Worker via OkHttp without needing the Flutter runtime active.
- **Real-Time State Mirroring:** Shows current state (`Clocked In` / `Clocked Out`), active duration, and last sync timestamp.
- **Bidirectional Sync:** App clock actions immediately update the widget via Android `MethodChannel`, and widget actions reflect in the app upon foreground resume.

### Reporting Engine & Cloudflare R2
- **Pure-JS OpenXML Generator:** High-performance, zero-dependency `.xlsx` workbook generator running natively inside Cloudflare Workers without Node.js filesystem APIs.
- **Side-by-Side Tables:** Renders the Shift Log table horizontally adjacent to the Summary Statistics table with independent column widths to autofit text cleanly.
- **Automated Monthly Cron:** Cloudflare Worker cron trigger runs at midnight UTC on the 1st of every month, generates the previous month's report, and stores it in a Cloudflare R2 bucket (`work-hours-reports`).
- **On-Demand Custom Reports:** Select custom date ranges via native Android date pickers with presets (`Formal` vs `Full`) and fine-grained options (include notes, summary statistics, source breakdown).
- **Direct Android Intent Opener:** Generated reports are cached locally and opened immediately in Microsoft Excel, Google Sheets, or any compatible viewer via Android `ACTION_VIEW` FileProvider.

---

## Repository Structure

```text
work-hours-tracker/
├── .github/
│   └── workflows/
│       ├── ci.yml                 # CI for Worker and Flutter on push/PR
│       └── deploy-worker.yml      # Automated D1 migration + Worker deployment
├── worker/
│   ├── src/
│   │   ├── index.ts               # Worker router, security headers, cron dispatcher
│   │   ├── auth.ts                # Timing-safe SHA-256 token verification
│   │   ├── clock.ts               # Clock-in / clock-out logic & idempotency
│   │   ├── undo.ts                # 5-minute undo state reversion engine
│   │   ├── events.ts              # Events query & admin manual backfill
│   │   ├── status.ts              # Status endpoint & Warsaw duration calculations
│   │   ├── reports/
│   │   │   ├── excel_generator.ts # Pure JS OpenXML .xlsx generator & ZIP builder
│   │   │   └── report_service.ts  # R2 report storage, cron, and query service
│   │   ├── errors.ts              # Standardized API error responses
│   │   └── types.ts               # Domain interfaces and API contracts
│   ├── migrations/
│   │   ├── 0001_initial.sql       # D1 schema: devices, work_state, events, processed_requests
│   │   └── 0002_add_notes_and_undo.sql # Notes column and undo tracking
│   ├── scripts/
│   │   └── provision-device.ts    # Secure device token generation script
│   ├── test/                      # Vitest unit and integration test suites
│   ├── package.json
│   ├── tsconfig.json
│   └── wrangler.jsonc             # Cloudflare Worker config, D1, R2, and Cron triggers
├── mobile/
│   ├── lib/
│   │   ├── api/                   # HTTP client and models
│   │   ├── features/
│   │   │   ├── clock/             # Clock screen, live timer, shift notes card, undo button
│   │   │   ├── history/           # Recent shifts bottom sheet, manual shift dialog
│   │   │   ├── reports/           # Reports screen, native date pickers, report file service
│   │   │   └── settings/          # Settings dialog, preferences, widget sync service
│   │   └── main.dart              # App entry point & lifecycle observer
│   ├── android/                   # Native Android host, widget receiver, and FileProvider
│   └── test/                      # Unit and widget test suites
├── DESIGN.md                      # Ground-truth design specification
└── README.md
```

---

## Setup Instructions

### 1. Prerequisites
- **Node.js:** v18+ (Node.js 20+ recommended)
- **Cloudflare Wrangler CLI:** `npm install -g wrangler`
- **Flutter SDK:** 3.24+
- **Android SDK:** API level 34+ (for Android builds)

---

### 2. Cloudflare Worker Setup

#### Install Dependencies
```powershell
cd worker
npm install
```

#### Run Tests & Typechecks
```powershell
npm run typecheck
npm test
```

#### Create Cloudflare D1 Database & R2 Bucket
```powershell
# Log in to Cloudflare
npx wrangler login

# Create production D1 database
npx wrangler d1 create work-hours-prod

# Create R2 bucket for automated monthly reports
npx wrangler r2 bucket create work-hours-reports
```

Update `worker/wrangler.jsonc` with your assigned `database_id`:
```jsonc
"d1_databases": [
  {
    "binding": "DB",
    "database_name": "work-hours-prod",
    "database_id": "<YOUR-DATABASE-ID-HERE>",
    "migrations_dir": "migrations"
  }
],
"r2_buckets": [
  {
    "binding": "REPORTS_BUCKET",
    "bucket_name": "work-hours-reports"
  }
],
"triggers": {
  "crons": ["0 0 1 * *"]
}
```

#### Apply Database Migrations
```powershell
# Apply locally for Vitest / local dev
npx wrangler d1 migrations apply work-hours-prod --local

# Apply to Cloudflare production database
npx wrangler d1 migrations apply work-hours-prod --remote
```

#### Configure Production Secrets
```powershell
npx wrangler secret put ADMIN_API_TOKEN
npx wrangler secret put DEVICE_TOKEN_PEPPER
```

#### Provision Device Token
Generate a cryptographically secure bearer token for your mobile device:
```powershell
npm run provision -- "primary-phone"
```
Keep the generated bearer token safe—you will enter it into the mobile app's settings.

#### Deploy Worker
```powershell
npx wrangler deploy
```

---

### 3. Mobile App Setup

#### Install Dependencies
```powershell
cd mobile
flutter pub get
flutter test
```

#### Run App in Debug Mode
Connect your Android phone via USB with USB debugging enabled, then execute:
```powershell
flutter run --debug
```

#### Initial Configuration Inside App
1. Open the app and tap the **Settings** icon (top right).
2. Enter your Cloudflare Worker URL: `https://your-worker.<subdomain>.workers.dev`.
3. Paste the **Device Token** generated by the provision script.
4. (Optional) Paste the **Admin Token** to enable past shift backfills.
5. Tap **Save Settings**.
6. The app will immediately sync with the server and display your current status.

#### Adding the Android Home Screen Widget
1. Long-press an empty space on your Android home screen and select **Widgets**.
2. Scroll to **Work Hours Tracker**.
3. Drag the widget to your home screen. The widget will read credentials from the app and mirror your active status.

---

## API Reference

All requests must use HTTPS and include appropriate headers:

```http
Authorization: Bearer <device-token>
Content-Type: application/json
```

| Method | Endpoint | Auth | Description |
| :--- | :--- | :--- | :--- |
| `POST` | `/api/v1/clock-in` | Device | Record shift start. Accepts `requestId`, `source`. Safe to retry. |
| `POST` | `/api/v1/clock-out` | Device | Record shift end. Accepts `requestId`, `source`, optional `note`. |
| `POST` | `/api/v1/undo` | Device | Revert latest clock action within 5-minute grace window. |
| `GET` | `/api/v1/status` | Device | Return authoritative state (`clocked_in`/`clocked_out`), durations. |
| `GET` | `/api/v1/events` | Device | Query raw events within range (`?from=...&to=...`). |
| `POST` | `/api/v1/admin/events/manual` | Admin | Backfill or repair past shifts with reason and overlap check. |
| `POST` | `/api/v1/reports/generate` | Device | Generate on-demand `.xlsx` binary report for date range & preset. |
| `GET` | `/api/v1/reports/latest` | Device | Return metadata & download URL for latest automated monthly report. |
| `GET` | `/api/v1/reports/download/:filename` | Device | Securely stream `.xlsx` report file stored in Cloudflare R2 bucket. |

---

## Future Roadmap

Prioritized based on personal daily utility:

### Phase 5: Web Dashboard (PC Access)
- **Flutter Web Build:** Deploy the existing Flutter codebase as a responsive web app hosted on Cloudflare Pages.
- **Shared Codebase:** 95% code reuse across Riverpod state management, API client, models, and UI components.
- **Desktop Workflow:** Seamlessly clock in/out and view recent shifts directly from your browser when working on a PC.

### Phase 6: Expected Shift Duration & Clock-Out Reminders
- **Shift Duration Target:** Option when clocking in to select an expected shift length (e.g. 8h default, or chips for 4h, 6h, 8h, 8h 30m).
- **Progress Gauge:** Visual bar indicating progress toward today's target duration.
- **Local Overtime Notifications:** Android local notifications (`flutter_local_notifications`) alerting when your planned shift duration is reached.

### Phase 7: Productivity Insights & Quick Notes
- **Weekly Pace Bar:** High-level gauge showing week-to-date hours vs weekly goal (e.g. 40 hours).
- **Quick Tag Templates:** One-tap tags in shift notes (e.g., `#remote`, `#meeting`, `#planning`, `#review`).
- **Inline Note Editing:** Ability to add or edit notes on past shifts directly from the Recents list without a full administrative backfill.

### Phase 8: Data Backups & Maintenance Tooling
- **Automated D1 Snapshot Script:** Lightweight scheduled script / CLI helper to export D1 events to local JSON or SQLite dump (`wrangler d1 export`).
- **CSV / JSON Raw Export:** Endpoint to export raw shift event logs for personal data backups.

---

### Explicit Non-Goals (Omitted by Design)
To keep the tool fast, robust, and low-maintenance:
- **No Complex Offline SQLite Outbox:** Unnecessary given persistent mobile connectivity; server remains single source of truth.
- **No Multi-User / Enterprise Team Features:** Single-user focus keeps the architecture simple and secure.
- **No Location / GPS Tracking:** Privacy-focused; manual source tagging is sufficient.