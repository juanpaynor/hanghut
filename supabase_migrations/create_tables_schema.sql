-- Create tables schema for dining tables feature

-- Drop existing tables if they exist with wrong schema
DROP TABLE IF EXISTS public.messages CASCADE;
DROP TABLE IF EXISTS public.table_participants CASCADE;
DROP TABLE IF EXISTS public.tables CASCADE;

-- Tables table (main table for dining events)
CREATE TABLE public.tables (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  host_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  description TEXT,
  location_name TEXT NOT NULL,
  latitude DOUBLE PRECISION NOT NULL,
  longitude DOUBLE PRECISION NOT NULL,
  city TEXT,
  country TEXT,
  datetime TIMESTAMPTZ NOT NULL,
  max_guests INTEGER NOT NULL DEFAULT 4,
  cuisine_type TEXT,
  price_per_person NUMERIC(10, 2),
  dietary_restrictions TEXT[],
  marker_image_url TEXT,
  marker_emoji TEXT,
  status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'full', 'cancelled', 'completed')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Table participants (users who joined a table)
CREATE TABLE public.table_participants (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  table_id UUID NOT NULL REFERENCES public.tables(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'confirmed', 'declined', 'cancelled')),
  joined_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(table_id, user_id)
);

-- Messages table (for table group chats)
CREATE TABLE public.messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  table_id UUID NOT NULL REFERENCES public.tables(id) ON DELETE CASCADE,
  sender_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  content TEXT NOT NULL,
  timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Create indexes for better query performance
CREATE INDEX IF NOT EXISTS idx_tables_host_id ON public.tables(host_id);
CREATE INDEX IF NOT EXISTS idx_tables_datetime ON public.tables(datetime);
CREATE INDEX IF NOT EXISTS idx_tables_location ON public.tables(latitude, longitude);
CREATE INDEX IF NOT EXISTS idx_tables_status ON public.tables(status);
CREATE INDEX IF NOT EXISTS idx_table_participants_table_id ON public.table_participants(table_id);
CREATE INDEX IF NOT EXISTS idx_table_participants_user_id ON public.table_participants(user_id);
CREATE INDEX IF NOT EXISTS idx_messages_table_id ON public.messages(table_id);
CREATE INDEX IF NOT EXISTS idx_messages_timestamp ON public.messages(timestamp);

-- Enable Row Level Security
ALTER TABLE public.tables ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.table_participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;

-- RLS Policies for tables
DROP POLICY IF EXISTS "Anyone can view open tables" ON public.tables;
CREATE POLICY "Anyone can view open tables" ON public.tables
  FOR SELECT USING (true);

DROP POLICY IF EXISTS "Users can create their own tables" ON public.tables;
CREATE POLICY "Users can create their own tables" ON public.tables
  FOR INSERT WITH CHECK (auth.uid() = host_id);

DROP POLICY IF EXISTS "Hosts can update their own tables" ON public.tables;
CREATE POLICY "Hosts can update their own tables" ON public.tables
  FOR UPDATE USING (auth.uid() = host_id);

DROP POLICY IF EXISTS "Hosts can delete their own tables" ON public.tables;
CREATE POLICY "Hosts can delete their own tables" ON public.tables
  FOR DELETE USING (auth.uid() = host_id);

-- RLS Policies for table_participants
DROP POLICY IF EXISTS "Anyone can view participants" ON public.table_participants;
CREATE POLICY "Anyone can view participants" ON public.table_participants
  FOR SELECT USING (true);

DROP POLICY IF EXISTS "Users can join tables" ON public.table_participants;
CREATE POLICY "Users can join tables" ON public.table_participants
  FOR INSERT WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update their own participation" ON public.table_participants;
CREATE POLICY "Users can update their own participation" ON public.table_participants
  FOR UPDATE USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can leave tables" ON public.table_participants;
CREATE POLICY "Users can leave tables" ON public.table_participants
  FOR DELETE USING (auth.uid() = user_id);

-- RLS Policies for messages
DROP POLICY IF EXISTS "Participants can view messages" ON public.messages;
CREATE POLICY "Participants can view messages" ON public.messages
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.table_participants
      WHERE table_id = messages.table_id
      AND user_id = auth.uid()
    )
    OR
    EXISTS (
      SELECT 1 FROM public.tables
      WHERE id = messages.table_id
      AND host_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Participants can send messages" ON public.messages;
CREATE POLICY "Participants can send messages" ON public.messages
  FOR INSERT WITH CHECK (
    auth.uid() = sender_id
    AND (
      EXISTS (
        SELECT 1 FROM public.table_participants
        WHERE table_id = messages.table_id
        AND user_id = auth.uid()
      )
      OR
      EXISTS (
        SELECT 1 FROM public.tables
        WHERE id = messages.table_id
        AND host_id = auth.uid()
      )
    )
  );

DROP POLICY IF EXISTS "Users can delete their own messages" ON public.messages;
CREATE POLICY "Users can delete their own messages" ON public.messages
  FOR DELETE USING (auth.uid() = sender_id);

-- Function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger to automatically update updated_at
DROP TRIGGER IF EXISTS update_tables_updated_at ON public.tables;
CREATE TRIGGER update_tables_updated_at
  BEFORE UPDATE ON public.tables
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

-- Create map_ready_tables view for map display
DROP VIEW IF EXISTS public.map_ready_tables;
CREATE VIEW public.map_ready_tables AS
SELECT 
    t.id,
    t.title,
    t.description,
    t.location_name as venue_name,
    t.latitude as location_lat,
    t.longitude as location_lng,
    t.datetime as scheduled_time,
    t.max_guests as max_capacity,
    t.status,
    t.marker_image_url,
    t.marker_emoji,
    t.cuisine_type,
    t.price_per_person,
    t.dietary_restrictions,
    
    -- Host info
    t.host_id,
    u.display_name as host_name,
    up.photo_url as host_photo_url,
    COALESCE(u.trust_score, 0) as host_trust_score,
    
    -- Capacity info
    COUNT(tp.id) FILTER (WHERE tp.status IN ('confirmed', 'pending')) as member_count,
    (t.max_guests - COUNT(tp.id) FILTER (WHERE tp.status = 'confirmed')) as seats_left,
    CASE 
        WHEN COUNT(tp.id) FILTER (WHERE tp.status = 'confirmed') >= t.max_guests THEN 'full'
        WHEN COUNT(tp.id) FILTER (WHERE tp.status = 'confirmed') >= (t.max_guests * 0.8) THEN 'filling_up'
        ELSE 'available'
    END as availability_state
    
FROM public.tables t
LEFT JOIN public.users u ON t.host_id = u.id
LEFT JOIN public.user_photos up ON u.id = up.user_id AND up.is_primary = true
LEFT JOIN public.table_participants tp ON t.id = tp.table_id
WHERE t.status = 'open'
  AND t.datetime > NOW()
GROUP BY t.id, u.display_name, up.photo_url, u.trust_score;
