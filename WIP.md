# Work Hours Tracker — Work In Progress (WIP)

## Current Status & Big Picture
- **State**: Comprehensive review of all 20 sections of `POLISH.md` completed. Consolidated `ROADMAP.md` created to replace `POLISH.md`. No code changes made yet.
- **Goal**: Harden the application base by addressing critical correctness bugs, security risks, and architectural misalignments identified in `POLISH.md` without over-engineering for a single-user system.
- **Guiding Principles**:
  1. Correctness and architectural solidity over cosmetic polish.
  2. Single-user simplicity over enterprise/multi-tenant over-engineering.
  3. Authoritative server time in `Europe/Warsaw`.
  4. Platform service abstractions via Riverpod provider injection (iOS-ready) rather than scattered negative guards.

---

## Progress Tracker

### Phase 1: Core Worker Correctness & Security Hardening
- [x] **Warsaw Timezone in Reports**: Fixed month start/end boundaries and local time formatting in `report_service.ts` and `excel_generator.ts`.
- [x] **Spreadsheet Formula Injection Defense**: Neutralized `=`, `+`, `-`, `@`, `\t`, `\r` formula triggers in note/source/summary text cells before inserting into Excel XML.
- [x] **Report Download Path Traversal**: Sanitized filename route with strict regex and rejection of traversal sequences (`..`, `/`, `\`).
- [x] **Atomic Undo Execution**: Execute undo event deletion, state rollback, and idempotency record within a single atomic `db.batch` transaction.
- [x] **Production CORS Rules**: Scoped allowed origins dynamically with `Vary: Origin`, `X-Content-Type-Options: nosniff`, `Referrer-Policy: strict-origin-when-cross-origin`, and `Cache-Control: no-store`.

### Phase 2: Multi-Platform Service Layer (Flutter App & iOS Readiness)
- [x] **Platform Service Abstractions**: Define abstract interfaces in `app/lib/services/platform/` (`HapticFeedbackService`, `ReportFileService`, `WidgetSyncService`, `CredentialStore`).
- [x] **Concrete Platform Implementations**: Implement Android, Web, and NoOp providers.
- [x] **Presentation Refactoring**: Refactor UI widgets and notifiers to eliminate inline platform checks (`if (!isAndroid)`, `kIsWeb`).
- [x] **Admin Token Web Security**: In-memory credential session for `ManualShiftDialog` on Web.

### Phase 3: Documentation & Design Specification Realignment
- [x] **`ROADMAP.md` Created**: Consolidated roadmap superseding `POLISH.md` (and `POLISH.md` deleted).
- [x] **`CHANGELOG.md` Created**: Backfilled commit history through `v0.1.0`, `v0.2.0`, `v0.3.0`, `v0.3.1`, and `Unreleased`.
- [x] **`docs/API.md` Created**: Complete endpoint contracts, schemas, and error codes.
- [x] **`docs/DEPLOYMENT.md` Created**: Operations runbook for D1, R2, secrets, migrations, and backups.
- [x] **`README.md` Streamlining**: Clean entry point referencing modular docs and technical guarantees.
- [x] **`DESIGN.md` Synchronization**: Updated ground-truth design to match unified Worker Static Assets, R2, and pure TS OpenXML generator.

### Phase 4: Test Coverage & Verification
- [x] **Backend Unit & Integration Tests**: Warsaw DST transitions (March & October), formula injection escaping, undo atomicity, R2 download traversal rejection, dynamic CORS headers, 4000 char note validation (59 Vitest tests passing).
- [x] **Flutter App Validation**: `flutter analyze` (0 issues) and `flutter test` (48 tests passing).

---

---

### Phase 5: v1.1.0 Feature Set & Multi-Environment Support
- [x] **Staging Infrastructure**: Cloudflare staging D1 database (`work-hours-staging`), R2 bucket (`work-hours-reports-staging`), and wrangler environment configuration.
- [x] **Planned Shift Duration & Progress**: `PlannedShiftDialog` with 4h, 6h, 8h, custom, and skip options; glowing progress bar and overtime indicator in `CurrentShiftTimerCard`.
- [x] **Shift End Reminders**: Android `AlarmManager` + `BroadcastReceiver` notifications, `NotificationService` abstraction, configurable reminder offsets (5m, 10m, 15m, disabled).
- [x] **Expanded Mobile History Touch Target**: History button in timer card expanded to fill available layout space.
- [x] **Environment Switcher & Credential Storage**: Removed Custom tab, added dedicated persistent storage keys for `prod` and `staging` (URL and Bearer token) to prevent credential wipe, migrated default production URL to `https://work-hours-api.kamilsuhak.workers.dev`, and invalidated status/shifts on environment swap.
- [x] **Top AppBar Streamlining**: Removed redundant Shift History, Download APK, and GitHub buttons from AppBar (preserved in Timer Card and SettingsDialog).
- [x] **Verification**: All 67 Flutter tests and 61 Vitest tests passing.

---

### Phase 6: v1.2 Correctness & Staging Environment Resolution
- [x] **Staging Cloudflare Secrets & Authentication**: Configured `DEVICE_TOKEN_PEPPER` and `ADMIN_API_TOKEN` secrets on Cloudflare Staging worker (`work-hours-api-staging`). Provisioned test device `phone-staging` in `work-hours-staging` D1 database and verified live API connectivity.
- [x] **Undo Grace Window Temporal Alignment**: Server (`clock.ts`, `status.ts`, `types.ts`) and client (`models.dart`) now measure the 5-minute undo grace window against physical transaction creation time (`created_at_utc`) rather than offset timestamp (`occurred_at_utc`), resolving edge cases where retroactive (-5m) actions expired immediately or post-dated (+5m) actions hid the undo button.
- [x] **Environment Switch Cache Invalidation & Connection Feedback**: Implemented `resetAndRefresh` in `CurrentStatusNotifier` to clear cached state during environment transitions. `SettingsDialog` now detects and displays server connection errors instead of giving false confirmation toasts.
- [x] **UI Error Visibility**: Added Riverpod error listener in `ClockScreen` to surface action failures via floating SnackBars, and rendered `_buildErrorContent` when server errors occur rather than deceptively masking them with stale production state.
- [x] **Verification**: All 62 Vitest worker tests and 69 Flutter unit/widget tests passing.

---

### Phase 7: v1.1.3 Minute-Precision Time Standardization & Shift Work Location
- [x] **Worker Minute Truncation**: Added `truncateToMinute` in `status.ts` and normalized recorded shift timestamps (`occurred_at_utc`, `active_since_utc`) and derived durations across `clock.ts`, `events.ts`, `status.ts`, and `excel_generator.ts`.
- [x] **Excel Generator Unification**: Refactored `pairEventsIntoReportShifts` and `computeReportStats` to reuse `pairShifts`, `truncateToMinute`, and `formatDuration` from `status.ts`.
- [x] **Flutter Client Standardization**: Added `truncateToMinute` in `models.dart`, unified `ShiftRecord` pairing and formatting in `shift_model.dart`, updated `CurrentShiftTimerCard` to keep `Today` and `Month to date` live-synced on minute boundaries, and trimmed seconds from progress bar and undo dialog labels while preserving `HH:MM:SS` on the active shift stopwatch.
- [x] **Custom Offset Dialog Polish**: Streamlined preset chips to `±5m`, `±15m`, `±30m`, fixed stale chip highlight on manual out-of-range input, and added inline `-120` to `+120` min (`±2h`) range helper/error feedback.
- [x] **Shift Work Location (`remote` | `in-office`)**: Added `0003_add_location_to_events.sql` migration defaulting historical events to `'remote'`, updated `POST /api/v1/clock-in` and `POST /api/v1/admin/events/manual` validation/persistence, added `Remote` / `In-Office` selectors in `PlannedShiftDialog` and `ManualShiftDialog`, and displayed location badges in `RecentShiftsView`.

---

### Phase 8: v1.2.0 Contract `.docx` Report Automation & Full Excel Reports
- [x] **Private R2 Templates (`templates/`)**: Load `templates/umowa-zlecenie.docx`, `templates/contract-profile.json`, and `templates/signature.png` from Cloudflare R2 (`REPORTS_BUCKET`) so private personal/contract details and signature stay out of the public git repository.
- [x] **OpenXML `.docx` Generator (`docx_generator.ts`)**: Native `DecompressionStream('deflate-raw')` ZIP unpacker and OpenXML manipulator that fills the 23-row `Załącznik` attendance table (`date | 0h0m | signature PNG | empty | empty`) aggregated by Warsaw calendar day (combining recorded shifts + `plannedShifts`) and populates all `Rachunek do umowy zlecenia` fields and contractor signature.
- [x] **Always-Full Excel Reports & Exact Warsaw Date Filtering**: Standardized manual and 1st-of-month cron `.xlsx` reports to always include all columns (`Date`, `Start Time`, `End Time`, `Duration`, `Location`, `Source`, `Shift Notes`) and `Summary Statistics`, with exact `Europe/Warsaw` calendar date range boundaries.
- [x] **Flutter Formal Report & `PlanFutureShiftsDialog`**: Separated `ReportsScreen` into Formal Contract Report (`.docx`, locked to full current month with `PlanFutureShiftsDialog` for remaining days) and Excel Data Report (`.xlsx`, custom date range), with `.docx` MIME type support on Android and Web.

---

## Status Summary
All v1.1.3 and v1.2.0 implementation items are complete, tested (71 Vitest tests + 71 Flutter tests), and atomically committed locally.
