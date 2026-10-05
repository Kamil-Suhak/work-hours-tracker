-- ==============================================================================
-- List Registered Devices
-- ==============================================================================
-- Queries all registered device records, their enabled status, and creation date.
--
-- Usage:
--   npx wrangler d1 execute work-hours-prod --remote --file=sql/list-devices.sql
--   or:
--   npm --prefix worker run db:devices
-- ==============================================================================

SELECT
    id,
    name,
    CASE enabled WHEN 1 THEN 'ACTIVE' ELSE 'REVOKED' END AS status,
    created_at_utc,
    substr(token_hash, 1, 12) || '...' AS token_hash_prefix
FROM devices
ORDER BY created_at_utc DESC;
