-- Add work location ('remote' | 'in-office') to events table, defaulting existing rows to 'remote'

ALTER TABLE events ADD COLUMN location TEXT NOT NULL DEFAULT 'remote' CHECK (location IN ('remote', 'in-office'));
