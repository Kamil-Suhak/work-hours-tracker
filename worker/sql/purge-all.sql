-- ==============================================================================
-- Full Factory Reset (Purge Everything Including Registered Devices)
-- ==============================================================================
-- WARNING: This completely wipes the database, including registered device
-- credentials. All mobile devices and web clients will need to be re-provisioned!
--
-- Usage:
--   npx wrangler d1 execute work-hours-prod --remote --file=sql/purge-all.sql
-- ==============================================================================

DELETE FROM events;
DELETE FROM processed_requests;
DELETE FROM work_state;
DELETE FROM devices;
