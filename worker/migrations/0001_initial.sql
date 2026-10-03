-- Initial migration: devices, work_state, events, processed_requests

CREATE TABLE devices (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    token_hash TEXT NOT NULL UNIQUE,
    enabled INTEGER NOT NULL DEFAULT 1 CHECK (enabled IN (0, 1)),
    created_at_utc TEXT NOT NULL
);

CREATE TABLE work_state (
    user_id TEXT PRIMARY KEY,
    state TEXT NOT NULL CHECK (state IN ('clocked_in', 'clocked_out')),
    active_since_utc TEXT,
    version INTEGER NOT NULL DEFAULT 0,
    updated_at_utc TEXT NOT NULL
);

CREATE TABLE events (
    id TEXT PRIMARY KEY,
    request_id TEXT NOT NULL UNIQUE,
    user_id TEXT NOT NULL,
    device_id TEXT,
    event_type TEXT NOT NULL CHECK (event_type IN ('clock_in', 'clock_out')),
    source TEXT NOT NULL CHECK (
        source IN ('flutter_app', 'android_widget', 'admin_manual', 'web_dashboard')
    ),
    occurred_at_utc TEXT NOT NULL,
    created_at_utc TEXT NOT NULL,
    reason TEXT,
    FOREIGN KEY (device_id) REFERENCES devices(id)
);

CREATE INDEX idx_events_user_occurred
ON events(user_id, occurred_at_utc);

CREATE TABLE processed_requests (
    request_id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    operation TEXT NOT NULL,
    response_json TEXT NOT NULL,
    created_at_utc TEXT NOT NULL
);
