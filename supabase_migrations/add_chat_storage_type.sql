-- Add chat_storage_type column to tables
-- This allows us to gradually migrate to Telegram-style local-first chat
-- Old tables: 'database' (current Supabase-first approach)
-- New tables: 'telegram' (local SQLite-first approach)

ALTER TABLE public.tables 
ADD COLUMN IF NOT EXISTS chat_storage_type TEXT DEFAULT 'database';

-- Add index for quick lookups
CREATE INDEX IF NOT EXISTS idx_tables_chat_storage_type 
ON public.tables(chat_storage_type);

-- Comment for documentation
COMMENT ON COLUMN public.tables.chat_storage_type IS 
'Chat storage strategy: "database" for legacy Supabase-first, "telegram" for local SQLite-first';
