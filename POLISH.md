# Work Hours Tracker: Polish and Hardening Checklist

**Document purpose:** Consolidate architectural concerns, security hardening, documentation cleanup, cross-platform polish, and pre-v1.0 follow-up work identified during review of the project around v0.3.1.

**How to use this document:**

- Treat each checkbox as a review item, not an automatic requirement.
- Prioritize correctness and security over cosmetic cleanup.
- Complete critical web-security work before publicly deploying Flutter Web.
- When a decision is made, record it in `DESIGN.md` and close or annotate the corresponding item here.
- Do not expand the product into a multi-user or enterprise system merely to satisfy a checklist item.

---

## 1. Priority Summary

### Critical Before Public Flutter Web Deployment

- [ ] Define a browser-appropriate credential model.
- [ ] Never compile a device token or admin token into the Flutter Web build.
- [ ] Do not persist the admin token in browser storage.
- [ ] Configure strict production CORS rules.
- [ ] Add safe browser download behavior for generated reports.
- [ ] Review note rendering for cross-site scripting and unsafe HTML.
- [ ] Ensure R2 downloads cannot use arbitrary client-provided object keys.
- [ ] Add Cloudflare Pages single-page application route fallback.

### High-Priority Correctness and Reliability

- [ ] Verify monthly report boundaries using `Europe/Warsaw`, including daylight-saving transitions.
- [ ] Clarify and test the app/widget synchronization model.
- [ ] Verify undo behavior, idempotency, and concurrent clock actions.
- [ ] Add compatibility and security tests for the custom OpenXML generator.
- [ ] Define processed-request retention.
- [ ] Add report metadata and generation idempotency.

### Documentation and Project Polish

- [ ] Split the oversized README into focused documents.
- [ ] Align roadmap phases with semantic release versions.
- [ ] Add a changelog.
- [ ] Make feature wording technically precise.
- [ ] Document platform-specific behavior and limitations.

---

## 2. Flutter Web Security Model

The web client runs in a fundamentally different security environment from the Android app. Browser-delivered code and configuration are inspectable, browser storage is accessible to page scripts, and cross-site scripting can expose stored credentials.

### 2.1 Separate Credentials by Client

Use separate device records and bearer tokens for Android and web.

Recommended identity model:

```text
primary-phone
  -> Flutter Android app
  -> Android home-screen widget

personal-web
  -> Flutter Web client

admin credential
  -> privileged manual maintenance only
  -> never embedded in either client build
```

Checklist:

- [ ] Provision a separate device token for Flutter Web.
- [ ] Ensure the server derives the trusted `device_id` from the presented token.
- [ ] Keep the request `source` as telemetry only.
- [ ] Do not rely on `source` to authorize an operation.
- [ ] Allow individual device credentials to be disabled or rotated.
- [ ] Confirm that revoking the web token does not revoke the Android token.

Suggested source values:

```text
flutter_android
android_widget
flutter_web
admin_manual
scheduled_report
```

### 2.2 Never Embed Secrets in the Web Build

Do not use build-time variables for bearer credentials:

```bash
# Do not do this
flutter build web --dart-define=DEVICE_TOKEN=secret
```

Values shipped to a browser must be considered public and extractable.

Checklist:

- [ ] Permit a build-time API base URL only if it is non-secret.
- [ ] Verify generated JavaScript does not contain device or admin tokens.
- [ ] Search built web assets for known secret fragments before deployment.
- [ ] Do not put credentials in `index.html`, JavaScript configuration, service-worker files, or Pages environment output.

### 2.3 Admin Operations in the Browser

The admin token should not be stored persistently in Flutter Web.

Acceptable short-term approaches:

1. Keep administrative correction features Android-only.
2. Ask for the admin credential when needed and retain it only in memory.
3. Create a short-lived elevated server session.
4. Introduce a narrowly scoped correction credential that cannot provision devices or perform unrelated maintenance.

Recommended initial choice:

```text
Normal web device token:
- status
- clock in/out
- event history
- report generation/download

Admin credential:
- entered only for a correction operation
- held only in memory
- cleared after use or page refresh
```

Checklist:

- [ ] Remove persistent admin-token storage from the web target.
- [ ] Ensure autocomplete and logs do not expose the admin token.
- [ ] Do not include an admin token in URLs or query parameters.
- [ ] Consider omitting manual backfill from the first web release.

### 2.4 CORS

The native Android app does not need browser CORS permissions, but Flutter Web does.

Checklist:

- [ ] Allow only the production Cloudflare Pages origin.
- [ ] Allow only explicit local development origins.
- [ ] Handle `OPTIONS` preflight requests correctly.
- [ ] Allow only required methods and headers.
- [ ] Include `Authorization` and `Content-Type` only where needed.
- [ ] Do not return a wildcard origin for credential-bearing APIs.
- [ ] Add `Vary: Origin` when dynamically returning allowed origins.
- [ ] Reject unrecognized browser origins.
- [ ] Test production and local development origins independently.

### 2.5 Browser Security Headers

Review Worker and Pages responses for sensible browser security headers.

Candidates:

```text
Content-Security-Policy
Referrer-Policy
X-Content-Type-Options
Permissions-Policy
Cross-Origin-Resource-Policy
```

Checklist:

- [ ] Define a Content Security Policy compatible with Flutter Web.
- [ ] Avoid unsafe script allowances where feasible.
- [ ] Disable unnecessary browser capabilities through `Permissions-Policy`.
- [ ] Set `X-Content-Type-Options: nosniff`.
- [ ] Confirm report downloads use the intended MIME type.

---

## 3. Flutter Web Platform Adaptation

Flutter Web should be treated as another API client with shared application logic, not as Android behavior running in a browser.

### 3.1 Share Appropriate Code

Good candidates for reuse:

- Riverpod state and providers.
- API client and request models.
- Duration formatting.
- Server-response models.
- Theme tokens.
- Most screen composition.
- Business rules that are genuinely client-side.

Checklist:

- [ ] Keep authoritative state and time calculations on the server.
- [ ] Do not duplicate server transition rules in Flutter.
- [ ] Reuse API contracts without forcing Android-only behavior into web code.

### 3.2 Isolate Platform Services

Define narrow platform abstractions instead of spreading `kIsWeb` checks throughout feature code.

Suggested services:

```text
CredentialStore
HapticFeedbackService
ReportOpenService
WidgetSyncService
NotificationService
FileDownloadService
```

Checklist:

- [ ] Provide Android and web implementations where behavior differs.
- [ ] Make haptic feedback a no-op where unsupported.
- [ ] Make widget synchronization Android-only.
- [ ] Make Android notification services unavailable on web without breaking shared code.
- [ ] Use dependency injection through Riverpod rather than global platform checks.

### 3.3 Report Opening and Downloading

Platform behavior should differ cleanly:

```text
Android:
authenticated request
  -> cache file locally
  -> FileProvider URI
  -> ACTION_VIEW

Web:
authenticated fetch
  -> Blob
  -> temporary object URL
  -> browser download
  -> revoke object URL
```

Checklist:

- [ ] Do not attempt to invoke Android intents on web.
- [ ] Set a safe download filename received from trusted server metadata.
- [ ] Revoke browser object URLs after use.
- [ ] Show useful errors when downloading or browser handling fails.
- [ ] Avoid exposing bearer tokens in downloadable URLs.

### 3.4 Responsive Web Scope

The first web release should remain deliberately small.

Suggested first scope:

- [ ] Authentication and configuration.
- [ ] Current state.
- [ ] Clock in.
- [ ] Clock out.
- [ ] Today total.
- [ ] Month-to-date total.
- [ ] Recent shifts.
- [ ] Report download.

Defer until the core web flow is stable:

- [ ] Administrative manual backfill.
- [ ] Full notes editing.
- [ ] Advanced report configuration.
- [ ] Browser notifications.
- [ ] Complex desktop-only layouts.

### 3.5 Cloudflare Pages Routing

Flutter Web is a single-page application.

Checklist:

- [ ] Add fallback routing so unknown application routes return `index.html`.
- [ ] Test direct navigation to nested routes.
- [ ] Test browser refresh while on nested routes.
- [ ] Confirm static assets are not accidentally rewritten to `index.html`.
- [ ] Decide whether to use hash routes or path-based routes and document the choice.

### 3.6 Service-Worker Caching

A stale cached web build can interact badly with a newly deployed API contract.

Checklist:

- [ ] Decide how Flutter's service worker should cache application assets.
- [ ] Test application updates after deployment.
- [ ] Avoid indefinitely caching sensitive API responses.
- [ ] Show an update or reload prompt if appropriate.
- [ ] Version breaking API changes rather than depending on simultaneous client refresh.

---

## 4. Authentication and Token Handling

### 4.1 Clarify the Authentication Language

Preferred description:

> SHA-256-hashed high-entropy device-token authentication with timing-safe digest comparison.

Avoid implying that raw SHA-256 is a recommended password-hashing scheme. It is suitable here because the input is a cryptographically random, high-entropy token and a server-side pepper is used.

Checklist:

- [ ] Document expected token entropy and generation method.
- [ ] Store only a hash or keyed digest in D1.
- [ ] Keep the pepper in Worker secrets.
- [ ] Use timing-safe comparison on equal-length digest bytes.
- [ ] Reject malformed token formats before database work where appropriate.
- [ ] Never log presented tokens, token hashes, or authorization headers.

### 4.2 Android Credential Storage

Checklist:

- [ ] Store the Android device token through secure local storage.
- [ ] Verify how the native widget accesses the credential.
- [ ] Avoid duplicating plaintext credentials into ordinary SharedPreferences.
- [ ] Define behavior after application reinstall or storage loss.
- [ ] Provide a safe reprovisioning process.

### 4.3 Admin-Token Scope

Checklist:

- [ ] Ensure the admin token is separate from the device token.
- [ ] Do not include the admin token in the widget.
- [ ] Do not expose it in a Flutter Web production build.
- [ ] Consider splitting correction and provisioning privileges if the admin surface grows.
- [ ] Add rate limiting and detailed audit records for admin operations.

---

## 5. App and Widget Consistency Model

The Flutter app and native Android widget are independent API clients. Direct app-to-widget communication is an optimization for immediate refresh, not the source of truth.

### 5.1 Clarify the Documented Behavior

Recommended README wording:

> **Independent API Client:** The widget records actions directly through the Worker API without requiring the Flutter runtime. App actions request an immediate widget refresh through the native Android host when available. Both clients reconcile independently with the authoritative server state.

Consistency flow:

```text
Widget action
  -> Worker API
  -> widget updates from response

App action
  -> Worker API
  -> app updates from response
  -> app requests native widget refresh when available

App foreground resume
  -> GET /status

Widget refresh
  -> GET /status
```

Checklist:

- [ ] Ensure widget clock actions do not require the Flutter engine.
- [ ] Treat MethodChannel communication as optional refresh signaling.
- [ ] Refetch state when Flutter returns to the foreground.
- [ ] Refetch state during an appropriate widget refresh cycle.
- [ ] Never authorize a transition based on cached app or widget state.
- [ ] Return the resulting authoritative state from every clock command.

### 5.2 Widget Display Accuracy

Avoid promising a continuously current timer unless Android background behavior genuinely provides it.

Preferred wording:

> **Current-State Display:** Shows the last synchronized clock state, active-since time, derived duration, and last synchronization timestamp.

Safer widget content:

```text
Clocked in since 08:13
Last synced 08:13
```

Checklist:

- [ ] Document whether elapsed duration updates periodically or only on refresh.
- [ ] Prefer active-since time when frequent updates are unreliable.
- [ ] Do not update every second from a home-screen widget.
- [ ] Avoid battery-heavy background work solely for display freshness.
- [ ] Display the last-sync time so stale data is apparent.
- [ ] Test behavior when Android kills or recreates the widget process.

---

## 6. Time, Timezone, and Calendar Boundaries

### 6.1 Monthly Cron Semantics

The configured cron:

```text
0 0 1 * *
```

runs at midnight UTC on the first day of the month. In Warsaw, that is normally 01:00 or 02:00 depending on daylight-saving time. This is acceptable only if report boundaries are explicitly calculated as Warsaw calendar boundaries.

Required algorithm:

```text
1. Determine the previous calendar month in Europe/Warsaw.
2. Construct local start: first day at 00:00 Europe/Warsaw.
3. Construct local end: first day of current month at 00:00 Europe/Warsaw.
4. Convert both instants to UTC.
5. Query using the half-open interval [startUtc, endUtc).
```

Checklist:

- [ ] Do not assume UTC month boundaries equal Warsaw month boundaries.
- [ ] Do not subtract a fixed UTC offset.
- [ ] Use half-open intervals for event queries.
- [ ] Test standard-time and daylight-saving months.
- [ ] Test the March and October transition periods.
- [ ] Record the report timezone in report metadata.

### 6.2 Duration Calculations

Checklist:

- [ ] Pair events in UTC.
- [ ] Calculate elapsed duration from UTC instants.
- [ ] Convert to Warsaw local time only for display and calendar grouping.
- [ ] Keep the live Flutter timer visual only.
- [ ] Confirm the visual timer derives from a server-confirmed `activeSince` value.
- [ ] Do not write per-second events or totals to the server.

Preferred feature wording:

> The UI calculates a live elapsed display from the server-confirmed active timestamp. The live ticker is presentational and is not authoritative.

### 6.3 Cross-Midnight and Month-Boundary Shifts

Checklist:

- [ ] Document whether a cross-midnight shift belongs to its start date or is split.
- [ ] Apply the rule consistently to app totals and reports.
- [ ] Test a shift beginning before midnight and ending afterward.
- [ ] Test a shift spanning the final day of a month.
- [ ] Ensure the report does not omit or double-count boundary shifts.

---

## 7. State Machine, Idempotency, and Undo

### 7.1 Explicit Transition Rules

Maintain explicit clock-in and clock-out endpoints. Do not introduce a toggle endpoint.

Expected transitions:

```text
clocked_out + clock-in  -> clocked_in  + insert event
clocked_in  + clock-in  -> clocked_in  + no new event
clocked_in  + clock-out -> clocked_out + insert event
clocked_out + clock-out -> clocked_out + no new event
```

Checklist:

- [ ] Repeat requests safely.
- [ ] Return the resulting state even when no change is required.
- [ ] Use server-generated timestamps for normal actions.
- [ ] Test app and widget requests arriving concurrently.
- [ ] Test a committed operation whose HTTP response is lost.

### 7.2 Processed-Request Retention

The README promises cached results for duplicate `requestId` values. Define how long those records remain available.

Possible policy:

```text
Processed requests are retained indefinitely because the volume is negligible
for a single-user application.
```

Or:

```text
Processed requests are retained for 90 days through a scheduled cleanup task.
```

Checklist:

- [ ] Choose and document a retention policy.
- [ ] Ensure cleanup cannot remove very recent request records.
- [ ] Confirm the policy is long enough for realistic delayed retries.
- [ ] Monitor table growth before adding unnecessary cleanup complexity.

### 7.3 Undo Semantics

The five-minute undo window needs precise behavior.

Checklist:

- [ ] Define whether undo inserts a compensating event or marks/reverts the latest event.
- [ ] Preserve an audit trail of the original action and its undo.
- [ ] Ensure undo is itself idempotent.
- [ ] Reject undo after the grace window.
- [ ] Reject undo when a later valid event exists.
- [ ] Define behavior when app and widget both attempt undo.
- [ ] Return the resulting authoritative state.
- [ ] Store server time as the undo-window authority.
- [ ] Test exact boundary behavior at five minutes.
- [ ] Test duplicate undo requests.

### 7.4 Concurrency

Checklist:

- [ ] Verify the state check and event insertion form one logical atomic operation.
- [ ] Use a state version or equivalent conditional update if necessary.
- [ ] Test two different request IDs attempting the same transition simultaneously.
- [ ] Test opposing actions arriving almost simultaneously.
- [ ] Ensure the unique request constraint is handled as an expected retry case.

---

## 8. Notes and Markdown Handling

Markdown notes are useful, but they create rendering and export decisions.

Recommended contract:

```text
Stored value: raw Markdown text
Android rendering: sanitized supported subset
Web rendering: sanitized supported subset
Raw HTML: disabled
Excel output: plain text, with an explicitly documented Markdown policy
```

Checklist:

- [ ] Define the supported Markdown subset.
- [ ] Disable raw HTML in Markdown notes.
- [ ] Sanitize links and rendered content on web.
- [ ] Decide whether reports retain Markdown syntax or strip it to plain text.
- [ ] Test long notes and multiline notes.
- [ ] Test Unicode and emoji.
- [ ] Test XML-sensitive characters: `&`, `<`, `>`, quotes, and apostrophes.
- [ ] Apply a maximum note length on both client and server.
- [ ] Ensure autosave failures are visible.
- [ ] Define whether in-progress notes survive application restarts.
- [ ] Ensure notes are associated with the intended active shift under races.

### Spreadsheet Formula Injection

Any note or user-controlled text beginning with the following characters may be interpreted as a spreadsheet formula:

```text
=
+
-
@
```

Checklist:

- [ ] Escape or neutralize formula-like user text in Excel cells.
- [ ] Test malicious-looking note values.
- [ ] Apply protection to reasons, labels, sources, and other exported text fields.

---

## 9. OpenXML Report Generator

The custom pure-JavaScript `.xlsx` generator removes runtime dependencies but creates a significant compatibility and maintenance surface.

### 9.1 Correctness and Compatibility

Test generated workbooks in:

- [ ] Microsoft Excel.
- [ ] Google Sheets.
- [ ] LibreOffice Calc.

Test workbook cases:

- [ ] Empty date range.
- [ ] One shift.
- [ ] Large month.
- [ ] Long notes.
- [ ] Unicode and emoji.
- [ ] XML-sensitive characters.
- [ ] Formula-like text.
- [ ] Very long source or reason values.
- [ ] March DST transition.
- [ ] October DST transition.
- [ ] Cross-midnight shifts.
- [ ] Incomplete shift data.

### 9.2 OpenXML Package Validation

Checklist:

- [ ] Verify required ZIP entries exist.
- [ ] Verify relationships and content types.
- [ ] Validate XML escaping consistently.
- [ ] Check worksheet names and invalid characters.
- [ ] Enforce Excel worksheet-name length limits.
- [ ] Confirm numeric durations are represented consistently.
- [ ] Confirm column widths are bounded.
- [ ] Confirm generated files are deterministic where practical.
- [ ] Verify the content type is the official `.xlsx` MIME type.

### 9.3 Worker Resource Use

Checklist:

- [ ] Measure report-generation CPU time.
- [ ] Measure memory use for the largest realistic report.
- [ ] Avoid unbounded in-memory buffers.
- [ ] Add a maximum custom-report range.
- [ ] Return a clear error when a requested report is too large.
- [ ] Confirm scheduled generation fits current Worker limits.
- [ ] Avoid calling the generator more than once for an idempotent request.

### 9.4 “Zero Dependency” Wording

Avoid treating zero dependencies as automatically superior. The tradeoff is fewer third-party packages versus more project-owned ZIP and OpenXML code.

Recommended wording:

> A Worker-compatible custom OpenXML generator creates `.xlsx` reports without Node.js filesystem APIs. Compatibility is covered by automated package tests and manual validation in common spreadsheet applications.

---

## 10. R2 Report Storage and Download Security

### 10.1 Do Not Authorize by Filename

Current-looking route:

```text
GET /api/v1/reports/download/:filename
```

Preferred route:

```text
GET /api/v1/reports/:reportId/download
```

Recommended flow:

```text
1. Authenticate the caller.
2. Look up reportId in D1.
3. Verify the report belongs to the expected user or type.
4. Read the server-controlled R2 object key from metadata.
5. Stream the object with safe response headers.
```

Checklist:

- [ ] Do not accept a full R2 key from the client.
- [ ] Do not use a client-provided filename directly for object access.
- [ ] Reject slashes and traversal-like values if filename routes remain.
- [ ] Prefix R2 keys on the server.
- [ ] Set `Content-Type` explicitly.
- [ ] Set a sanitized `Content-Disposition` filename.
- [ ] Require authentication for report metadata and downloads.
- [ ] Avoid bearer tokens in signed or query-string download URLs.

### 10.2 Report Metadata

Store report metadata in D1:

```text
report_id
user_id
period_start_utc
period_end_utc
timezone
preset
options_json
r2_object_key
sha256
size_bytes
generated_at_utc
generation_source
status
```

Checklist:

- [ ] Add a report metadata table if not already present.
- [ ] Use a stable report ID separate from the R2 key.
- [ ] Record generation status and failures.
- [ ] Record a checksum for integrity and diagnostics.
- [ ] Record the exact period and timezone.
- [ ] Allow regenerated reports to be distinguished from prior versions.

### 10.3 Scheduled-Report Idempotency

Checklist:

- [ ] Prevent duplicate monthly reports for the same period and preset.
- [ ] Use a database uniqueness rule or idempotency key.
- [ ] Make retries safe if R2 upload succeeds but metadata insertion fails.
- [ ] Define whether regeneration replaces or versions an existing report.
- [ ] Log generation failures without leaking credentials or report contents.

### 10.4 R2 Lifecycle and Retention

Checklist:

- [ ] Define whether reports are retained indefinitely.
- [ ] Decide how obsolete regenerated reports are handled.
- [ ] Keep R2 bucket access private.
- [ ] Document that R2 reports are derived artifacts while D1 events are primary data.

---

## 11. API and Error Contract Polish

### 11.1 Document Complete Contracts

For each endpoint, document:

- Method and route.
- Authentication type.
- Request body.
- Success response.
- Idempotency behavior.
- Validation rules.
- Status codes.
- Stable error codes.
- Side effects.
- Source attribution rules.

Checklist:

- [ ] Move detailed endpoint documentation to `docs/API.md`.
- [ ] Include example requests and responses.
- [ ] Clarify whether no-op transitions return `200` or `409`.
- [ ] Clarify how duplicate `requestId` responses are replayed.
- [ ] Document custom-report size and range limits.
- [ ] Document undo-window errors.

### 11.2 Input Validation

Checklist:

- [ ] Validate `requestId` format and maximum length.
- [ ] Validate `source` against a fixed allow-list.
- [ ] Validate date ranges and maximum span.
- [ ] Validate note length.
- [ ] Validate manual shifts and overlaps.
- [ ] Reject unknown JSON fields if strict contracts are desired.
- [ ] Limit request body size.
- [ ] Use parameterized D1 statements.

### 11.3 Security and Cache Headers

Checklist:

- [ ] Mark authenticated API responses as non-publicly cacheable.
- [ ] Prevent accidental caching of token-bearing error responses.
- [ ] Set safe headers for report binary responses.
- [ ] Avoid leaking internal SQL, bindings, stack traces, or object keys.

---

## 12. Manual Backfill and Corrections

### 12.1 Administrative Backfill

Checklist:

- [ ] Require an admin credential.
- [ ] Require a reason.
- [ ] Record creation time separately from historical occurrence time.
- [ ] Reject reversed timestamps.
- [ ] Enforce a reasonable maximum duration.
- [ ] Check overlap with existing shifts.
- [ ] Make manual requests idempotent.
- [ ] Audit the source as `admin_manual`.
- [ ] Preserve evidence of later edits or deletions.

### 12.2 Past-Note Editing

If inline editing is introduced:

- [ ] Do not disguise an edit as an original value.
- [ ] Store modification metadata or an audit record.
- [ ] Define who can edit and through which credential.
- [ ] Prevent stale clients from overwriting newer edits.
- [ ] Confirm reports use the intended latest value.

---

## 13. Android Report Opening and File Handling

Checklist:

- [ ] Use a configured FileProvider rather than `file://` URIs.
- [ ] Grant temporary read permission to the receiving application.
- [ ] Use the official `.xlsx` MIME type.
- [ ] Handle the absence of a compatible viewer gracefully.
- [ ] Use sanitized local filenames.
- [ ] Keep report cache files in application-controlled storage.
- [ ] Define cleanup for old cached reports.
- [ ] Verify downloaded bytes or checksum when metadata provides one.
- [ ] Do not expose bearer tokens to external viewer intents.

---

## 14. README and Documentation Restructure

The current README combines product overview, architecture specification, setup manual, API reference, and roadmap. Split responsibilities while preserving a concise entry point.

### 14.1 Keep in `README.md`

- [ ] One-paragraph product purpose.
- [ ] Current version and project status.
- [ ] Supported platforms.
- [ ] Screenshot or concise UI preview.
- [ ] High-level architecture diagram.
- [ ] Current feature summary.
- [ ] Technology stack.
- [ ] Short quick-start instructions.
- [ ] Repository layout.
- [ ] Links to detailed documents.
- [ ] Short roadmap summary.

Suggested status block:

```markdown
**Current version:** v0.3.1
**Status:** Personal beta, actively used
**Platforms:** Android and Cloudflare Worker; Flutter Web in progress
```

### 14.2 Keep in `DESIGN.md`

- [ ] State-machine rules.
- [ ] Authoritative server-time behavior.
- [ ] Event pairing and duration rules.
- [ ] Idempotency guarantees.
- [ ] Undo semantics.
- [ ] Warsaw timezone boundaries.
- [ ] D1 schema decisions.
- [ ] Authentication and security model.
- [ ] Widget and app consistency model.
- [ ] R2 report lifecycle.
- [ ] Explicit non-goals.

### 14.3 Create `docs/API.md`

- [ ] Endpoint reference.
- [ ] Authentication.
- [ ] Request and response examples.
- [ ] Error codes.
- [ ] Idempotency behavior.
- [ ] Report request options.

### 14.4 Create `docs/DEPLOYMENT.md`

- [ ] Prerequisites.
- [ ] D1 creation and migration.
- [ ] R2 creation.
- [ ] Worker secrets.
- [ ] Device provisioning.
- [ ] Worker deployment.
- [ ] GitHub Actions secrets.
- [ ] Flutter Android build.
- [ ] Flutter Web and Cloudflare Pages deployment.
- [ ] Rollback and recovery notes.

### 14.5 Add `CHANGELOG.md`

Use release-oriented entries:

```markdown
## [0.3.1]

### Added

- Flutter Web target.
- Responsive clock interface.

### Fixed

- Warsaw monthly report boundary behavior.
- Widget refresh after an application clock action.

### Changed

- Separate device credentials for Android and web.
```

Checklist:

- [ ] Add entries for existing releases if history is available.
- [ ] Update the changelog as part of release preparation.
- [ ] Keep unreleased work under an `Unreleased` section.

---

## 15. Versioning and Roadmap Alignment

The README currently combines semantic versions such as v0.3.1 with roadmap phases such as Phase 5. Choose a clear convention.

Recommended approach:

```text
Semantic versions:
- code and release history

Named milestones:
- product roadmap
```

Example roadmap:

```text
Completed: Core Tracking
Completed: Android Client and Widget
Completed: Reporting and R2 Storage
In Progress: Web Access
Planned: Shift Goals and Reminders
Planned: Productivity Insights
Planned: Backups and Maintenance
```

Checklist:

- [ ] Replace unexplained “Phase 5” numbering or document phases 1 through 4.
- [ ] Keep release versions in `CHANGELOG.md`.
- [ ] Keep roadmap milestones user-facing and outcome-based.
- [ ] Define what qualifies the application for v1.0.

---

## 16. Feature Wording and Technical Precision

Update marketing-style statements so they accurately describe implementation guarantees.

### Authentication

Replace:

```text
Timing-safe SHA-256 Auth
```

With:

```text
SHA-256-hashed high-entropy device-token authentication with timing-safe
digest comparison
```

### Live Timer

Replace any implication that the live timer is authoritative with:

```text
The client displays a live elapsed duration derived from the server-confirmed
active timestamp. The server remains authoritative.
```

### Widget State

Prefer:

```text
Current-state display with active-since time and last synchronization timestamp
```

rather than promising continuous real-time mirroring.

### Independent Widget

Clarify:

```text
The widget calls the API independently. App-to-widget MethodChannel messages
request an immediate visual refresh but are not required for consistency.
```

### OpenXML Generator

Prefer:

```text
Worker-compatible custom OpenXML generator with compatibility tests
```

rather than presenting zero dependencies as an unqualified benefit.

Checklist:

- [ ] Make all README guarantees testable.
- [ ] Mark planned features clearly as planned.
- [ ] Avoid calling cached state real-time unless refresh behavior supports it.
- [ ] Distinguish security controls from infallible security claims.

---

## 17. Testing Gaps to Close

### 17.1 Backend State Tests

- [ ] Normal clock-in.
- [ ] Repeated clock-in.
- [ ] Normal clock-out.
- [ ] Repeated clock-out.
- [ ] Same request ID replay.
- [ ] Simultaneous clock-in requests.
- [ ] Simultaneous opposing requests.
- [ ] Lost response followed by retry.
- [ ] Undo success.
- [ ] Duplicate undo.
- [ ] Expired undo.
- [ ] Undo after a later action.

### 17.2 Time Tests

- [ ] Warsaw standard-time date.
- [ ] Warsaw daylight-time date.
- [ ] March DST transition.
- [ ] October DST transition.
- [ ] Cross-midnight shift.
- [ ] Cross-month shift.
- [ ] Previous-month cron range.
- [ ] Half-open date-range boundaries.

### 17.3 Authentication Tests

- [ ] Valid Android token.
- [ ] Valid web token.
- [ ] Disabled device.
- [ ] Invalid token.
- [ ] Missing token.
- [ ] Wrong admin token.
- [ ] Device token used on an admin route.
- [ ] Token not present in logs.

### 17.4 Web Tests

- [ ] Allowed production origin.
- [ ] Allowed local development origin.
- [ ] Rejected unknown origin.
- [ ] Successful preflight.
- [ ] Direct nested-route load.
- [ ] Browser refresh on a nested route.
- [ ] Authenticated report Blob download.
- [ ] No embedded tokens in built assets.
- [ ] Sanitized Markdown rendering.

### 17.5 Android Tests

- [ ] App clock action refreshes the widget when possible.
- [ ] Widget operates without Flutter running.
- [ ] App refreshes after widget use.
- [ ] Credential loss and reprovisioning.
- [ ] Report opens through FileProvider.
- [ ] No compatible spreadsheet viewer.
- [ ] Widget stale-state display.

### 17.6 Report Tests

- [ ] Excel, Google Sheets, and LibreOffice compatibility.
- [ ] Empty report.
- [ ] Formula-injection strings.
- [ ] Unicode notes.
- [ ] XML-sensitive text.
- [ ] Large custom-range rejection.
- [ ] Monthly generation idempotency.
- [ ] Authorized report download.
- [ ] Unknown report ID.
- [ ] Attempted arbitrary R2 key access.

---

## 18. Observability and Maintenance

### 18.1 Logging

Log:

- Request correlation ID.
- Authenticated device ID.
- Operation name.
- Declared source.
- State-change result.
- Event ID when created.
- Report ID.
- Generation status.
- Latency and high-level failure code.

Do not log:

- Bearer tokens.
- Token hashes.
- Authorization headers.
- Full note text unless explicitly required.
- Admin credentials.
- Arbitrary R2 keys received from clients.
- Stack traces in client responses.

Checklist:

- [ ] Confirm logs support diagnosing a lost-response retry.
- [ ] Confirm logs can distinguish Android, widget, and web device records.
- [ ] Add report-generation failure context without report contents.

### 18.2 Backups

D1 events are primary data. R2 workbooks are derived artifacts.

Checklist:

- [ ] Add a documented D1 export procedure.
- [ ] Test restoration into a non-production database.
- [ ] Never overwrite production while testing restore.
- [ ] Keep backup files outside Git.
- [ ] Exclude tokens or hash and secret material where practical.
- [ ] Define how often manual or scheduled backups are expected.

### 18.3 Migration Safety

- [ ] Never modify an already applied production migration.
- [ ] Use additive migrations where possible.
- [ ] Apply schema expansion before deploying code that requires it.
- [ ] Use multi-release expand-and-contract changes for breaking migrations.
- [ ] Export D1 before risky migrations.
- [ ] Keep production database creation out of normal deployment workflows.

---

## 19. Suggested Execution Order

### Stage A: Web Deployment Blockers

1. [ ] Create a separate web device credential.
2. [ ] Remove persistent admin credentials from web.
3. [ ] Add strict CORS handling.
4. [ ] Add Pages SPA fallback.
5. [ ] Implement browser Blob downloads.
6. [ ] Sanitize Markdown rendering.
7. [ ] Verify the web build contains no secrets.

### Stage B: Reporting Hardening

1. [ ] Replace filename-based report lookup with report IDs.
2. [ ] Add D1 report metadata.
3. [ ] Add generation idempotency.
4. [ ] Test Warsaw monthly boundaries.
5. [ ] Add OpenXML compatibility and injection tests.
6. [ ] Measure Worker CPU and memory use.

### Stage C: Consistency and Documentation

1. [ ] Clarify widget and app synchronization wording.
2. [ ] Define widget timer and update semantics.
3. [ ] Define undo audit behavior.
4. [ ] Define processed-request retention.
5. [ ] Split README content into focused documents.
6. [ ] Add a changelog and align the roadmap.

### Stage D: Pre-v1.0 Reliability

1. [ ] Complete concurrency tests.
2. [ ] Complete DST and boundary tests.
3. [ ] Add tested backup and restore procedures.
4. [ ] Document credential rotation.
5. [ ] Resolve all remaining ambiguous guarantees in `DESIGN.md`.

---

## 20. Definition of Polished

The project can be considered polished for a stable personal release when:

- [ ] Android, widget, and web clients all reconcile with the same authoritative API state.
- [ ] No secret is embedded in Flutter Web assets.
- [ ] Admin credentials are not persistently exposed to browser storage.
- [ ] CORS is restricted to intended web origins.
- [ ] Concurrent and repeated state transitions cannot corrupt event history.
- [ ] Undo preserves an audit trail and behaves idempotently.
- [ ] Monthly reports use correct Warsaw calendar boundaries.
- [ ] R2 reports are accessed through authenticated, server-controlled report IDs.
- [ ] Generated workbooks open correctly in common spreadsheet applications.
- [ ] Formula-like text and Markdown are rendered and exported safely.
- [ ] Production D1 data survives deployments and schema migrations.
- [ ] Backup and restore procedures have been tested.
- [ ] README, design, API, deployment, and changelog documents have clear responsibilities.
- [ ] Feature claims accurately describe implemented behavior.
- [ ] Remaining roadmap items are optional enhancements rather than correctness repairs.
