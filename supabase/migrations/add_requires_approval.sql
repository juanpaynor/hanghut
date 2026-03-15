-- Add requires_approval column to tables
-- Default false = auto-join (current behavior preserved)
-- When true = joins go to 'pending' for host approval

ALTER TABLE tables ADD COLUMN requires_approval BOOLEAN NOT NULL DEFAULT false;
