# Work Hours Tracker

A low-friction, single-user work hours tracking platform with authoritative server time, Cloudflare D1 persistence, a Flutter mobile client, and a native Android home-screen widget.

---

## Architecture Overview

```text
Android home-screen widget (Kotlin)
                    |
                    | HTTPS JSON API
                    v
Flutter app (Riverpod) ---> Cloudflare Worker (TypeScript)
                                  |
                                  v
                          Cloudflare D1 database

Later (v0.3):
GitHub Actions scheduled workflow
        |
        +--> protected report API
        +--> Python/openpyxl workbook
        +--> transactional email
```

### Core Technologies

- **Backend:** TypeScript on Cloudflare Workers
- **Database:** Cloudflare D1 (SQLite at the edge)
- **Migrations:** Versioned SQL migrations managed via Wrangler
- **Mobile Client:** Flutter with Riverpod state management
- **Android Widget:** Kotlin independent API client with separate Clock In/Out actions
- **Authoritative Time:** Server-generated UTC ISO 8601 strings; grouped/displayed in `Europe/Warsaw`
- **CI/CD:** GitHub Actions for automated typechecking, testing, and D1 migrations + Worker deployments

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
│   │   ├── index.ts               # Worker router, security headers, logging
│   │   ├── auth.ts                # SHA-256 token hashing & timing-safe authentication
│   │   ├── clock.ts               # Clock-in / clock-out logic & idempotency
│   │   ├── events.ts              # Events query & admin manual backfill
│   │   ├── status.ts              # Status endpoint & Europe/Warsaw duration calculations
│   │   ├── errors.ts              # Standard error format & AppError class
│   │   └── types.ts               # Domain interfaces and API contracts
│   ├── migrations/
│   │   └── 0001_initial.sql       # Initial D1 schema (devices, work_state, events, processed_requests)
│   ├── scripts/
│   │   └── provision-device.ts    # Secure device token generation & provisioning script
│   ├── test/
│   │   ├── auth.test.ts           # Token hashing & timing-safe auth tests
│   │   ├── transitions.test.ts    # State machine, idempotency, and Warsaw timezone tests
│   │   └── events.test.ts         # Validation and overlap rule tests
│   ├── package.json
│   ├── tsconfig.json
│   ├── vitest.config.ts
│   └── wrangler.jsonc             # Cloudflare Worker configuration & D1 binding
├── mobile/
│   ├── lib/
│   │   ├── api/
│   │   │   ├── api_client.dart    # HTTP client with secure token storage
│   │   │   └── models.dart        # Immutable models and error types
│   │   ├── features/
│   │   │   ├── clock/             # Clock screen, state notifier, repository
│   │   │   └── history/           # Recent events provider
│   │   └── main.dart              # App entry point with lifecycle resume observer
│   ├── android/                   # Kotlin Android native project & Home Screen Widget
│   │   └── app/src/main/kotlin/.../widget/WorkHoursWidgetReceiver.kt
│   ├── test/
│   │   ├── duration_formatting_test.dart
│   │   └── widget_test.dart
│   ├── analysis_options.yaml
│   └── pubspec.yaml
├── DESIGN.md                      # Ground-truth design specification
└── README.md
```

---

## Getting Started

### 1. Cloudflare Worker Setup

From the `worker` directory:

```bash
cd worker
npm install

# Run type check and tests
npm run typecheck
npm test

# Create the remote D1 database once
npx wrangler d1 create work-hours-prod

# Update worker/wrangler.jsonc with the generated database_id

# Apply migrations locally
npx wrangler d1 migrations apply work-hours-prod --local

# Apply migrations to production
npx wrangler d1 migrations apply work-hours-prod --remote
```

#### Provisioning the First Device Token

Generate a cryptographically secure device bearer token and corresponding database record:

```bash
npx tsx scripts/provision-device.ts "primary-phone"
```

Copy the generated bearer token into your device's secure storage.

#### Setting Worker Secrets

Set sensitive production secrets via Wrangler:

```bash
npx wrangler secret put ADMIN_API_TOKEN
npx wrangler secret put DEVICE_TOKEN_PEPPER
```

### 2. Mobile App Setup

From the `mobile` directory:

```bash
cd mobile
flutter pub get
flutter analyze
flutter test

# Run app with a custom API URL
flutter run --dart-define=API_BASE_URL=https://your-worker.workers.dev
```

---

## API Contract (v0.1)

| Method | Endpoint | Auth | Description |
| :--- | :--- | :--- | :--- |
| `POST` | `/api/v1/clock-in` | Bearer `<device-token>` | Clock in; safe to retry with `requestId` |
| `POST` | `/api/v1/clock-out` | Bearer `<device-token>` | Clock out; safe to retry with `requestId` |
| `GET` | `/api/v1/status` | Bearer `<device-token>` | Get authoritative status & durations |
| `GET` | `/api/v1/events` | Bearer `<device-token>` | Query raw events for range `?from=...&to=...` |
| `POST` | `/api/v1/admin/events/manual` | Bearer `<admin-token>` | Authenticated backfill / repair of shifts |

---

## CI/CD Pipeline

The repository includes two GitHub Actions workflows:

1. **`.github/workflows/ci.yml`**: Runs on every pull request and push to validate TypeScript types, Vitest test suites, and Flutter analysis and tests.
2. **`.github/workflows/deploy-worker.yml`**: Automatically applies pending D1 migrations to `work-hours-prod` and deploys the updated Cloudflare Worker when changes are merged into `main`.

Configure the following GitHub repository secrets:
- `CLOUDFLARE_API_TOKEN`
- `CLOUDFLARE_ACCOUNT_ID`

---

## Design Document

For in-depth architectural principles, concurrency patterns, and the roadmap (v0.1 to v1.0), refer to [DESIGN.md](DESIGN.md).