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
- [ ] **Warsaw Timezone in Reports**: Fix month start/end boundaries and local time formatting in `report_service.ts` and `excel_generator.ts` (currently slicing UTC `toISOString()`).
- [ ] **Spreadsheet Formula Injection Defense**: Neutralize `=`, `+`, `-`, `@` formula triggers in note/source text before inserting into Excel cells.
- [ ] **Report Download Path Traversal**: Sanitize filename route and restrict access strictly to safe `reports/*.xlsx` keys.
- [ ] **Atomic Undo Execution**: Execute undo event deletion, state rollback, and idempotency record within a single atomic `db.batch` transaction.
- [ ] **Production CORS Rules**: Scope allowed origins dynamically with `Vary: Origin` (worker origin + localhost for dev) instead of wildcard `*`.

### Phase 2: Multi-Platform Service Layer (Flutter App & iOS Readiness)
- [ ] **Platform Service Abstractions**: Define abstract interfaces in `app/lib/services/platform/` (`HapticFeedbackService`, `ReportFileService`, `WidgetSyncService`, `CredentialStore`).
- [ ] **Concrete Platform Implementations**: Implement Android, Web, and NoOp providers.
- [ ] **Presentation Refactoring**: Refactor UI widgets and notifiers to eliminate inline platform checks (`if (!isAndroid)`, `kIsWeb`).
- [ ] **Admin Token Web Security**: In-memory credential session for `ManualShiftDialog` on Web.

### Phase 3: Documentation & Design Specification Realignment
- [x] **`ROADMAP.md` Created**: Consolidated roadmap superseding `POLISH.md`.
- [x] **`CHANGELOG.md` Created**: Backfilled commit history through `v0.1.0`, `v0.2.0`, `v0.3.0`, `v0.3.1`, and `Unreleased`.
- [x] **`docs/API.md` Created**: Complete endpoint contracts, schemas, and error codes.
- [x] **`docs/DEPLOYMENT.md` Created**: Operations runbook for D1, R2, secrets, migrations, and backups.
- [x] **`README.md` Streamlining**: Clean entry point referencing modular docs and technical guarantees.
- [ ] **`DESIGN.md` Synchronization**: Update ground-truth design to match the unified Cloudflare Worker + Workers Static Assets + pure TS OpenXML architecture (removing stale Python references).

### Phase 4: Test Coverage & Verification
- [ ] **Backend Unit & Integration Tests**: Warsaw DST transitions, formula injection escaping, undo atomicity, R2 download traversal rejection.
- [ ] **Flutter App Validation**: `flutter analyze` and `flutter test`.

---

## Immediate Next Steps
1. Synchronize `DESIGN.md` to remove stale Python/openpyxl/email references.
2. User confirmation to proceed with Phase 1 backend implementation (Warsaw Timezone & Excel fixes).



