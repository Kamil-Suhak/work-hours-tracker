# Work Hours Tracker — API Reference

This document provides the authoritative reference for the Work Hours Tracker API (`/api/v1/*`).

---

## 1. Overview & Conventions

- **Base URL:** `https://<your-worker>.<subdomain>.workers.dev` (or same-origin on Web).
- **Protocol:** HTTPS only.
- **Timestamps:** ISO 8601 strings in UTC with millisecond precision (e.g. `2026-10-04T08:00:00.000Z`).
- **Timezone for Durations:** All daily boundaries and month-to-date totals are computed using `Europe/Warsaw`.
- **Request Tracing:** Every response includes `X-Correlation-ID` for diagnostics.

---

## 2. Authentication

Requests require a Bearer token in the `Authorization` header:

```http
Authorization: Bearer <token>
```

### Credentials
1. **Device Token (Client Operations):**
   - Issued to devices via `npm run provision -- "<device-name>"`.
   - Stored in Cloudflare D1 `devices` table as `SHA-256(token + DEVICE_TOKEN_PEPPER)`.
   - Authorized for all standard endpoints: `status`, `clock-in`, `clock-out`, `undo`, `events`, `reports/*`.
2. **Admin Token (Maintenance Operations):**
   - Stored as a Cloudflare Worker secret (`ADMIN_API_TOKEN`).
   - Required for privileged administrative backfills (`/api/v1/admin/events/manual`).

---

## 3. Idempotency

Mutating endpoints (`clock-in`, `clock-out`, `undo`, `admin/events/manual`) require a unique client-generated `requestId` (UUID v4 recommended, max 128 characters).

- **Guarantee:** If a network retry occurs with the same `requestId`, the Worker replays the original cached response from `processed_requests` without inserting duplicate database records.
- **Retention:** Processed requests are retained indefinitely in SQLite for single-user audit stability.

---

## 4. Endpoints

### 4.1 Status & Time
#### `GET /api/v1/status`
Returns the current authoritative state, elapsed durations, and the latest event.

- **Auth:** Device Token
- **Response (200 OK):**
```json
{
  "state": "clocked_in",
  "activeSince": "2026-10-04T08:00:00.000Z",
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
  "note": "Optional initial shift note"
}
```
- **Allowed Sources:** `flutter_app`, `android_widget`, `admin_manual`, `web_dashboard`
- **Response (200 OK):**
```json
{
  "state": "clocked_in",
  "changed": true,
  "activeSince": "2026-10-04T08:00:00.000Z",
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
Transitions state from `clocked_in` to `clocked_out`, calculates shift duration, and stores the completed shift note.

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

### 4.3 History & Admin Corrections

#### `GET /api/v1/events`
Queries raw clock events within a date range (maximum range: 93 days).

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
    "note": null
  }
]
```

#### `POST /api/v1/admin/events/manual`
Inserts a historical matched shift pair (clock-in + clock-out) with validation against existing shift overlaps.

- **Auth:** Admin Token (`ADMIN_API_TOKEN`)
- **Body:**
```json
{
  "requestId": "f4a5b6c7-1234-5678-9abc-def012345678",
  "clockInAt": "2026-10-03T08:00:00.000Z",
  "clockOutAt": "2026-10-03T16:30:00.000Z",
  "reason": "Forgot phone at home",
  "note": "Worked on Q3 planning"
}
```
- **Response (200 OK):**
```json
{
  "success": true,
  "clockInEventId": "b1a2c3d4-0000-4000-8000-000000000010",
  "clockOutEventId": "b1a2c3d4-0000-4000-8000-000000000011",
  "durationSeconds": 30600
}
```

---

### 4.4 Reporting & R2 Engine

#### `POST /api/v1/reports/generate`
Generates an on-demand OpenXML spreadsheet (`.xlsx`) binary report for the specified date range.

- **Auth:** Device Token
- **Body:**
```json
{
  "startDate": "2026-09-01",
  "endDate": "2026-09-30",
  "preset": "formal",
  "options": {
    "includeNotes": false,
    "includeStats": true,
    "includeSource": false
  }
}
```
- **Presets:**
  - `formal`: Clean table with Date, Start Time (Warsaw), End Time (Warsaw), Duration, and Summary Statistics.
  - `full`: Complete log with Shift Notes, Source tags, and all statistics.
- **Response (200 OK):** Binary stream (`application/vnd.openxmlformats-officedocument.spreadsheetml.sheet`) with headers:
  - `Content-Disposition: attachment; filename="work-hours-2026-09-01-to-2026-09-30-formal.xlsx"`
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
| `INVALID_DATE_RANGE` | 400 | `endDate` is before `startDate` or range exceeds 93 days. |
| `OVERLAPPING_SHIFT` | 400 | Manual shift overlaps with existing recorded shifts. |
| `UNDO_WINDOW_EXPIRED`| 400 | More than 5 minutes elapsed since event occurrence. |
| `EVENT_MISMATCH` | 409 | Event to undo is not the latest event in sequence. |
| `NO_EVENTS_FOUND` | 404 | No events exist to query or undo. |
| `REPORT_NOT_FOUND` | 404 | Requested report file does not exist in R2 bucket. |
| `STORAGE_NOT_CONFIGURED` | 503 | Cloudflare R2 binding is not configured. |
| `INTERNAL_ERROR` | 500 | Unhandled server exception. |
