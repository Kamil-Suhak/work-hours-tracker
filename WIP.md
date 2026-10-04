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
- [ ] **Platform Service Abstractions**: Define abstract interfaces in `app/lib/services/platform/` (`HapticFeedbackService`, `ReportFileService`, `WidgetSyncService`, `CredentialStore`).
- [ ] **Concrete Platform Implementations**: Implement Android, Web, and NoOp providers.
- [ ] **Presentation Refactoring**: Refactor UI widgets and notifiers to eliminate inline platform checks (`if (!isAndroid)`, `kIsWeb`).
- [ ] **Admin Token Web Security**: In-memory credential session for `ManualShiftDialog` on Web.

### Phase 3: Documentation & Design Specification Realignment
- [x] **`ROADMAP.md` Created**: Consolidated roadmap superseding `POLISH.md` (and `POLISH.md` deleted).
- [x] **`CHANGELOG.md` Created**: Backfilled commit history through `v0.1.0`, `v0.2.0`, `v0.3.0`, `v0.3.1`, and `Unreleased`.
- [x] **`docs/API.md` Created**: Complete endpoint contracts, schemas, and error codes.
- [x] **`docs/DEPLOYMENT.md` Created**: Operations runbook for D1, R2, secrets, migrations, and backups.
- [x] **`README.md` Streamlining**: Clean entry point referencing modular docs and technical guarantees.
- [x] **`DESIGN.md` Synchronization**: Updated ground-truth design to match unified Worker Static Assets, R2, and pure TS OpenXML generator.

### Phase 4: Test Coverage & Verification
- [x] **Backend Unit & Integration Tests**: Warsaw DST transitions (March & October), formula injection escaping, undo atomicity, R2 download traversal rejection, dynamic CORS headers (57 Vitest tests passing).
- [x] **Flutter App Validation**: `flutter analyze` (0 issues) and `flutter test` (42 tests passing).

---

## Immediate Next Steps
1. Commit Phase 1 backend hardening and documentation synchronization changes.
2. Proceed to Phase 2: Multi-Platform Service Layer in Flutter (`HapticFeedbackService`, `ReportFileService`, `WidgetSyncService`, `CredentialStore`) and admin token web security.



