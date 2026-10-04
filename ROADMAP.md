# Work Hours Tracker — Project Roadmap & Hardening Specification

**Document Purpose:** Consolidates all architectural concerns, security hardening, correctness fixes, cross-platform adaptations, documentation restructuring, and testing gaps from `POLISH.md` into a single actionable roadmap. This document supersedes and replaces `POLISH.md`.

**Guiding Principles:**

1. **Rock-Solid Core over Fluff:** Maintainable, robust server logic and data integrity take absolute priority over visual or cosmetic additions.
2. **Single-User Pragmatism:** Tailored specifically for a single-user personal tool. We eliminate enterprise complexity, multi-tenant session infrastructure, and premature table/retention architectures that add maintenance burden without value.
3. **Authoritative Server Time:** Server controls UTC ISO 8601 state transitions; `Europe/Warsaw` is strictly used for calendar grouping, daily boundaries, and display.
4. **Platform Hygiene:** Utilize Service Abstraction Architecture.

---

## 1. Critical Correctness & Security Hardening

### 1.1 Warsaw Timezone Calculations in Reports (Real Bug)

- **Problem:**
  - `worker/src/reports/report_service.ts` calculates scheduled previous-month boundaries in UTC (`Date.UTC(year, month - 1, 1)`), which misaligns with Warsaw calendar month boundaries by 1–2 hours.
  - `worker/src/reports/excel_generator.ts` formats `startTimeLocal` and `endTimeLocal` by slicing `inDate.toISOString()`, writing **UTC hours** into Excel cells instead of Warsaw local time.
- **Action Items:**
  - [ ] Use `Intl.DateTimeFormat` with `timeZone: 'Europe/Warsaw'` to derive the previous calendar month's exact UTC start (`YYYY-MM-01T00:00:00 Warsaw`) and end (`YYYY-MM-01T00:00:00 Warsaw of next month`).
  - [ ] Use half-open intervals `[startUtc, endUtc)` for shift event queries.
  - [ ] In `excel_generator.ts`, format shift dates, start times, and end times in `Europe/Warsaw`.
  - [ ] Add automated tests covering March (winter -> summer, UTC+1 to UTC+2) and October (summer -> winter, UTC+2 to UTC+1) DST transitions.

### 1.2 Spreadsheet Formula Injection Defense (CWE-1236)

- **Problem:**
  - User notes, sources, or custom text starting with `=`, `+`, `-`, or `@` can be interpreted as formulas by spreadsheet applications (Microsoft Excel, Google Sheets, LibreOffice Calc).
- **Action Items:**
  - [ ] In `worker/src/reports/excel_generator.ts`, sanitize all user-controllable text cells: if a value begins with `=`, `+`, `-`, `@`, `\t`, or `\r`, prepend a neutralizing single quote (`'`).
  - [ ] Preserve XML escaping (`&amp;`, `&lt;`, `&gt;`, `&quot;`, `&apos;`).
  - [ ] Add automated unit tests with malicious/formula-like test strings.

### 1.3 Path Traversal & Filename Sanitization on Report Download

- **Problem:**
  - `GET /api/v1/reports/download/:filename` accepts arbitrary client-decoded strings and passes them directly to `env.REPORTS_BUCKET.get(key)`.
- **Action Items:**
  - [ ] Enforce strict regex validation on requested filenames: `^work-hours-\d{4}-\d{2}-(formal|full)\.xlsx$`.
  - [ ] Reject any filename containing path separators (`/`, `\`) or traversal sequences (`..`).
  - [ ] Set `Content-Type: application/vnd.openxmlformats-officedocument.spreadsheetml.sheet` and sanitized `Content-Disposition`.
  - [ ] Add test cases verifying rejection of traversal and malformed filenames.

### 1.4 Atomic Undo Transaction in State Machine

- **Problem:**
  - `handleUndo` currently executes `DELETE FROM events WHERE id = ?` first as a standalone query, then computes durations, and only then executes `db.batch([work_state update, processed_requests insert])`. A failure between these steps leaves database state corrupted.
- **Action Items:**
  - [ ] Reorganize `handleUndo` so duration recalculations are computed first.
  - [ ] Bundle the `DELETE FROM events`, `work_state` update with optimistic version check (`WHERE version = ?`), and `processed_requests` recording into a single atomic `db.batch` call.
  - [ ] Ensure repeated undo requests replay the cached response via idempotency.
  - [ ] Add integration test verifying atomicity and graceful handling of race conditions.

### 1.5 CORS & Security Headers

- **Problem:**
  - The API currently responds with `Access-Control-Allow-Origin: *` on credential-bearing endpoints.
- **Action Items:**
  - [ ] Dynamically validate `Origin` header against:
    - Same-origin (when Flutter Web is served via Worker Static Assets).
    - Configured production custom domains.
    - Local development origins (`http://localhost:*`, `http://127.0.0.1:*`).
  - [ ] Add `Vary: Origin` header to all CORS responses.
  - [ ] Set security headers: `X-Content-Type-Options: nosniff`, `Referrer-Policy: strict-origin-when-cross-origin`, and `Cache-Control: no-store` on authenticated API responses.

---

## 2. Authentication & Client Web Security

### 2.1 Web Credential Model & Admin Token Handling

- **Context & Evaluation:**
  - `flutter_secure_storage: ^11.2.0` on Web utilizes the Web Cryptography API (`SubtleCrypto` AES-GCM) with an IndexedDB-stored CryptoKey to encrypt data in `localStorage`. It is **not** raw plaintext.
  - However, in web browsers, WebCrypto keys in IndexedDB are accessible to any script executing in that origin. For daily operations, the web client only requires a scoped `personal-web` device token.
  - Persisting the master `ADMIN_API_TOKEN` indefinitely in browser storage creates an unnecessary exposure surface.
- **Action Items:**
  - [ ] Provision distinct device records in D1: `primary-phone` for Android/Widget and `personal-web` for Flutter Web.
  - [ ] In `app/lib/features/settings/settings_notifier.dart`, avoid saving `adminToken` to browser storage on Web.
  - [ ] Keep the admin token in-memory only during the active session, or prompt for it on-demand inside `ManualShiftDialog`.
  - [ ] Ensure build artifacts do not contain any hardcoded tokens (`--dart-define` secrets forbidden).

---

## 3. Notes & Markdown Handling

### 3.1 Notes Lifecycle & Rendering

- **Action Items:**
  - [ ] **Storage:** Store shift notes as raw Markdown in D1 `events.note`. Impose a reasonable size limit (e.g. 4,000 characters) on both client and server.
  - [ ] **Flutter Rendering:** Maintain `MarkdownText` as a lightweight, safe Flutter widget renderer (supports headers, bold, italics, code, bullet lists). Never evaluate raw HTML or pass unsanitized strings to webviews.
  - [ ] **Excel Export:** `cleanMarkdownForExcel` flattens markdown to readable plain text, strips bullet syntax, and neutralizes formula prefixes before Excel cell generation.
  - [ ] **Draft Persistence:** Retain ongoing shift notes in local device storage so unsaved notes survive app closure while clocked in.

---

## 4. App & Native Android Widget Consistency

### 4.1 Consistency & Synchronization

- **Action Items:**
  - [ ] **Independent Clients:** The Android widget communicates directly with the Worker API via OkHttp. The Flutter app is not required to be running.
  - [ ] **Signaling vs Authority:** Flutter-to-Widget `MethodChannel` calls are optional refresh triggers, not the source of truth. Both clients independently reconcile state with `GET /api/v1/status`.
  - [ ] **Display Accuracy:** Widget displays the server-authoritative state (`Clocked In` / `Clocked Out`), `active-since` time, derived duration, and last sync timestamp. Avoid battery-draining continuous background timers on home screen widgets.
  - [ ] **Foreground Refresh:** The Flutter app automatically calls `GET /api/v1/status` on app resume.

---

## 5. Multi-Platform Service Abstraction Architecture (iOS-Ready)

### 5.1 The Anti-Pattern of Negative Platform Guards (`!isAndroid`)

- Relying on `if (!isAndroid) return;` or scattered `kIsWeb` checks creates a fragile binary assumption ("Android" vs "everything else").
- When porting to iOS in the future:
  - Haptics would mistakenly be disabled on iOS even though iOS provides rich `UIImpactFeedbackGenerator` support.
  - Widget synchronization would attempt Android `MethodChannel` or be treated as a web no-op rather than integrating with iOS WidgetKit timelines.
  - Report file opening would fail on iOS because it expects Android's `FileProvider` instead of `UIDocumentInteractionController` or native sharing.
- Scattering platform checks inside Flutter UI widgets (`ClockScreen`, `SettingsDialog`, `ReportsScreen`) violates separation of concerns.

### 5.2 Idiomatic Riverpod Service Layer

Decouple the presentation layer completely from the underlying operating system by introducing abstract service contracts injected via Riverpod providers:

1. **`HapticFeedbackService` (`hapticServiceProvider`):**
   - Contract: `Future<void> lightImpact()`, `Future<void> mediumImpact()`.
   - Implementations:
     - `AndroidHapticService`: Delegates to `HapticFeedback.lightImpact()` / direct vibrator.
     - `IosHapticService` (future): Delegates to `HapticFeedback.lightImpact()` / `selectionClick()`.
     - `WebHapticService`: Pure, silent no-op.
2. **`ReportFileService` (`reportFileServiceProvider`):**
   - Contract: `Future<String?> saveAndOpenReport({required Uint8List bytes, required String filename})`.
   - Implementations:
     - `AndroidReportFileService`: Android MethodChannel -> Cache storage -> `FileProvider` `ACTION_VIEW`.
     - `IosReportFileService` (future): Cache to `NSTemporaryDirectory()` -> Native Share Sheet / Document Interaction Controller.
     - `WebReportFileService`: In-memory `Blob` -> temporary object URL -> programmatic download -> immediate URL revocation.
3. **`WidgetSyncService` (`widgetSyncServiceProvider`):**
   - Contract: `Future<void> syncCredentials(...)`, `Future<void> notifyWidgetOfStateChange(...)`.
   - Implementations:
     - `AndroidWidgetSyncService`: Invokes Android `MethodChannel('com.workhours.tracker/widget_sync')`.
     - `IosWidgetSyncService` (future): Updates shared App Group container and reloads WidgetKit timelines via `home_widget`.
     - `NoOpWidgetSyncService` (Web / Desktop): Silent no-op.
4. **`CredentialStore` (`credentialStoreProvider`):**
   - Contract: Device token and admin token storage.
   - Implementations:
     - `MobileCredentialStore` (Android + iOS): Uses hardware-backed secure storage (Keystore on Android, Keychain on iOS).
     - `WebCredentialStore`: Uses `flutter_secure_storage` WebCrypto for device token, but keeps `adminToken` in-memory only during the active administrative session.

### 5.3 Action Items

- [ ] Define abstract service contracts in `app/lib/services/platform/`.
- [ ] Implement concrete Android, Web, and no-op service classes.
- [ ] Provide factory/conditional Riverpod providers that resolve the appropriate implementation at startup.
- [ ] Refactor UI widgets and notifiers to depend strictly on the Riverpod service interfaces with zero inline platform checks.

---

## 6. Documentation Restructuring

### 6.1 Documentation Plan

The repository documentation will be reorganized into dedicated, single-responsibility files:

- **`README.md` (Streamlined Entry Point):**
  - Project summary & status badge.
  - High-level architecture diagram.
  - Core features summary.
  - Quick-start guide (Prerequisites, Quick setup).
  - Navigation links to `DESIGN.md`, `docs/API.md`, `docs/DEPLOYMENT.md`, `CHANGELOG.md`.

- **`DESIGN.md` (Ground-Truth Architecture):**
  - Update to reflect current unified architecture: Unified Cloudflare Worker with Workers Static Assets (`env.ASSETS`), pure TypeScript OpenXML generator, Cloudflare R2 bucket, and D1 database.
  - Purge obsolete references to Python, `openpyxl`, and GitHub Actions email workflows.
  - Detail the authoritative Warsaw timezone calculation model, state machine transitions, and idempotency guarantees.

- **`docs/API.md` (Complete API Contract):**
  - Detailed documentation of all `/api/v1/*` endpoints.
  - Authentication headers (`Bearer <device-token>` vs `Bearer <admin-token>`).
  - Request body schemas, validation rules, status codes, and error payloads.
  - Idempotency semantics and retry guarantees.

- **`docs/DEPLOYMENT.md` (Operations & Runbook):**
  - Initial setup: D1 creation, R2 bucket creation, secrets configuration (`ADMIN_API_TOKEN`, `DEVICE_TOKEN_PEPPER`).
  - Device provisioning with `provision-device.mjs`.
  - D1 database migration procedures (local and remote).
  - Production deployment via Wrangler.
  - D1 snapshot backup and restore runbook (`wrangler d1 export`).

- **`CHANGELOG.md` (Release & Version History):**
  - Follow Keep a Changelog conventions.
  - Track releases: `v0.1.0` (Core tracking), `v0.2.0` (Totals & Recents), `v0.3.0` (Reporting & OpenXML), `v0.3.1` (Web adaptation), `Unreleased` (Hardening & Polish).

---

## 7. Pruned & Excluded Items (Explicit Non-Goals)

To prevent over-engineering a single-user system, the following suggestions from `POLISH.md` are **deliberately pruned**:

1. **D1 Relational Report Metadata Table (`reports` table):**
   - _Why pruned:_ Single-user creates ~12 reports a year. Storing metadata in R2 object metadata (`customMetadata`) with an atomic `latest.json` pointer provides all necessary tracking with zero D1 migration/relational overhead.
2. **Elevated Session Token & Capability Infrastructure:**
   - _Why pruned:_ A stateless bearer token hashed with SHA-256 and server-side pepper against D1 is secure, low-latency, and zero-maintenance. No session database or complex capability tokens required.
3. **Scheduled Cleanup Cron for `processed_requests`:**
   - _Why pruned:_ Single-user volume is ~730 rows per year (<1 MB over 5 years in SQLite). Scheduled background deletion jobs add unnecessary complexity for negligible storage impact.
4. **Cloudflare Pages Routing & Fallback Configs:**
   - _Why pruned:_ The project uses a **Unified Cloudflare Worker** with Cloudflare Workers Static Assets (`run_worker_first: true`). API and Web assets are co-located on the same domain; SPA routing is already configured via `"not_found_handling": "single-page-application"`.

---

## 8. Phased Execution Roadmap

### Phase 1: Core Worker Correctness & Security

- [ ] Fix Warsaw calendar month calculations in `worker/src/reports/report_service.ts`.
- [ ] Fix Warsaw local time formatting (`startTimeLocal`, `endTimeLocal`) in `worker/src/reports/excel_generator.ts`.
- [ ] Implement formula injection sanitization in `excel_generator.ts`.
- [ ] Secure `GET /api/v1/reports/download/:filename` with strict regex and path traversal rejection.
- [ ] Make `handleUndo` in `worker/src/clock.ts` fully atomic inside a single `db.batch`.
- [ ] Scope CORS dynamically with `Vary: Origin` and localhost support.

### Phase 2: Client Web Security & Platform Cleanliness

- [ ] Update `settings_notifier.dart` to keep `adminToken` in-memory on Web rather than persisting to storage.
- [ ] Standardize platform guards to `if (!isAndroid) return;` across Flutter services.
- [ ] Verify Web report download flow and object URL cleanup.

### Phase 3: Documentation Restructure & Spec Synchronization

- [ ] Update `DESIGN.md` to reflect unified architecture (Workers Static Assets, pure TS OpenXML, R2).
- [ ] Create `docs/API.md`.
- [ ] Create `docs/DEPLOYMENT.md`.
- [ ] Create `CHANGELOG.md`.
- [ ] Streamline `README.md`.

### Phase 4: Automated Testing & Verification

- [ ] Add Worker unit tests for Warsaw DST transitions (March and October).
- [ ] Add Worker tests for formula injection neutralization.
- [ ] Add Worker tests for report download path traversal rejection.
- [ ] Add Worker integration tests for atomic undo transactions.
- [ ] Validate entire repository: `npm test`, `npm run typecheck`, `flutter test`, `flutter analyze`.

---

## 9. Definition of Done for v1.0 Stable Release

The system is considered ready for `v1.0` when:

1. Android app, home-screen widget, and web client all reconcile against authoritative server state.
2. Month boundaries and shift times are accurately calculated in `Europe/Warsaw` across DST transitions.
3. OpenXML `.xlsx` reports open cleanly in Excel, Google Sheets, and LibreOffice Calc without formula injection vulnerabilities.
4. Report downloads are secured against path traversal.
5. All mutations in clocking and undo execute atomically in D1 transactions.
6. Documentation is clean, aligned, and separated into `README.md`, `DESIGN.md`, `docs/API.md`, `docs/DEPLOYMENT.md`, and `CHANGELOG.md`.
7. All automated test suites (`vitest` and `flutter test`) pass with 100% success.
