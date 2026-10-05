# Work Hours Tracker — Deployment & Operations Guide

This document details end-to-end deployment, secret configuration, database migrations, device provisioning, and backup runbooks.

---

## 1. Prerequisites

- **Node.js:** v20+ recommended (`node --version`)
- **Cloudflare Wrangler CLI:** `npm install -g wrangler` (`wrangler --version`)
- **Flutter SDK:** 3.24+ (`flutter --version`)
- **Android SDK:** API 34+ (for Android APK / bundle compilation)

---

## 2. Cloudflare Infrastructure Setup

### 2.1 Authenticate with Cloudflare
```bash
npx wrangler login
```

### 2.2 Create Production Cloudflare D1 Database
```bash
npx wrangler d1 create work-hours-prod
```
Copy the generated `database_id` and update `worker/wrangler.jsonc`:
```jsonc
"d1_databases": [
  {
    "binding": "DB",
    "database_name": "work-hours-prod",
    "database_id": "<YOUR-DATABASE-ID>",
    "migrations_dir": "migrations"
  }
]
```

### 2.3 Create Production Cloudflare R2 Bucket
```bash
npx wrangler r2 bucket create work-hours-reports
```

Ensure `worker/wrangler.jsonc` contains the binding:
```jsonc
"r2_buckets": [
  {
    "binding": "REPORTS_BUCKET",
    "bucket_name": "work-hours-reports"
  }
]
```

---

## 3. Database Migrations

Cloudflare D1 migrations track schema versions in `migrations/`.

### 3.1 Local Testing & Vitest
```bash
npx wrangler d1 migrations apply work-hours-prod --local
```

### 3.2 Remote Production Application
Apply pending migrations to the Cloudflare edge database:
```bash
npx wrangler d1 migrations apply work-hours-prod --remote
```

> **Migration Rules:**
> - Migrations are strictly additive. Never modify an existing numbered migration that has been applied to production.
> - Always perform a D1 backup before applying major schema expansions.

---

## 4. Production Secrets Configuration

Configure the required server-side secrets using Wrangler:

```bash
# 1. Administrative API token for shift backfill (/api/v1/admin/events/manual)
npx wrangler secret put ADMIN_API_TOKEN

# 2. Cryptographic pepper added to raw device tokens before SHA-256 hashing
npx wrangler secret put DEVICE_TOKEN_PEPPER
```

---

## 5. Device Provisioning

Generate cryptographically secure Bearer tokens for each client:

### 5.1 Provision Android Phone / Widget
```bash
node worker/scripts/provision-device.mjs "primary-phone"
```

### 5.2 Provision Personal Web Browser
```bash
node worker/scripts/provision-device.mjs "personal-web"
```

The script outputs:
1. The **Raw Bearer Token** (copy this securely into the app settings).
2. The **SQL INSERT Statement** executed against D1 to register `token_hash`.

---

## 6. Build & Deployment

The system is deployed as a **Unified Cloudflare Worker** that serves both the API and the compiled Flutter Web frontend via Cloudflare Workers Static Assets.

### 6.1 Build Flutter Web Assets
```powershell
flutter build web --release
```
Assets are output to `app/build/web/`.

### 6.2 Deploy Worker & Static Assets
```powershell
npx wrangler deploy
```

Wrangler uploads the compiled TypeScript Worker and synchronizes `app/build/web` to Cloudflare's global edge network.

---

## 7. Disaster Recovery & Backup Runbook

Cloudflare D1 is an SQLite-based serverless database. Regular snapshots ensure zero data loss.

### 7.1 Manual D1 Snapshot Export
Export all production tables and records to an SQL dump:
```bash
npx wrangler d1 export work-hours-prod --remote --output="backups/work-hours-backup-$(date +%Y%m%d).sql"
```

> Keep exported `.sql` files outside public git repositories.

### 7.2 Disaster Recovery / Restoration
To restore into a staging or replacement database:
```bash
# 1. Create a test/recovery database
npx wrangler d1 create work-hours-restore-test

# 2. Execute backup SQL against the new database
npx wrangler d1 execute work-hours-restore-test --remote --file="backups/work-hours-backup-20261004.sql"
```
Verify data integrity before repointing production Worker bindings.

---

## 8. Operational Database Scripts & Common Queries (`worker/sql/`)

A dedicated set of tested SQL scripts and operational utilities is maintained in [`worker/sql/`](../worker/sql/) and [`worker/scripts/`](../worker/scripts/) for recurring administration tasks.

### 8.1 Purging Shift History & Resetting Active State
Wipes all shift events and request idempotency logs, resetting the user state to `clocked_out` while **preserving all registered client devices**:

```bash
# Using npm script from repository root:
npm --prefix worker run db:purge

# Or using Wrangler directly:
npx wrangler d1 execute work-hours-prod --remote --file=worker/sql/purge-shifts.sql
```

### 8.2 Full Factory Reset (Including Devices)
> [!CAUTION]
> This wipes the entire database, including registered device tokens. All mobile devices and web browsers will need to be re-provisioned.

```bash
npm --prefix worker run db:purge-all
# Or:
npx wrangler d1 execute work-hours-prod --remote --file=worker/sql/purge-all.sql
```

### 8.3 List Registered Devices
Inspect all provisioned client devices, their authorization status (`ACTIVE` vs `REVOKED`), and creation timestamps:

```bash
npm --prefix worker run db:devices
# Or:
npx wrangler d1 execute work-hours-prod --remote --file=worker/sql/list-devices.sql
```

### 8.4 Inspect Current Clock State
Query whether the user is currently clocked in or out, `active_since` timestamp, schema version, and the 5 latest events:

```bash
npm --prefix worker run db:status
# Or:
npx wrangler d1 execute work-hours-prod --remote --file=worker/sql/inspect-state.sql
```

### 8.5 View Recent Shifts & Event Log
Retrieve the 25 most recent clock-in and clock-out events with associated device names and shift notes:

```bash
npm --prefix worker run db:shifts
# Or:
npx wrangler d1 execute work-hours-prod --remote --file=worker/sql/recent-shifts.sql
```


