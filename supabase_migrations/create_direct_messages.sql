-- Create direct chats table
CREATE TABLE IF NOT EXISTS direct_chats (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create direct chat participants table
CREATE TABLE IF NOT EXISTS direct_chat_participants (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    chat_id UUID NOT NULL REFERENCES direct_chats(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    joined_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    last_read_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    UNIQUE(chat_id, user_id)
);

-- Create direct messages table
CREATE TABLE IF NOT EXISTS direct_messages (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    chat_id UUID NOT NULL REFERENCES direct_chats(id) ON DELETE CASCADE,
    sender_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    content TEXT NOT NULL,
    message_type TEXT DEFAULT 'text', -- 'text', 'image', 'gif'
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    read_at TIMESTAMP WITH TIME ZONE
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_direct_chat_participants_user_id ON direct_chat_participants(user_id);
CREATE INDEX IF NOT EXISTS idx_direct_chat_participants_chat_id ON direct_chat_participants(chat_id);
CREATE INDEX IF NOT EXISTS idx_direct_messages_chat_id ON direct_messages(chat_id);
CREATE INDEX IF NOT EXISTS idx_direct_messages_sender_id ON direct_messages(sender_id);

-- RLS Policies
ALTER TABLE direct_chats ENABLE ROW LEVEL SECURITY;
ALTER TABLE direct_chat_participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE direct_messages ENABLE ROW LEVEL SECURITY;

-- Chats: Participants can view/insert
CREATE POLICY "Participants can view chats" ON direct_chats
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM direct_chat_participants
            WHERE chat_id = id AND user_id = auth.uid()
        )
    );

CREATE POLICY "Participants can update chats" ON direct_chats
    FOR UPDATE USING (
        EXISTS (
            SELECT 1 FROM direct_chat_participants
            WHERE chat_id = id AND user_id = auth.uid()
        )
    );

-- Participants: View own chats and who is in them
CREATE POLICY "View chat participants" ON direct_chat_participants
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM direct_chat_participants p
            WHERE p.chat_id = chat_id AND p.user_id = auth.uid()
        )
    );

-- Messages: Participants can view/send
CREATE POLICY "View messages" ON direct_messages
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM direct_chat_participants
            WHERE chat_id = direct_messages.chat_id AND user_id = auth.uid()
        )
    );

CREATE POLICY "Send messages" ON direct_messages
    FOR INSERT WITH CHECK (
        auth.uid() = sender_id AND
        EXISTS (
            SELECT 1 FROM direct_chat_participants
            WHERE chat_id = direct_messages.chat_id AND user_id = auth.uid()
        )
    );

-- Function to get or create DM chat between two users
CREATE OR REPLACE FUNCTION get_or_create_dm_chat(target_user_id UUID)
RETURNS UUID AS $$
DECLARE
    existing_chat_id UUID;
    new_chat_id UUID;
    current_user_id UUID;
BEGIN
    current_user_id := auth.uid();
    
    -- Check for existing chat with exactly these 2 participants
    SELECT c.id INTO existing_chat_id
    FROM direct_chats c
    JOIN direct_chat_participants p1 ON c.id = p1.chat_id
    JOIN direct_chat_participants p2 ON c.id = p2.chat_id
    WHERE p1.user_id = current_user_id 
    AND p2.user_id = target_user_id
    GROUP BY c.id
    HAVING COUNT(DISTINCT p1.user_id) = 2; -- Ensure only 2 participants (1-on-1)

    IF existing_chat_id IS NOT NULL THEN
        RETURN existing_chat_id;
    END IF;

    -- Create new chat
    INSERT INTO direct_chats DEFAULT VALUES RETURNING id INTO new_chat_id;

    -- Add participants
    INSERT INTO direct_chat_participants (chat_id, user_id)
    VALUES 
        (new_chat_id, current_user_id),
        (new_chat_id, target_user_id);

    RETURN new_chat_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
