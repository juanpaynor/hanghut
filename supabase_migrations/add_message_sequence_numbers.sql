-- Chat Optimization: Add Sequence Numbers for Guaranteed Message Ordering
-- This migration adds server-assigned sequence numbers to ensure messages are always in correct order

-- 1. Add sequence_number column to messages table
ALTER TABLE messages 
ADD COLUMN IF NOT EXISTS sequence_number BIGINT;

-- 2. Backfill existing messages with sequence numbers (based on created_at)
-- This ensures existing messages have sequence numbers
DO $$
DECLARE
  table_record RECORD;
  seq_num BIGINT;
BEGIN
  -- For each table/chat
  FOR table_record IN 
    SELECT DISTINCT table_id FROM messages WHERE sequence_number IS NULL
  LOOP
    seq_num := 0;
    
    -- Assign sequence numbers to existing messages in order
    UPDATE messages
    SET sequence_number = subquery.new_seq
    FROM (
      SELECT id, ROW_NUMBER() OVER (ORDER BY timestamp ASC) as new_seq
      FROM messages
      WHERE table_id = table_record.table_id
        AND sequence_number IS NULL
    ) AS subquery
    WHERE messages.id = subquery.id;
  END LOOP;
END $$;

-- 3. Create function to auto-assign sequence numbers on insert
CREATE OR REPLACE FUNCTION assign_message_sequence()
RETURNS TRIGGER AS $$
BEGIN
  -- Get next sequence number for this table/chat
  SELECT COALESCE(MAX(sequence_number), 0) + 1
  INTO NEW.sequence_number
  FROM messages
  WHERE table_id = NEW.table_id;
  
  -- If still null (first message), set to 1
  IF NEW.sequence_number IS NULL THEN
    NEW.sequence_number := 1;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 4. Create trigger to call function before insert
DROP TRIGGER IF EXISTS messages_sequence_trigger ON messages;
CREATE TRIGGER messages_sequence_trigger
BEFORE INSERT ON messages
FOR EACH ROW
EXECUTE FUNCTION assign_message_sequence();

-- 5. Create index for fast ordering by sequence number
CREATE INDEX IF NOT EXISTS idx_messages_sequence 
ON messages(table_id, sequence_number DESC);

-- 6. Create index for gap detection queries
CREATE INDEX IF NOT EXISTS idx_messages_sequence_asc 
ON messages(table_id, sequence_number ASC);

-- 7. Add NOT NULL constraint after backfill
ALTER TABLE messages 
ALTER COLUMN sequence_number SET NOT NULL;

-- 8. Add comment for documentation
COMMENT ON COLUMN messages.sequence_number IS 'Server-assigned monotonically increasing sequence number for guaranteed message ordering. Never use client timestamps for ordering.';

-- 9. Create helper function to detect gaps in sequence
CREATE OR REPLACE FUNCTION detect_message_gaps(p_table_id UUID, p_start_seq BIGINT, p_end_seq BIGINT)
RETURNS TABLE(missing_sequence BIGINT) AS $$
BEGIN
  RETURN QUERY
  SELECT seq
  FROM generate_series(p_start_seq, p_end_seq) seq
  WHERE NOT EXISTS (
    SELECT 1 FROM messages
    WHERE table_id = p_table_id
      AND sequence_number = seq
  );
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION detect_message_gaps IS 'Detects missing sequence numbers in a range, useful for sync gap detection';
