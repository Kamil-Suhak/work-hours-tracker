-- Add server-managed auto-stop target timestamp for active shifts
ALTER TABLE work_state ADD COLUMN target_clock_out_utc TEXT;
