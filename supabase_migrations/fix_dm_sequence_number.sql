-- Add sequence_number column to direct_messages if it doesn't exist
ALTER TABLE direct_messages ADD COLUMN IF NOT EXISTS sequence_number BIGINT;

-- Sequence generator for direct messages (per chat)
-- Note: 'messages' table uses a trigger that calculates MAX(sequence_number) + 1 for a given table_id
-- We will implement the exact same pattern for direct_messages.

-- Create the trigger function
CREATE OR REPLACE FUNCTION set_direct_message_sequence_number()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.sequence_number IS NULL THEN
        SELECT COALESCE(MAX(sequence_number), 0) + 1
        INTO NEW.sequence_number
        FROM direct_messages
        WHERE chat_id = NEW.chat_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Drop the trigger if it exists to be safe
DROP TRIGGER IF EXISTS set_direct_message_sequence_number_trigger ON direct_messages;

-- Create the trigger
CREATE TRIGGER set_direct_message_sequence_number_trigger
    BEFORE INSERT ON direct_messages
    FOR EACH ROW
    EXECUTE FUNCTION set_direct_message_sequence_number();

-- Backfill existing direct_messages if they have a null sequence_number
WITH numbered_messages AS (
    SELECT 
        id,
        chat_id,
        ROW_NUMBER() OVER(PARTITION BY chat_id ORDER BY created_at ASC) as new_seq
    FROM direct_messages
    WHERE sequence_number IS NULL
)
UPDATE direct_messages dm
SET sequence_number = nm.new_seq
FROM numbered_messages nm
WHERE dm.id = nm.id;
