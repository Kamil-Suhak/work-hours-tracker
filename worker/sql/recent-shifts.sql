-- ==============================================================================
-- Query Recent Shifts & Event Log
-- ==============================================================================
-- Retrieves the 25 most recent clock-in / clock-out events with associated
-- device names and notes.
--
-- Usage:
--   npx wrangler d1 execute work-hours-prod --remote --file=sql/recent-shifts.sql
--   or:
--   npm --prefix worker run db:shifts
-- ==============================================================================

SELECT
    e.id,
    e.event_type,
    e.source,
    COALESCE(d.name, 'Admin/Manual') AS device_name,
    e.occurred_at_utc,
    COALESCE(e.note, '') AS note
FROM events e
LEFT JOIN devices d ON e.device_id = d.id
ORDER BY e.occurred_at_utc DESC
LIMIT 25;
