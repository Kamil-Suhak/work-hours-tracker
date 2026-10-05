-- ==============================================================================
-- Purge Shift Data (Reset Work State & Clear Events)
-- ==============================================================================
-- Purges all shift logs, notes, and idempotency request records.
-- Resets the current work status to 'clocked_out'.
--
-- NOTE: Preserves the 'devices' table so mobile and web tokens remain valid!
--
-- Usage:
--   npx wrangler d1 execute work-hours-prod --remote --file=sql/purge-shifts.sql
--   or from project root:
--   npm --prefix worker run db:purge
-- ==============================================================================

DELETE FROM events;
DELETE FROM processed_requests;
UPDATE work_state
SET state = 'clocked_out',
    active_since_utc = NULL,
    version = 1,
    updated_at_utc = datetime('now');
