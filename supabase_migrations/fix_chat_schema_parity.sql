-- ============================================================================
-- CHAT SCHEMA PARITY FIX - Critical Migration
-- ============================================================================
-- Purpose: Align trip_messages and direct_messages tables with messages table
-- Issues Fixed:
--   1. Add sequence_number column (CRITICAL - fixes message ordering)
--   2. Add missing columns (reply_to_id, gif_url, deleted_at, etc.)
--   3. Create performance indexes
--   4. Add CASCADE delete constraints
--   5. Create sequence triggers
--
-- Date: 2026-01-30
-- Safe to run multiple times (uses IF NOT EXISTS / IF EXISTS)
-- ============================================================================

BEGIN;

-- ============================================================================
-- PART 1: Add sequence_number to trip_messages
-- ============================================================================

-- Step 1.1: Add the column (nullable first for backfill)
ALTER TABLE trip_messages 
ADD COLUMN IF NOT EXISTS sequence_number BIGINT;

-- Step 1.2: Backfill existing messages with correct sequence
-- This ensures messages are ordered by sent_at within each chat
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM trip_messages WHERE sequence_number IS NULL
  ) THEN
    UPDATE trip_messages 
    SET sequence_number = subquery.new_seq
    FROM (
      SELECT 
        id, 
        ROW_NUMBER() OVER (
          PARTITION BY chat_id 
          ORDER BY sent_at ASC, id ASC
        ) as new_seq
      FROM trip_messages
      WHERE sequence_number IS NULL
    ) AS subquery
    WHERE trip_messages.id = subquery.id;
    
    RAISE NOTICE 'Backfilled sequence_number for trip_messages';
  END IF;
END $$;

-- Step 1.3: Create trigger function for auto-incrementing sequence
CREATE OR REPLACE FUNCTION assign_trip_message_sequence()
RETURNS TRIGGER AS $$
BEGIN
  -- Only assign if not already set
  IF NEW.sequence_number IS NULL THEN
    SELECT COALESCE(MAX(sequence_number), 0) + 1
    INTO NEW.sequence_number
    FROM trip_messages
    WHERE chat_id = NEW.chat_id;
    
    -- Fallback to 1 if no messages exist
    IF NEW.sequence_number IS NULL THEN
      NEW.sequence_number := 1;
    END IF;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Step 1.4: Create trigger (drop first if exists)
DROP TRIGGER IF EXISTS trip_messages_sequence_trigger ON trip_messages;
CREATE TRIGGER trip_messages_sequence_trigger
BEFORE INSERT ON trip_messages
FOR EACH ROW
EXECUTE FUNCTION assign_trip_message_sequence();

-- Step 1.5: Make column NOT NULL after backfill
ALTER TABLE trip_messages 
ALTER COLUMN sequence_number SET NOT NULL;

-- Step 1.6: Add helpful comment
COMMENT ON COLUMN trip_messages.sequence_number IS 
  'Server-assigned monotonically increasing sequence number for guaranteed message ordering. Auto-incremented per chat_id.';

-- ============================================================================
-- PART 2: Add sequence_number to direct_messages
-- ============================================================================

-- Step 2.1: Add the column
ALTER TABLE direct_messages 
ADD COLUMN IF NOT EXISTS sequence_number BIGINT;

-- Step 2.2: Backfill existing messages
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM direct_messages WHERE sequence_number IS NULL
  ) THEN
    UPDATE direct_messages 
    SET sequence_number = subquery.new_seq
    FROM (
      SELECT 
        id, 
        ROW_NUMBER() OVER (
          PARTITION BY chat_id 
          ORDER BY created_at ASC, id ASC
        ) as new_seq
      FROM direct_messages
      WHERE sequence_number IS NULL
    ) AS subquery
    WHERE direct_messages.id = subquery.id;
    
    RAISE NOTICE 'Backfilled sequence_number for direct_messages';
  END IF;
END $$;

-- Step 2.3: Create trigger function
CREATE OR REPLACE FUNCTION assign_direct_message_sequence()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.sequence_number IS NULL THEN
    SELECT COALESCE(MAX(sequence_number), 0) + 1
    INTO NEW.sequence_number
    FROM direct_messages
    WHERE chat_id = NEW.chat_id;
    
    IF NEW.sequence_number IS NULL THEN
      NEW.sequence_number := 1;
    END IF;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Step 2.4: Create trigger
DROP TRIGGER IF EXISTS direct_messages_sequence_trigger ON direct_messages;
CREATE TRIGGER direct_messages_sequence_trigger
BEFORE INSERT ON direct_messages
FOR EACH ROW
EXECUTE FUNCTION assign_direct_message_sequence();

-- Step 2.5: Make NOT NULL
ALTER TABLE direct_messages 
ALTER COLUMN sequence_number SET NOT NULL;

-- Step 2.6: Add comment
COMMENT ON COLUMN direct_messages.sequence_number IS 
  'Server-assigned monotonically increasing sequence number for guaranteed message ordering. Auto-incremented per chat_id.';

-- ============================================================================
-- PART 3: Add missing feature columns to trip_messages
-- ============================================================================

-- Reply functionality
ALTER TABLE trip_messages 
ADD COLUMN IF NOT EXISTS reply_to_id uuid;

-- GIF support
ALTER TABLE trip_messages 
ADD COLUMN IF NOT EXISTS gif_url text;

-- Soft delete support
ALTER TABLE trip_messages 
ADD COLUMN IF NOT EXISTS deleted_at timestamp with time zone;

ALTER TABLE trip_messages 
ADD COLUMN IF NOT EXISTS deleted_for_everyone boolean DEFAULT false;

-- Sender name cache (for faster rendering)
ALTER TABLE trip_messages 
ADD COLUMN IF NOT EXISTS sender_name text;

-- Add FK constraint for replies (only if column exists and constraint doesn't)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint 
    WHERE conname = 'trip_messages_reply_to_id_fkey'
  ) THEN
    ALTER TABLE trip_messages 
    ADD CONSTRAINT trip_messages_reply_to_id_fkey 
    FOREIGN KEY (reply_to_id) REFERENCES trip_messages(id) ON DELETE SET NULL;
    
    RAISE NOTICE 'Added reply_to_id FK constraint to trip_messages';
  END IF;
END $$;

-- ============================================================================
-- PART 4: Add missing feature columns to direct_messages
-- ============================================================================

-- Reply functionality
ALTER TABLE direct_messages 
ADD COLUMN IF NOT EXISTS reply_to_id uuid;

-- GIF support
ALTER TABLE direct_messages 
ADD COLUMN IF NOT EXISTS gif_url text;

-- Soft delete support
ALTER TABLE direct_messages 
ADD COLUMN IF NOT EXISTS deleted_at timestamp with time zone;

ALTER TABLE direct_messages 
ADD COLUMN IF NOT EXISTS deleted_for_everyone boolean DEFAULT false;

-- Sender name cache
ALTER TABLE direct_messages 
ADD COLUMN IF NOT EXISTS sender_name text;

-- Add FK constraint for replies
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint 
    WHERE conname = 'direct_messages_reply_to_id_fkey'
  ) THEN
    ALTER TABLE direct_messages 
    ADD CONSTRAINT direct_messages_reply_to_id_fkey 
    FOREIGN KEY (reply_to_id) REFERENCES direct_messages(id) ON DELETE SET NULL;
    
    RAISE NOTICE 'Added reply_to_id FK constraint to direct_messages';
  END IF;
END $$;

-- ============================================================================
-- PART 5: Create performance indexes
-- ============================================================================

-- Index for trip_messages pagination (chat_id + sequence_number DESC)
CREATE INDEX IF NOT EXISTS idx_trip_messages_chat_sequence 
ON trip_messages(chat_id, sequence_number DESC);

-- Index for trip_messages timestamp queries (fallback)
CREATE INDEX IF NOT EXISTS idx_trip_messages_chat_sent_at 
ON trip_messages(chat_id, sent_at DESC);

-- Index for direct_messages pagination
CREATE INDEX IF NOT EXISTS idx_direct_messages_chat_sequence 
ON direct_messages(chat_id, sequence_number DESC);

-- Index for direct_messages timestamp queries
CREATE INDEX IF NOT EXISTS idx_direct_messages_chat_created_at 
ON direct_messages(chat_id, created_at DESC);

-- Ensure messages table has the right index too
CREATE INDEX IF NOT EXISTS idx_messages_table_sequence 
ON messages(table_id, sequence_number DESC);

-- Composite index for efficient pagination with ID tiebreaker
CREATE INDEX IF NOT EXISTS idx_trip_messages_chat_seq_id 
ON trip_messages(chat_id, sequence_number DESC, id);

CREATE INDEX IF NOT EXISTS idx_direct_messages_chat_seq_id 
ON direct_messages(chat_id, sequence_number DESC, id);

-- Index for deleted message queries (soft delete filtering)
CREATE INDEX IF NOT EXISTS idx_trip_messages_deleted 
ON trip_messages(chat_id, deleted_at) 
WHERE deleted_at IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_direct_messages_deleted 
ON direct_messages(chat_id, deleted_at) 
WHERE deleted_at IS NOT NULL;

-- ============================================================================
-- PART 6: Fix CASCADE delete constraints
-- ============================================================================

-- Fix trip_messages: should CASCADE when chat is deleted
DO $$
BEGIN
  -- Drop old constraint
  ALTER TABLE trip_messages 
  DROP CONSTRAINT IF EXISTS trip_messages_chat_id_fkey;
  
  -- Add new constraint with CASCADE
  ALTER TABLE trip_messages 
  ADD CONSTRAINT trip_messages_chat_id_fkey 
  FOREIGN KEY (chat_id) REFERENCES trip_group_chats(id) 
  ON DELETE CASCADE;
  
  RAISE NOTICE 'Updated trip_messages FK to CASCADE on chat deletion';
END $$;

-- Fix direct_messages: should CASCADE when chat is deleted
DO $$
BEGIN
  ALTER TABLE direct_messages 
  DROP CONSTRAINT IF EXISTS direct_messages_chat_id_fkey;
  
  ALTER TABLE direct_messages 
  ADD CONSTRAINT direct_messages_chat_id_fkey 
  FOREIGN KEY (chat_id) REFERENCES direct_chats(id) 
  ON DELETE CASCADE;
  
  RAISE NOTICE 'Updated direct_messages FK to CASCADE on chat deletion';
END $$;

-- ============================================================================
-- PART 7: Verify migration success
-- ============================================================================

DO $$
DECLARE
  trip_seq_count INTEGER;
  dm_seq_count INTEGER;
  trip_null_count INTEGER;
  dm_null_count INTEGER;
BEGIN
  -- Count messages with sequence numbers
  SELECT COUNT(*) INTO trip_seq_count 
  FROM trip_messages WHERE sequence_number IS NOT NULL;
  
  SELECT COUNT(*) INTO dm_seq_count 
  FROM direct_messages WHERE sequence_number IS NOT NULL;
  
  -- Count any remaining nulls (should be 0)
  SELECT COUNT(*) INTO trip_null_count 
  FROM trip_messages WHERE sequence_number IS NULL;
  
  SELECT COUNT(*) INTO dm_null_count 
  FROM direct_messages WHERE sequence_number IS NULL;
  
  -- Report results
  RAISE NOTICE '========================================';
  RAISE NOTICE 'MIGRATION VERIFICATION RESULTS:';
  RAISE NOTICE '========================================';
  RAISE NOTICE 'trip_messages with sequence_number: %', trip_seq_count;
  RAISE NOTICE 'trip_messages with NULL sequence: %', trip_null_count;
  RAISE NOTICE 'direct_messages with sequence_number: %', dm_seq_count;
  RAISE NOTICE 'direct_messages with NULL sequence: %', dm_null_count;
  RAISE NOTICE '========================================';
  
  -- Fail if any nulls found
  IF trip_null_count > 0 OR dm_null_count > 0 THEN
    RAISE EXCEPTION 'Migration failed: Found NULL sequence_number values';
  END IF;
  
  RAISE NOTICE '✅ Migration completed successfully!';
END $$;

COMMIT;

-- ============================================================================
-- VERIFICATION QUERIES (Run these after migration)
-- ============================================================================

-- Check trip_messages schema
-- SELECT column_name, data_type, is_nullable 
-- FROM information_schema.columns 
-- WHERE table_name = 'trip_messages' 
-- ORDER BY ordinal_position;

-- Check direct_messages schema
-- SELECT column_name, data_type, is_nullable 
-- FROM information_schema.columns 
-- WHERE table_name = 'direct_messages' 
-- ORDER BY ordinal_position;

-- Verify sequence numbers are sequential
-- SELECT chat_id, COUNT(*) as msg_count, 
--        MIN(sequence_number) as min_seq, 
--        MAX(sequence_number) as max_seq
-- FROM trip_messages 
-- GROUP BY chat_id;

-- Check for gaps in sequence (should return 0 rows)
-- WITH sequences AS (
--   SELECT chat_id, sequence_number,
--          LAG(sequence_number) OVER (PARTITION BY chat_id ORDER BY sequence_number) as prev_seq
--   FROM trip_messages
-- )
-- SELECT * FROM sequences 
-- WHERE prev_seq IS NOT NULL AND sequence_number != prev_seq + 1;
