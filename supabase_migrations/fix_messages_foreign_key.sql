-- FIX: Messages table relationship with users
-- The error "Could not find a relationship between 'messages' and 'users'" happens because
-- messages.sender_id references auth.users (private), but the client tries to join public.users.

BEGIN;

DO $$
DECLARE
    constraint_name_var text;
BEGIN
    -- 1. Find the existing FK constraint on sender_id
    SELECT conname INTO constraint_name_var
    FROM pg_constraint
    WHERE conrelid = 'public.messages'::regclass
      AND confrelid = 'auth.users'::regclass
      AND array_to_string(conkey, ',') = (
          SELECT attnum::text 
          FROM pg_attribute 
          WHERE attrelid = 'public.messages'::regclass 
          AND attname = 'sender_id'
      );

    -- 2. Drop it if found
    IF constraint_name_var IS NOT NULL THEN
        EXECUTE 'ALTER TABLE public.messages DROP CONSTRAINT ' || quote_ident(constraint_name_var);
        RAISE NOTICE 'Dropped existing FK constraint: %', constraint_name_var;
    END IF;

    -- 3. Also check for standard naming just in case
    IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'messages_sender_id_fkey') THEN
        ALTER TABLE public.messages DROP CONSTRAINT messages_sender_id_fkey;
    END IF;

    -- 4. Add the correct FK to public.users
    ALTER TABLE public.messages
    ADD CONSTRAINT messages_sender_id_fkey
    FOREIGN KEY (sender_id)
    REFERENCES public.users(id)
    ON DELETE CASCADE;

    RAISE NOTICE 'Added new FK constraint messages_sender_id_fkey referencing public.users';

END $$;

COMMIT;

-- Verify
-- SELECT 
--     tc.constraint_name, 
--     tc.table_name, 
--     kcu.column_name, 
--     ccu.table_name AS foreign_table_name,
--     ccu.column_name AS foreign_column_name 
-- FROM 
--     information_schema.table_constraints AS tc 
--     JOIN information_schema.key_column_usage AS kcu
--       ON tc.constraint_name = kcu.constraint_name
--       AND tc.table_schema = kcu.table_schema
--     JOIN information_schema.constraint_column_usage AS ccu
--       ON ccu.constraint_name = tc.constraint_name
--       AND ccu.table_schema = tc.table_schema
-- WHERE tc.constraint_type = 'FOREIGN KEY' AND tc.table_name='messages';
