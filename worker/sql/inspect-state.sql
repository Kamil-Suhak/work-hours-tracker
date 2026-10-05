-- ==============================================================================
-- Inspect Current Work State & Latest Events
-- ==============================================================================
-- Shows whether the user is currently clocked in or out, active_since timestamp,
-- and the 5 most recent events.
--
-- Usage:
--   npx wrangler d1 execute work-hours-prod --remote --file=sql/inspect-state.sql
--   or:
--   npm --prefix worker run db:status
-- ==============================================================================

SELECT
    user_id,
    state,
    COALESCE(active_since_utc, 'None (clocked out)') AS active_since,
    version,
    updated_at_utc
FROM work_state;

SELECT
    id,
    event_type,
    source,
    occurred_at_utc,
    COALESCE(note, '') AS note
FROM events
ORDER BY occurred_at_utc DESC
LIMIT 5;
