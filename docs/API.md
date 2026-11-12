# Work Hours Tracker — API Reference

This document provides the authoritative reference for the Work Hours Tracker API (`/api/v1/*`).

---

## 1. Overview & Conventions

- **Base URL:** `https://<your-worker>.<subdomain>.workers.dev` (or same-origin on Web).
- **Protocol:** HTTPS only.
- **Timestamps:** ISO 8601 strings in UTC. Shift timestamps (`occurredAtUtc`, `activeSince`) are normalized to minute precision (e.g. `2026-10-04T08:00:00.000Z`), while `serverTime` and `createdAtUtc` retain full server precision.
- **Timezone for Durations:** All daily boundaries and month-to-date totals are computed using `Europe/Warsaw` at minute precision.
- **Request Tracing:** Every response includes `X-Correlation-ID` for diagnostics.

---

## 2. Authentication

Requests require a Bearer token in the `Authorization` header:

```http
Authorization: Bearer <token>
```

### Credentials
1. **Device Token (All API Endpoints):**
   - Issued to devices via `npm run provision -- "<device-name>"`.
   - Stored in Cloudflare D1 `devices` table as `SHA-256(token + DEVICE_TOKEN_PEPPER)`.
   - Authorized for all API endpoints: `status`, `clock-in`, `clock-out`, `shift/target`, `undo`, `events`, `reports/*`.

---

## 3. Idempotency

Mutating clock commands (`clock-in`, `clock-out`, `undo`) require a unique client-generated `requestId` (UUID v4 recommended, max 128 characters).

- **Guarantee:** If a network retry occurs with the same `requestId`, the Worker replays the original cached response from `processed_requests` without inserting duplicate database records.
- **Retention:** Processed requests are retained indefinitely in SQLite for single-user audit stability.

---

## 4. Endpoints

### 4.1 Status & Time
#### `GET /api/v1/status`
Returns the current authoritative state, elapsed durations, optional auto-stop target, and the latest event. If an active shift's `targetClockOutUtc` has already elapsed, authenticated API requests (and the monthly report cron) lazily materialize a `clock_out` event at `max(activeSince, targetClockOutUtc)` with reason `"Auto-stopped at target"` before returning or aggregating.

- **Auth:** Device Token
- **Response (200 OK):**
```json
{
  "state": "clocked_in",
  "activeSince": "2026-10-04T08:00:00.000Z",
  "targetClockOutUtc": "2026-10-04T16:00:00.000Z",
  "serverTime": "2026-10-04T12:30:00.000Z",
  "todaySeconds": 16200,
  "monthSeconds": 72000,
  "latestEvent": {
    "id": "e4b2d3c1-0000-4000-8000-000000000001",
    "eventType": "clock_in",
    "occurredAtUtc": "2026-10-04T08:00:00.000Z"
  }
}
```

---

### 4.2 Clock Operations

#### `POST /api/v1/clock-in`
Transitions state from `clocked_out` to `clocked_in` and records an event.

- **Auth:** Device Token
- **Body:**
```json
{
  "requestId": "c1f2b3a4-1234-5678-9abc-def012345678",
  "source": "flutter_app",
  "location": "remote",
  "offsetMinutes": -5,
  "targetMinutes": 480,
  "note": "Optional initial shift note"
}
```
- **Allowed Sources:** `flutter_app`, `android_widget`, `web_dashboard`
- **Allowed Locations:** `remote`, `in-office` (optional, defaults to `remote`)
- **Optional `targetMinutes`:** Integer `1`–`1440` (max 24 hours); sets `targetClockOutUtc` relative to the effective clock-in minute (`null` for open-ended shifts)
- **Response (200 OK):**
```json
{
  "state": "clocked_in",
  "changed": true,
  "activeSince": "2026-10-04T08:00:00.000Z",
  "targetClockOutUtc": "2026-10-04T16:00:00.000Z",
  "serverTime": "2026-10-04T08:00:00.000Z",
  "todaySeconds": 0,
  "monthSeconds": 55800,
  "latestEvent": {
    "id": "f5a6b7c8-0000-4000-8000-000000000002",
    "eventType": "clock_in",
    "occurredAtUtc": "2026-10-04T08:00:00.000Z"
  }
}
```
*Note: If already clocked in, returns `changed: false` with current state without creating a new event.*

#### `POST /api/v1/clock-out`
Transitions state from `clocked_in` to `clocked_out`, clears `targetClockOutUtc`, calculates shift duration, and stores the completed shift note.

- **Auth:** Device Token
- **Body:**
```json
{
  "requestId": "d2e3f4a5-1234-5678-9abc-def012345678",
  "source": "flutter_app",
  "note": "Final completed shift note (Markdown supported, max 4000 chars)"
}
```
- **Response (200 OK):**
```json
{
  "state": "clocked_out",
  "changed": true,
  "activeSince": null,
  "targetClockOutUtc": null,
  "serverTime": "2026-10-04T16:00:00.000Z",
  "todaySeconds": 28800,
  "monthSeconds": 84600,
  "latestEvent": {
    "id": "a9b8c7d6-0000-4000-8000-000000000003",
    "eventType": "clock_out",
    "occurredAtUtc": "2026-10-04T16:00:00.000Z"
  }
}
```

#### `PATCH /api/v1/shift/target`
Sets, shifts, or clears `targetClockOutUtc` for the currently active (`clocked_in`) shift. Uses optimistic locking (`version`) on `work_state`.

- **Auth:** Device Token
- **Body (one of):**
  - Relative shift nudge: `{ "deltaMinutes": -10 }` (integer `-1440`..`1440`, non-zero; negative deltas clamp to `max(nowMinute + 1m, activeSince + 1m)`)
  - Explicit target duration: `{ "targetMinutes": 120 }` (integer `1`..`1440` from `activeSince`, must be at least 1 minute in the future)
  - Clear target (open-ended shift): `{ "targetMinutes": null }`
- **Response (200 OK):** Returns the updated `GET /api/v1/status` payload.

#### `POST /api/v1/undo`
Reverts the latest clock-in or clock-out action within a 5-minute (300,000 ms) grace window.

- **Auth:** Device Token
- **Body:**
```json
{
  "requestId": "e3f4a5b6-1234-5678-9abc-def012345678",
  "eventId": "a9b8c7d6-0000-4000-8000-000000000003"
}
```
- **Response (200 OK):**
```json
{
  "success": true,
  "undoneEventId": "a9b8c7d6-0000-4000-8000-000000000003",
  "restoredState": "clocked_in",
  "activeSince": "2026-10-04T08:00:00.000Z",
  "targetClockOutUtc": null,
  "serverTime": "2026-10-04T16:02:00.000Z",
  "todaySeconds": 0,
  "monthSeconds": 55800,
  "latestEvent": {
    "id": "f5a6b7c8-0000-4000-8000-000000000002",
    "eventType": "clock_in",
    "occurredAtUtc": "2026-10-04T08:00:00.000Z"
  }
}
```

---

### 4.3 History & Events

#### `GET /api/v1/events`
Queries raw clock events within a date range (maximum range: 93 days). Note: historical entries or D1 script inserts may carry `source: "admin_manual"`.

- **Auth:** Device Token
- **Query Parameters:**
  - `from` (required): ISO 8601 start date/timestamp.
  - `to` (required): ISO 8601 end date/timestamp.
- **Response (200 OK):**
```json
[
  {
    "id": "f5a6b7c8-0000-4000-8000-000000000002",
    "requestId": "c1f2b3a4-1234-5678-9abc-def012345678",
    "userId": "default-user",
    "deviceId": "primary-phone",
    "eventType": "clock_in",
    "source": "flutter_app",
    "occurredAtUtc": "2026-10-04T08:00:00.000Z",
    "createdAtUtc": "2026-10-04T08:00:00.000Z",
    "location": "remote",
    "note": null
  }
]
```

---

### 4.4 Reporting & R2 Engine

#### `POST /api/v1/reports/generate`
Generates an on-demand Excel data report (`.xlsx`, custom date range) or Formal Contract Report (`.docx`, locked to the full current Warsaw month).

- **Auth:** Device Token
- **Body (`.xlsx` — Personal Excel Data Report):**
```json
{
  "format": "xlsx",
  "startDate": "2026-09-01",
  "endDate": "2026-09-30",
  "preset": "full"
}
```
- **Body (`.docx` — Formal Contract Report for Current Month):**
```json
{
  "format": "docx",
  "preset": "formal",
  "plannedShifts": [
    { "date": "2026-10-27", "durationMinutes": 480 },
    { "date": "2026-10-28", "durationMinutes": 360 }
  ]
}
```
- **Formats:**
  - `xlsx`: Complete shift log with Date, Start Time (Warsaw), End Time (Warsaw), Duration, Location (`Remote` / `In-Office`), Source, Shift Notes, and Summary Statistics.
  - `docx`: Populates the private `templates/umowa-zlecenie.docx` template from R2 (`Załącznik nr 2` 23-row attendance table + `Rachunek do umowy zlecenia`) for the full current `Europe/Warsaw` month, summing recorded shifts and `plannedShifts` by Warsaw calendar day (`date | 0h0m | signature PNG | empty | empty`).
- **Response (200 OK):** Binary stream (`application/vnd.openxmlformats-officedocument.spreadsheetml.sheet` for `.xlsx`, or `application/vnd.openxmlformats-officedocument.wordprocessingml.document` for `.docx`) with headers:
  - `Content-Disposition: attachment; filename="work-hours-2026-09-01-to-2026-09-30-full.xlsx"` (or `zalaczniki-umowa-zlecenie-2026-10.docx`)
  - `X-Total-Hours: 168`
  - `X-Total-Shifts: 21`

#### `GET /api/v1/reports/latest`
Returns metadata and download link for the latest automated monthly report stored in R2.

- **Auth:** Device Token
- **Response (200 OK):**
```json
{
  "filename": "reports/work-hours-2026-09-full.xlsx",
  "sizeBytes": 14520,
  "uploadedAtUtc": "2026-10-01T00:00:15.000Z",
  "preset": "full",
  "month": "2026-09"
}
```

#### `GET /api/v1/reports/download/:filename`
Streams the specified `.xlsx` file securely from the Cloudflare R2 bucket.

- **Auth:** Device Token
- **Validation:** Filenames are strictly matched against `^work-hours-\d{4}-\d{2}-(formal|full)\.xlsx$`. Path traversals and slashes are rejected.
- **Response (200 OK):** Binary `.xlsx` payload with `Content-Type: application/vnd.openxmlformats-officedocument.spreadsheetml.sheet`.

---

## 5. Error Responses

Errors return standardized JSON with HTTP 4xx or 5xx status codes:

```json
{
  "error": {
    "code": "EVENT_MISMATCH",
    "message": "The specified event is not the latest event and cannot be undone.",
    "requestId": "e3f4a5b6-1234-5678-9abc-def012345678"
  }
}
```

### Common Error Codes
| Code | Status | Description |
| :--- | :---: | :--- |
| `UNAUTHORIZED` | 401 | Missing or invalid Bearer token. |
| `DEVICE_DISABLED` | 403 | The provisioned device record has `enabled = 0`. |
| `VALIDATION_ERROR` | 400 | Malformed JSON or invalid parameter format. |
| `INVALID_REQUEST_ID` | 400 | Missing or overly long `requestId` (> 128 chars). |
| `INVALID_SOURCE` | 400 | `source` not in allowlist. |
| `INVALID_LOCATION` | 400 | `location` is not `'remote'` or `'in-office'`. |
| `INVALID_OFFSET` | 400 | `offsetMinutes` must be an integer between `-120` and `120`. |
| `INVALID_TARGET` | 400 | `targetMinutes` or `deltaMinutes` invalid, in the past, or exceeds 24 hours. |
| `NOTE_TOO_LONG` | 400 | Shift note exceeds 4,000 characters. |
| `INVALID_DATE_RANGE` | 400 | `endDate` is before `startDate` or range exceeds 93 days. |
| `NO_ACTIVE_TARGET` | 400 | Relative target nudge attempted without an existing shift target. |
| `UNDO_WINDOW_EXPIRED`| 400 | More than 5 minutes elapsed since event occurrence. |
| `NOT_CLOCKED_IN` | 409 | Shift target update attempted while clocked out. |
| `STATE_CONFLICT` | 409 | Shift state changed concurrently during update; retry request. |
| `EVENT_MISMATCH` | 409 | Event to undo is not the latest event in sequence. |
| `NO_EVENTS_FOUND` | 404 | No events exist to query or undo. |
| `REPORT_NOT_FOUND` | 404 | Requested report file does not exist in R2 bucket. |
| `STORAGE_NOT_CONFIGURED` | 503 | Cloudflare R2 binding is not configured. |
| `INTERNAL_ERROR` | 500 | Unhandled server exception. |
