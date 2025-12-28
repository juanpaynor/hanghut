-- Create user_trips table for future trip planning
CREATE TABLE IF NOT EXISTS user_trips (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    destination_city TEXT NOT NULL,
    destination_country TEXT NOT NULL,
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    travel_style TEXT, -- 'budget', 'moderate', 'luxury'
    interests TEXT[], -- ['food', 'nightlife', 'culture', 'adventure', 'relaxation']
    goals TEXT[], -- ['make_friends', 'find_companion', 'local_tips', 'group_activities']
    description TEXT,
    status TEXT DEFAULT 'upcoming', -- 'upcoming', 'active', 'completed', 'cancelled'
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    -- Constraints
    CONSTRAINT valid_dates CHECK (end_date >= start_date),
    CONSTRAINT valid_status CHECK (status IN ('upcoming', 'active', 'completed', 'cancelled'))
);

-- Create trip_participants junction table (for group trips)
CREATE TABLE IF NOT EXISTS trip_participants (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    trip_id UUID NOT NULL REFERENCES user_trips(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    joined_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    role TEXT DEFAULT 'member', -- 'creator', 'member'
    
    UNIQUE(trip_id, user_id)
);

-- Create trip_group_chats table
CREATE TABLE IF NOT EXISTS trip_group_chats (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    destination_city TEXT NOT NULL,
    destination_country TEXT NOT NULL,
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    ably_channel_id TEXT UNIQUE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    -- Unique constraint to prevent duplicate chats for same destination/dates
    UNIQUE(destination_city, destination_country, start_date, end_date)
);

-- Create trip_chat_participants junction table
CREATE TABLE IF NOT EXISTS trip_chat_participants (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    chat_id UUID NOT NULL REFERENCES trip_group_chats(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    joined_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    last_read_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    UNIQUE(chat_id, user_id)
);

-- Create trip_messages table (similar to table messages but for trip chats)
CREATE TABLE IF NOT EXISTS trip_messages (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    chat_id UUID NOT NULL REFERENCES trip_group_chats(id) ON DELETE CASCADE,
    sender_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    content TEXT NOT NULL,
    message_type TEXT DEFAULT 'text', -- 'text', 'system', 'image'
    sent_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_user_trips_user_id ON user_trips(user_id);
CREATE INDEX IF NOT EXISTS idx_user_trips_dates ON user_trips(start_date, end_date);
CREATE INDEX IF NOT EXISTS idx_user_trips_destination ON user_trips(destination_city, destination_country);
CREATE INDEX IF NOT EXISTS idx_user_trips_status ON user_trips(status);

CREATE INDEX IF NOT EXISTS idx_trip_participants_trip_id ON trip_participants(trip_id);
CREATE INDEX IF NOT EXISTS idx_trip_participants_user_id ON trip_participants(user_id);

CREATE INDEX IF NOT EXISTS idx_trip_chat_participants_chat_id ON trip_chat_participants(chat_id);
CREATE INDEX IF NOT EXISTS idx_trip_chat_participants_user_id ON trip_chat_participants(user_id);

CREATE INDEX IF NOT EXISTS idx_trip_messages_chat_id ON trip_messages(chat_id);
CREATE INDEX IF NOT EXISTS idx_trip_messages_sent_at ON trip_messages(sent_at);

-- Enable Row Level Security
ALTER TABLE user_trips ENABLE ROW LEVEL SECURITY;
ALTER TABLE trip_participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE trip_group_chats ENABLE ROW LEVEL SECURITY;
ALTER TABLE trip_chat_participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE trip_messages ENABLE ROW LEVEL SECURITY;

-- RLS Policies for user_trips
DROP POLICY IF EXISTS "Users can view all trips" ON user_trips;
CREATE POLICY "Users can view all trips" ON user_trips
    FOR SELECT USING (true);

DROP POLICY IF EXISTS "Users can create their own trips" ON user_trips;
CREATE POLICY "Users can create their own trips" ON user_trips
    FOR INSERT WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update their own trips" ON user_trips;
CREATE POLICY "Users can update their own trips" ON user_trips
    FOR UPDATE USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can delete their own trips" ON user_trips;
CREATE POLICY "Users can delete their own trips" ON user_trips
    FOR DELETE USING (auth.uid() = user_id);

-- RLS Policies for trip_participants
DROP POLICY IF EXISTS "Anyone can view trip participants" ON trip_participants;
CREATE POLICY "Anyone can view trip participants" ON trip_participants
    FOR SELECT USING (true);

DROP POLICY IF EXISTS "Trip creators can add participants" ON trip_participants;
CREATE POLICY "Trip creators can add participants" ON trip_participants
    FOR INSERT WITH CHECK (
        EXISTS (
            SELECT 1 FROM user_trips 
            WHERE id = trip_id AND user_id = auth.uid()
        )
    );

DROP POLICY IF EXISTS "Users can leave trips" ON trip_participants;
CREATE POLICY "Users can leave trips" ON trip_participants
    FOR DELETE USING (auth.uid() = user_id);

-- RLS Policies for trip_group_chats
DROP POLICY IF EXISTS "Anyone can view trip chats" ON trip_group_chats;
CREATE POLICY "Anyone can view trip chats" ON trip_group_chats
    FOR SELECT USING (true);

DROP POLICY IF EXISTS "Authenticated users can create trip chats" ON trip_group_chats;
CREATE POLICY "Authenticated users can create trip chats" ON trip_group_chats
    FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);

-- RLS Policies for trip_chat_participants
DROP POLICY IF EXISTS "Anyone can view chat participants" ON trip_chat_participants;
CREATE POLICY "Anyone can view chat participants" ON trip_chat_participants
    FOR SELECT USING (true);

DROP POLICY IF EXISTS "Users can join trip chats" ON trip_chat_participants;
CREATE POLICY "Users can join trip chats" ON trip_chat_participants
    FOR INSERT WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can leave trip chats" ON trip_chat_participants;
CREATE POLICY "Users can leave trip chats" ON trip_chat_participants
    FOR DELETE USING (auth.uid() = user_id);

-- RLS Policies for trip_messages
DROP POLICY IF EXISTS "Chat participants can view messages" ON trip_messages;
CREATE POLICY "Chat participants can view messages" ON trip_messages
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM trip_chat_participants
            WHERE chat_id = trip_messages.chat_id AND user_id = auth.uid()
        )
    );

DROP POLICY IF EXISTS "Chat participants can send messages" ON trip_messages;
CREATE POLICY "Chat participants can send messages" ON trip_messages
    FOR INSERT WITH CHECK (
        auth.uid() = sender_id AND
        EXISTS (
            SELECT 1 FROM trip_chat_participants
            WHERE chat_id = trip_messages.chat_id AND user_id = auth.uid()
        )
    );

-- Function to automatically create trip participant when trip is created
CREATE OR REPLACE FUNCTION create_trip_creator_participant()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO trip_participants (trip_id, user_id, role)
    VALUES (NEW.id, NEW.user_id, 'creator');
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS on_trip_created ON user_trips;
CREATE TRIGGER on_trip_created
    AFTER INSERT ON user_trips
    FOR EACH ROW
    EXECUTE FUNCTION create_trip_creator_participant();

-- Function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS update_user_trips_updated_at ON user_trips;
CREATE TRIGGER update_user_trips_updated_at
    BEFORE UPDATE ON user_trips
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- View to get trip matches (users with overlapping trips to same destination)
CREATE OR REPLACE VIEW trip_matches AS
SELECT DISTINCT
    t1.id AS trip_id,
    t1.user_id AS user_id,
    t2.user_id AS matched_user_id,
    t2.id AS matched_trip_id,
    t1.destination_city,
    t1.destination_country,
    GREATEST(t1.start_date, t2.start_date) AS overlap_start,
    LEAST(t1.end_date, t2.end_date) AS overlap_end,
    LEAST(t1.end_date, t2.end_date) - GREATEST(t1.start_date, t2.start_date) + 1 AS overlap_days
FROM user_trips t1
JOIN user_trips t2 ON 
    t1.destination_city = t2.destination_city AND
    t1.destination_country = t2.destination_country AND
    t1.id != t2.id AND
    t1.user_id != t2.user_id AND
    t1.status = 'upcoming' AND
    t2.status = 'upcoming' AND
    -- Date ranges overlap
    t1.start_date <= t2.end_date AND
    t1.end_date >= t2.start_date;

COMMENT ON TABLE user_trips IS 'Stores user future trip plans for matching with other travelers';
COMMENT ON TABLE trip_participants IS 'Junction table for group trip participants';
COMMENT ON TABLE trip_group_chats IS 'Group chats for travelers going to same destination';
COMMENT ON TABLE trip_chat_participants IS 'Participants in trip group chats';
COMMENT ON TABLE trip_messages IS 'Messages in trip group chats';
COMMENT ON VIEW trip_matches IS 'Returns users with overlapping trips to the same destination';
