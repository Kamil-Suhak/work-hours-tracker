# Changelog

All notable changes to the Work Hours Tracker project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [1.1.3] - 2026-10-22

### Added
- **Shift Work Location (`remote` | `in-office`):** Added work location selection on every shift when clocking in (`PlannedShiftDialog`) or backfilling manually (`ManualShiftDialog`), displayed as a `Remote` / `In-Office` badge in `RecentShiftsView`, and backed by D1 migration `0003_add_location_to_events.sql` (defaulting historical rows to `'remote'`).

### Changed
- **Minute-Precision Time Standardization:** Standardized timestamp recording and duration calculation across the Cloudflare Worker, Excel report generator, and Flutter client to operate at 1-minute precision (`YYYY-MM-DDTHH:MM:00.000Z`), keeping seconds exclusively on the live `CURRENT SHIFT TIMER` readout.
- **Consistent Shift & Summary Totals:** Unified shift pairing (`pairShifts`, `pairEventsIntoReportShifts`, `pairEventsIntoShifts`) and duration formatting (`formatDuration`, `formatSeconds`) so that a shift starting at `17:00` and ending at `21:00` always evaluates to `4h 0m` across the Recent Shifts view, Today's total, Month-to-date total, and `.xlsx` reports.
- **Live Today & Month-to-Date Sync:** Updated `CurrentShiftTimerCard` to advance `Today` and `Month to date` totals in lockstep with minute boundaries while clocked in, and trimmed seconds from progress bar overtime/remaining indicators and the Undo confirmation dialog.
- **Custom Clock Offset Dialog Refinement:** Simplified offset preset chips to `±5m`, `±15m`, and `±30m` (removing `±10m`), added inline min/max range helper and live validation (`-120` to `+120` min / `±2h`), and fixed preset chip selection state when typing out-of-range values manually.

---

## [1.1.2] - 2026-10-12

### Added
- **Multi-Environment Support (Prod & Staging):** Added staging D1 database (`work-hours-staging`), R2 bucket (`work-hours-reports-staging`), and in-app Environment Switcher with isolated credential storage.
- **Planned Shift Duration & Reminders:** Added `PlannedShiftDialog` (4h, 6h, 8h, custom), glowing progress/overtime bar in `CurrentShiftTimerCard`, and configurable Android shift-end reminder notifications.
- **Clock Time Offset Support:** Added `-5m`, `+5m`, and custom (`-120m` to `+120m`) offset options on long-press of Clock In / Clock Out buttons.

### Fixed
- **Undo Window Calculation:** Evaluated the 5-minute undo grace period against transaction creation time (`created_at_utc`) rather than offset occurrence time (`occurred_at_utc`).
- **Environment Switch Cache & Error Surfacing:** Cleared cached status on environment switch and surfaced API/connection errors in `ClockScreen` and `SettingsDialog`.

---

## [1.0.1] - 2026-10-05

### Added
- **Markdown Preview Code Blocks & Checkboxes:** Render multi-line fenced code blocks with dark cyber styling and task checklists (`- [ ]` / `- [x]`) with checked/unchecked icons and strike-through.
- **Auto-Continuing Bullet & Task Lists:** Note editor automatically inserts `- ` or `- [ ] ` on Enter when continuing lists, and exits the list when Enter is pressed on an empty item.

### Fixed
- **Recent Shifts Scrollbar:** Added visible, interactive desktop/web scrollbar to the recent shifts quadrant.
- **Markdown Toolbar Cursor Positioning:** Tapping formatting buttons retains editor focus and places the cursor between paired markers (`**|**`) or after prefixes (`## |`).
- **Web Report Opening:** Cached generated report bytes in `WebReportFileService` so the "Open" button opens the report in a new tab with user feedback.
- **Tracker Quadrant View Stability:** Consolidated Current Shift Timer and Month-to-Date/History sections into a side-by-side layout at the same Y level, narrowed and centered action buttons, and prevented scrolling when the Undo button is visible.

---

## [1.0.0-experimental] - 2026-10-05

> **Experimental Release:** Automated tests (backend and client) pass at 100%. Pending manual end-to-end device testing.

### Added
- Consolidated `ROADMAP.md` superseding `POLISH.md`.
- `WIP.md` tracking document for active development.
- `docs/API.md` providing complete API schema, error codes, and contract documentation.
- `docs/DEPLOYMENT.md` providing end-to-end setup, migrations, and D1 backup procedures.
- Multi-platform Riverpod service abstraction architecture (geared towards future iOS support).
- Upgraded Gradle wrapper to 8.14 to satisfy Flutter toolchain requirements.

### Changed
- Refactored platform handling from scattered negative guards (`!isAndroid`) to Riverpod provider-injected service abstractions (`HapticFeedbackService`, `ReportFileService`, `WidgetSyncService`, `CredentialStore`).

### Fixed
- **Warsaw Timezone in Reports:** Corrected monthly report boundaries and local shift times (`startTimeLocal`, `endTimeLocal`) in Excel generator to use `Europe/Warsaw` across DST transitions instead of UTC.
- **Spreadsheet Formula Injection:** Sanitized user text cells in `.xlsx` generator starting with `=`, `+`, `-`, `@` with a neutralizing single quote (`'`).
- **Report Download Path Traversal:** Hardened `GET /api/v1/reports/download/:filename` with strict regex and traversal rejection.
- **Atomic Undo Transaction:** Reorganized `handleUndo` into a single atomic `db.batch` call with optimistic version checks.
- **CORS Scoping:** Scoped API origins dynamically with `Vary: Origin` (worker origin + localhost for dev) instead of wildcard `*`.
- **Web Admin Token Security:** Guarded admin token from persistent browser storage on Web.

---

## [0.3.1] - 2026-10-04

### Added
- **Flutter Web Client:** Responsive web build served via Cloudflare Workers Static Assets (`env.ASSETS`, `run_worker_first: true`).
- **4-Quadrant Desktop Dashboard:** Adaptive layout on desktop viewports (`>= 900px`) rendering Clock, Stats, Recents, and Reports side-by-side.
- **Dynamic Web API Origin:** Client automatically binds to `Uri.base.origin` when running in a browser.
- **Web Blob Downloader:** Browser download helper using temporary object URLs for report files.

### Changed
- Directory rename from `mobile/` to `app/`.
- CI workflow to build Flutter Web assets prior to Worker deployment.

### Fixed
- Web client authentication header handling.
- Center alignment for error containers and silent haptic handling on Web.

---

## [0.3.0] - 2026-10-04

### Added
- **Pure-TypeScript OpenXML Generator:** Zero-dependency `.xlsx` workbook generator running natively in Cloudflare Workers without Node.js filesystem APIs.
- **Cloudflare R2 Bucket Storage:** Storage binding (`work-hours-reports`) for automated and on-demand report workbooks.
- **Automated Monthly Cron:** Scheduled cron trigger (`0 0 1 * *`) generating both `formal` and `full` monthly reports on the 1st of each month.
- **Reporting Endpoints:**
  - `POST /api/v1/reports/generate` for on-demand `.xlsx` generation.
  - `GET /api/v1/reports/latest` returning metadata and month summary.
  - `GET /api/v1/reports/download/:filename` for streaming `.xlsx` files from R2.
- **Mobile Reports UI:** Screen with date pickers, preset toggles (`formal` vs `full`), and summary statistics.
- **Android FileProvider Opener:** Native Android intent bridge (`ACTION_VIEW`) to open `.xlsx` files in Excel or Google Sheets.

---

## [0.2.0] - 2026-10-04

### Added
- **5-Minute Undo Grace Window:** `POST /api/v1/undo` endpoint and animated client countdown button to revert accidental clock actions.
- **Shift Notes:** Markdown-friendly notes editor (`events.note`) with expanding live preview and autosave during active shifts.
- **Manual Shift Backfill:** `POST /api/v1/admin/events/manual` dialog for administrators to insert missed or past shifts with overlap validation.
- **Shift History & Pairing:** Recents bottom sheet grouping clock-in/out event pairs with duration badges.
- **Android Widget Notes Bridge:** Shift notes mirrored to the native Android home-screen widget.
- **Haptic Feedback Toggle:** In-app vibration preferences for clock operations.

### Changed
- Database migration `0002_add_note_to_events.sql` adding `note` column to `events` table.

---

## [0.1.0] - 2026-10-03

### Added
- **Cloudflare Worker Core:** Authoritative server-time state machine in TypeScript.
- **Cloudflare D1 Persistence:** SQLite database schema (`0001_initial.sql`) with tables for `devices`, `work_state`, `events`, and `processed_requests`.
- **Authoritative Clock Endpoints:** Explicit `POST /api/v1/clock-in` and `POST /api/v1/clock-out` endpoints.
- **Device Authentication:** Timing-safe SHA-256 token verification with server secret pepper (`DEVICE_TOKEN_PEPPER`).
- **Request Idempotency:** Duplicate request caching via `requestId` preventing duplicate events on network retries.
- **Flutter Mobile Client:** Riverpod-powered mobile UI with central pulse timer and status display.
- **Native Android Widget:** Kotlin / RemoteViews home-screen widget communicating directly with Worker via OkHttp.
- **Device Provisioning:** CLI script (`scripts/provision-device.mjs`) to generate high-entropy device tokens.
- **API Testing:** Bruno collection for local and remote API testing.
