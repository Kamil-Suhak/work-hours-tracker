# Changelog

All notable changes to the Work Hours Tracker project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [1.3.0] - 2026-11-12

### Added
- **Server-Authoritative Shift Target & Lazy Auto-Stop:** Added D1 migration `0004_add_target_clock_out.sql` (`work_state.target_clock_out_utc`), optional `targetMinutes` on `POST /api/v1/clock-in`, and `PATCH /api/v1/shift/target` supporting relative `deltaMinutes` nudges, explicit `targetMinutes`, or clearing the target. Any authenticated Worker request (and the monthly cron) materializes `clock_out` at `max(activeSince, targetClockOutUtc)` with reason `"Auto-stopped at target"` when due.
- **Flutter Target Controls & Notification Sync:** Added quick `-10m` / `+10m` nudge buttons and `ShiftTargetDialog` in the active tracker UI, synchronized shift-end reminder notifications with live `targetClockOutUtc` updates, and triggered status refresh when reaching the target.
- **Direct D1 Shift CLI (`db:shift`):** Added `worker/scripts/shifts.mjs` (`npm --prefix worker run db:shift`) to `list`, `add`, `edit`, `close`, and `delete` shifts directly in Cloudflare D1 with `Europe/Warsaw` parsing, overlap validation, automatic `work_state` resynchronization, and dry-run output by default (`--apply` to execute writes).

### Removed
- **Admin Backfill API & UI:** Removed `POST /api/v1/admin/events/manual`, `ADMIN_API_TOKEN` verification/config, `ManualShiftDialog`, legacy admin token storage, and client-only `plannedShiftProvider`.

### Fixed & Hardened
- **Worker Concurrency & Route Safety:** Guarded `handleClockIn`, `handleClockOut`, and `handleUndo` `db.batch()` writes with optimistic `work_state.version` / existence predicates and concurrent idempotency replay; filtered auto-stop lookup to `clock_in` events; added safe path segment decoding (`400 VALIDATION_ERROR`) and auth checks ahead of unknown-route `404` responses.
- **Client & Widget Reliability:** Fixed `SettingsNotifier.isConfigured` token/URL validation and legacy key cleanup, serialized `ShiftNotesCard` draft saves across active shifts, throttled auto-stop status polling in `CurrentShiftTimerCard`, bounded `ShiftsNotifier` future queries, surfaced fallback `reason` strings in `RecentShiftsView`, and guarded Android widget status handling in `WorkHoursWidgetReceiver`.

### Changed
- **Version Bumps:** Bumped Flutter bundle version to `1.3.0+15`, synchronized `AppConfig.appVersion` (`1.3.0`) for the Android update check badge, and bumped Cloudflare Worker API to `1.3.0`.

---

## [1.2.6] - 2026-11-06

### Fixed
- **Minute-Truncation Parity Between Frontend & Backend:** Added `_truncateToMinute` in `ReportsScreen` so event clock-in and clock-out timestamps have seconds and milliseconds stripped prior to difference calculation. Prevents 1-minute truncation shortfalls across multi-shift months where `clockOut.second < clockIn.second`, guaranteeing exact agreement with backend `pairShifts` (e.g. October 80h 0m target met).
- **Past-Month Forecasting Guard:** Disabled forecasting on historical months. Past months display an informative status badge (`Contract Target Met` or `Contract Target Not Met`) and disable the interactive forecast dialog.
- **Current-Month Forecasting Range Constraint:** Constrained `PlanFutureShiftsDialog` to only present today and future days of the active month (`now.day .. lastDay`), completely preventing forecasting on elapsed days.
- **Omit Out-of-Month Forecasts:** Ensured formal report requests never attach planned shifts when generating reports for past months.

---

## [1.2.5] - 2026-11-05

### Added
- **Formal Contract `.docx` Integer Hour Redistribution:** Implemented a zero-sum, largest-remainder integer redistribution algorithm (`redistributeIntegerHours`) for the attendance annex table (`Załącznik`). Daily shifts are rounded to integer hours (1h minimum, 9h maximum cap) with minute remainders allocated by highest remainder (ties broken by earlier calendar date), ensuring the monthly sum strictly equals the contract requirement (`80h`). Formatted table attendance hours and Rachunek monthly hours as plain integers (e.g. `8`, `80`).
- **Fixed Rachunek Signing Date:** Guaranteed the signing date on Page 2 (`Rachunek do umowy zlecenia`) is always the 30th day of the month (`${issuePlace}, ${YYYY-MM-30}`), independent of calendar length or generation day.
- **Target Signature Extents:** Scaled handwritten signature OpenXML drawing dimensions to match target document specifications (`cx="812959" cy="301096"` in table cells; `cx="1152842" cy="433149"` in Rachunek footer).
- **Full Reporting (`.xlsx`) DrawingML Charts:** Added pure OpenXML zero-dependency chart generation to full Excel reports:
  - *Daily Work Hours*: Clustered column/bar chart (`xl/charts/chart1.xml`) plotting hours worked across shift dates.
  - *Location Breakdown*: Doughnut chart (`xl/charts/chart2.xml`) breaking down hours worked between Remote and In-Office locations.
  - Added numeric `Hours` column to the shift data table with dynamic `SUM` formula in the total row and a dedicated location summary table.
- **Contract Profile Endpoint:** Added `GET /api/v1/reports/contract-profile` returning contractor metadata and required monthly hours.

### Changed
- **Reports Screen 3-Button Architecture:** Streamlined the reports UI to exactly three unambiguous, distinctly labeled buttons with no confusing helper text or duplicate controls:
  1. Formal Report Card: Single `Generate & Download Formal Report` button.
  2. Full Report Card: `Generate & Download Full Report` button for custom date ranges.
  3. Full Report Card: `Download Auto-Generated Report` button for scheduled 1st-of-month archives.
- **Contract Target Gating & Interactive Forecast Status:** Added a contract progress status tile in the Formal Report Card that calculates worked plus planned hours against the contract profile. The formal report button remains strictly disabled until worked + forecasted hours equal the contract target (`80h`). Tapping the status tile opens an improved `PlanFutureShiftsDialog` allowing users to forecast remaining days up to the exact target.
- **Removed Orphaned Code:** Cleaned up redundant "Open Last Report" buttons (files open automatically upon download), duplicate archive download controls in the formal card, and orphaned report state variables.
- **Version Bumps:** Bumped Flutter bundle version to `1.2.5+13` and Cloudflare Worker API to `1.2.5`.

---

## [1.2.4] - 2026-10-30

### Added
- **Production Keystore Signing in CI Pipeline:** Configured Android Gradle release signing via environment variables (`KEYSTORE_PATH`, `KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD`) and GitHub Actions secret decoding (`ANDROID_KEYSTORE_BASE64`). Enables consistent release certificate signing to prevent Play Protect untrusted warnings and allows seamless in-place APK updates on Android without uninstalling or losing data.
- **Android Version Check Badge:** Added an understated version indicator in the Settings dialog on Android (`!kIsWeb && defaultTargetPlatform == TargetPlatform.android`). Dynamically fetches the latest release from GitHub Releases API with a 4-second timeout, formatting as `Latest version: <latest> | Current version: <current>`. Highlights the latest version in yellow when an update is available and in green when up-to-date. Tapping the badge opens the latest release page on GitHub.

### Changed
- **Version Bumps:** Bumped application configuration, Flutter bundle version (`1.2.4+12`), and Cloudflare Worker API to `1.2.4`.

---

## [1.2.3] - 2026-10-28

### Added
- **Clickable Past Shift Note Editing in Web Quadrants:** In the 4-quadrant desktop web view, clicking any past shift in the Recent Shifts quadrant directly mounts that shift's notes in the left editor and markdown preview quadrants for viewing or editing. Disallows typing if clocked out with no past shift selected while allowing editing/adding notes for past shifts at any time. Automatically persists active shift note drafts, and handles the dual-save edge case if clocking out while editing a past shift note.
- **Dynamic Note Editor Headers & Relocated Clear Button:** Renamed the active note title to dynamic labels (`Notes | Current Shift` or `Notes | Shift on <Date>`). Moved the "Clear Note" button to the top-right corner of the editor quadrant header.
- **Environment Isolation & Locked API Base URL:** Removed the editable Worker URL text field from Settings, replacing it with a styled, non-editable API Base URL card displaying compile-time endpoints (`AppConfig.defaultApiBaseUrl` and `AppConfig.stagingApiBaseUrl`) with copy-to-clipboard functionality and lock icon. Isolated device Bearer tokens, admin API tokens, reminder offsets, and vibration preferences in separate secure storage per environment. Enclosed all environment-specific settings collectively within animated transitions (`AnimatedSwitcher`).
- **Web & Mobile Shift Notifications:** Implemented web notifications using HTML5 Notification API with background timer triggers and permission requests. Resolved mobile exact alarm scheduling crashes on Android 12+ (API 31+) by falling back to `setAndAllowWhileIdle` when exact alarm permission is ungranted, adding `USE_EXACT_ALARM`, and pre-creating the notification channel on startup.
- **Automated R2 Storage Discovery on Screen Load:** `ReportsScreen` automatically queries Cloudflare R2 on load via `/api/v1/reports/latest`. If automated monthly archives exist in R2, download buttons are prominently rendered on the report cards; if no archives exist, the download buttons are cleanly omitted without false error toasts.
- **Scaled Contract Report Signature Image:** Scaled the handwritten signature PNG embedded in formal contract `.docx` reports by 1.5x (`1_275_000` x `270_000` EMU for table cells; `1_725_000` x `435_000` EMU for rachunek footer) while strictly preserving aspect ratio.
- **Emerald Clock Favicon:** Added SVG favicon (`favicon.svg`) with dark slate plate and emerald clock dial for the web client.

### Changed
- **Quadrant Title Clarifications:** Renamed `'Live Markdown Preview'` to `'Markdown Preview'` and streamlined timer card sync label to `'Last synced'`. Removed character and word counter display from the web markdown note editor.
- **Version Bumps:** Bumped application configuration, Flutter bundle version (`1.2.3+11`), and Cloudflare Worker API to `1.2.3`.

---

## [1.2.2] - 2026-10-26

### Added
- **Custom Duration Text Input for Shift Planning:** Replaced the `+/- 30m` step buttons and 6h pills in `PlanFutureShiftsDialog` with a compact inline text input (`hintText: '0h 0m'`) on each remaining day row. Supports flexible input formats (`0h 0m`, `2h 30m`, `6h`, `45m`, `7:30`, `2.5`, `2,5`), highlights custom durations with an active indigo border, and seamlessly synchronizes with live planned/projected total indicators and duration chips (`Off`, `4h`, `8h`).
- **Simultaneous Side-by-Side Reports View:** Redesigned the desktop/tablet view of `ReportsScreen` to display both the Formal Contract Report and Excel Data Report simultaneously side-by-side, maximizing horizontal and vertical screen space and allowing immediate configuration and generation of both reports without tab switching.
- **Application Screenshots in Documentation:** Added rich visual walkthrough screenshots to `README.md` covering the main dashboard, active shift stopwatch, duration & location selection, custom clock offsets, multi-environment settings, and the side-by-side reports layout.

### Changed
- **Server Sync Label Simplification:** Streamlined the Clock Screen authoritative server time indicator to concise `"Last synced: <time>"` text.
- **Version Bumps:** Bumped application metadata, Flutter configuration (`1.2.2+10`), and Worker API version to `1.2.2`.

---

## [1.2.1] - 2026-10-22

### Added
- **Reports Screen Split Tabs & Layout Overhaul:** Redesigned `ReportsScreen` into a clean 2-tab view (`Formal Report` and `Excel Report`), properly utilizing vertical space on desktop with centered, constrained cards and reasonably sized generate buttons (`280px`).
- **Last 6 Months Quick-Select Dropdown:** Replaced quick pills with a dedicated month-name dropdown (e.g. *October 2026*, *September 2026*) on both the Formal and Excel report tabs.
- **Visual Split-Button for Clock Controls:** Added a subtle vertical divider inside `ClockActionButton` separating the primary action label from the dropdown arrow. Left target triggers regular clock in/out; right arrow target opens offset options (`-5m`, `Now`, `+5m`, `Custom...`) with a single click/tap on desktop or phone.
- **Settings Dialog Transitions & Staging Web Link:** Added an animated horizontal slide/fade transition (`AnimatedSwitcher`) when toggling between Production and Staging environments, along with a direct action button to open the Staging web client in the browser.
- **CI / CD Pipeline Staging Gate:** Structured GitHub Actions workflow to run full Worker & Flutter CI first, build and deploy to Staging, and only then proceed with Production deployment.

### Changed
- **Removed File Extensions & Redundant Badges:** Stripped `.DOCX` and `.XLSX` from all headers, buttons, dialogs, and snackbars, removed the `Umowa Zlecenie` badge, and clarified automated archive downloads as `"Download Latest Automated Report"`.
- **Symmetrical Formal Date Range:** Rendered side-by-side Start Date and End Date cards on the Formal Report tab to match the Excel Report layout, secured with subtle lock icons.
- **Desktop & Mobile Timer Card Typography:** Removed redundant History button from the desktop quadrant view (`CurrentTrackerQuadrant`), enlarging the Month-to-date total in its place (`22px`), and separated the Month to Date label and value onto centered individual lines for mobile.

---

## [1.2.0] - 2026-10-22

### Added
- **Formal Contract `.docx` Report Automation:** Added zero-dependency OpenXML `.docx` generation (`worker/src/reports/docx_generator.ts`) that populates `templates/umowa-zlecenie.docx` from Cloudflare R2 (`Załącznik` 23-row attendance table + `Rachunek do umowy zlecenia`) with daily aggregated hours (`date | 0h0m | signature PNG | empty | empty`), contractor profile metadata (`templates/contract-profile.json`), and embedded handwritten signature (`templates/signature.png`).
- **Plan Remaining Shifts Dialog (`PlanFutureShiftsDialog`):** Added an interactive dialog in the Flutter app when generating the Formal Contract Report (`.docx`) to plan remaining shifts of the current month (e.g. 26th–31st), displaying live `Recorded + Planned = Projected Total` hours and weekday quick-fill presets.
- **Exact Warsaw Month & Custom Range Boundaries:** Added `getCurrentWarsawMonthRangeUtc` and `warsawDateRangeToUtc` in `worker/src/status.ts` so formal `.docx` reports lock to the exact current `Europe/Warsaw` month without boundary clipping or cross-month leakage, and `.xlsx` reports filter shifts accurately by Warsaw calendar date.

### Changed
- **Separated Formal `.docx` & Full Excel `.xlsx` Reports:** Split `ReportsScreen` into a dedicated Formal Contract Report (`.docx`) card (locked to the full current month) and an Excel Data Report (`.xlsx`) card (with custom date range and quick chips).
- **Full-Featured Excel Reports by Default:** Standardized both manual and scheduled 1st-of-month cron (`0 0 1 * *`) `.xlsx` reports to always include all database fields (`Date`, `Start Time`, `End Time`, `Duration`, `Location`, `Source`, `Shift Notes`) and `Summary Statistics`.

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
