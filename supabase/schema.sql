-- BiteMates Database Schema for Supabase
-- Migration from Nhost to Supabase
-- Note: RLS (Row Level Security) policies NOT included as per request

-- Enable Required Extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- Create Custom Types (Enums)
CREATE TYPE auth_provider_type AS ENUM ('email', 'google', 'apple');
CREATE TYPE user_status_type AS ENUM ('active', 'suspended', 'banned');
CREATE TYPE goal_type AS ENUM ('friends', 'romance', 'casual');
CREATE TYPE meetup_mode_type AS ENUM ('matched', 'create_own', 'both');
CREATE TYPE gender_preference_type AS ENUM ('women_only', 'men_only', 'mix_preferred', 'no_preference');
CREATE TYPE activity_type AS ENUM ('dinner', 'drinks', 'coffee', 'brunch', 'activity', 'other');
CREATE TYPE table_mode_type AS ENUM ('matched', 'public', 'private');
CREATE TYPE gender_filter_type AS ENUM ('women_only', 'men_only', 'mix', 'none');
CREATE TYPE table_status_type AS ENUM ('draft', 'open', 'full', 'in_progress', 'completed', 'cancelled');
CREATE TYPE member_role_type AS ENUM ('host', 'member');
CREATE TYPE member_status_type AS ENUM ('pending', 'approved', 'joined', 'declined', 'left', 'no_show', 'attended');
CREATE TYPE timeframe_preference_type AS ENUM ('today', 'tomorrow', 'this_week', 'weekend', 'custom');
CREATE TYPE queue_status_type AS ENUM ('pending', 'matched', 'expired');
CREATE TYPE message_type AS ENUM ('text', 'image', 'system');
CREATE TYPE trip_purpose_type AS ENUM ('vacation', 'work', 'moving', 'visiting', 'other');
CREATE TYPE travel_status_type AS ENUM ('planning', 'confirmed', 'in_progress', 'completed');
CREATE TYPE travel_match_status_type AS ENUM ('active', 'archived');
CREATE TYPE report_reason_type AS ENUM ('harassment', 'fake_profile', 'no_show', 'inappropriate', 'other');
CREATE TYPE report_status_type AS ENUM ('pending', 'reviewed', 'actioned', 'dismissed');
CREATE TYPE interest_category_type AS ENUM ('food', 'activities', 'hobbies', 'music', 'sports', 'arts', 'tech', 'travel', 'other');

-- ==============================================
-- CORE USER TABLES
-- ==============================================

-- Users Table
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email TEXT UNIQUE NOT NULL,
    auth_provider auth_provider_type NOT NULL DEFAULT 'email',
    display_name TEXT NOT NULL,
    bio TEXT,
    date_of_birth DATE,
    gender_identity TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_active_at TIMESTAMPTZ,
    home_location_lat DOUBLE PRECISION,
    home_location_lng DOUBLE PRECISION,
    is_verified_email BOOLEAN NOT NULL DEFAULT FALSE,
    is_verified_phone BOOLEAN NOT NULL DEFAULT FALSE,
    is_verified_photo BOOLEAN NOT NULL DEFAULT FALSE,
    trust_score INTEGER NOT NULL DEFAULT 50 CHECK (trust_score >= 0 AND trust_score <= 100),
    total_meetups_attended INTEGER NOT NULL DEFAULT 0,
    total_no_shows INTEGER NOT NULL DEFAULT 0,
    status user_status_type NOT NULL DEFAULT 'active'
);

CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_status ON users(status);
CREATE INDEX idx_users_created_at ON users(created_at);
CREATE INDEX idx_users_location ON users(home_location_lat, home_location_lng);

-- Trigger to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_users_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- User Personality Table (Big 5 traits)
CREATE TABLE user_personality (
    user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    openness INTEGER NOT NULL CHECK (openness >= 1 AND openness <= 5),
    conscientiousness INTEGER NOT NULL CHECK (conscientiousness >= 1 AND conscientiousness <= 5),
    extraversion INTEGER NOT NULL CHECK (extraversion >= 1 AND extraversion <= 5),
    agreeableness INTEGER NOT NULL CHECK (agreeableness >= 1 AND agreeableness <= 5),
    neuroticism INTEGER NOT NULL CHECK (neuroticism >= 1 AND neuroticism <= 5),
    completed_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- User Preferences Table
CREATE TABLE user_preferences (
    user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    budget_min INTEGER NOT NULL CHECK (budget_min >= 0),
    budget_max INTEGER NOT NULL CHECK (budget_max >= budget_min),
    primary_goal goal_type NOT NULL DEFAULT 'friends',
    open_to_all_goals BOOLEAN NOT NULL DEFAULT FALSE,
    preferred_meetup_mode meetup_mode_type NOT NULL DEFAULT 'both',
    gender_preference gender_preference_type NOT NULL DEFAULT 'no_preference',
    preferred_group_size_min INTEGER NOT NULL DEFAULT 3 CHECK (preferred_group_size_min >= 2),
    preferred_group_size_max INTEGER NOT NULL DEFAULT 6 CHECK (preferred_group_size_max >= preferred_group_size_min)
);

-- User Photos Table
CREATE TABLE user_photos (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    photo_url TEXT NOT NULL,
    is_primary BOOLEAN NOT NULL DEFAULT FALSE,
    is_face_verified BOOLEAN NOT NULL DEFAULT FALSE,
    display_order INTEGER NOT NULL DEFAULT 0,
    uploaded_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_user_photos_user_id ON user_photos(user_id);
CREATE INDEX idx_user_photos_is_primary ON user_photos(is_primary);

-- Ensure only one primary photo per user
CREATE UNIQUE INDEX idx_user_photos_one_primary 
    ON user_photos(user_id) 
    WHERE is_primary = TRUE;

-- ==============================================
-- INTERESTS SYSTEM
-- ==============================================

-- Interest Tags Table
CREATE TABLE interest_tags (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT UNIQUE NOT NULL,
    category interest_category_type NOT NULL DEFAULT 'other',
    icon TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_interest_tags_category ON interest_tags(category);
CREATE INDEX idx_interest_tags_name ON interest_tags(name);

-- User Interests Junction Table
CREATE TABLE user_interests (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    interest_tag_id UUID NOT NULL REFERENCES interest_tags(id) ON DELETE CASCADE,
    added_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(user_id, interest_tag_id)
);

CREATE INDEX idx_user_interests_user_id ON user_interests(user_id);
CREATE INDEX idx_user_interests_tag_id ON user_interests(interest_tag_id);

-- ==============================================
-- TABLES (MEETUPS) SYSTEM
-- ==============================================

-- Tables (Dining Events/Meetups)
CREATE TABLE tables (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    host_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    description TEXT,
    activity_type activity_type NOT NULL DEFAULT 'dinner',
    venue_name TEXT NOT NULL,
    venue_address TEXT NOT NULL,
    location_lat DOUBLE PRECISION NOT NULL,
    location_lng DOUBLE PRECISION NOT NULL,
    scheduled_at TIMESTAMPTZ NOT NULL,
    duration_minutes INTEGER NOT NULL DEFAULT 120,
    budget_min_per_person INTEGER NOT NULL CHECK (budget_min_per_person >= 0),
    budget_max_per_person INTEGER NOT NULL CHECK (budget_max_per_person >= budget_min_per_person),
    max_capacity INTEGER NOT NULL CHECK (max_capacity >= 2 AND max_capacity <= 20),
    current_capacity INTEGER NOT NULL DEFAULT 0 CHECK (current_capacity >= 0),
    table_mode table_mode_type NOT NULL DEFAULT 'public',
    goal_type goal_type NOT NULL DEFAULT 'friends',
    gender_filter gender_filter_type NOT NULL DEFAULT 'none',
    requires_approval BOOLEAN NOT NULL DEFAULT TRUE,
    status table_status_type NOT NULL DEFAULT 'draft',
    ably_channel_id TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_tables_host_user_id ON tables(host_user_id);
CREATE INDEX idx_tables_location ON tables(location_lat, location_lng);
CREATE INDEX idx_tables_scheduled_at ON tables(scheduled_at);
CREATE INDEX idx_tables_status ON tables(status);
CREATE INDEX idx_tables_goal_type ON tables(goal_type);
CREATE INDEX idx_tables_activity_type ON tables(activity_type);
CREATE INDEX idx_tables_created_at ON tables(created_at);

-- Trigger to auto-generate Ably channel ID
CREATE OR REPLACE FUNCTION generate_table_channel_id()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.ably_channel_id IS NULL THEN
        NEW.ably_channel_id := 'table:' || NEW.id::text || ':chat';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_generate_table_channel
    BEFORE INSERT ON tables
    FOR EACH ROW
    EXECUTE FUNCTION generate_table_channel_id();

CREATE TRIGGER trigger_tables_updated_at
    BEFORE UPDATE ON tables
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Table Members Junction Table
CREATE TABLE table_members (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    table_id UUID NOT NULL REFERENCES tables(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role member_role_type NOT NULL DEFAULT 'member',
    status member_status_type NOT NULL DEFAULT 'pending',
    requested_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    approved_at TIMESTAMPTZ,
    joined_at TIMESTAMPTZ,
    left_at TIMESTAMPTZ,
    UNIQUE(table_id, user_id)
);

CREATE INDEX idx_table_members_table_id ON table_members(table_id);
CREATE INDEX idx_table_members_user_id ON table_members(user_id);
CREATE INDEX idx_table_members_status ON table_members(status);

-- Trigger to update table capacity and status
CREATE OR REPLACE FUNCTION update_table_capacity()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE tables
    SET current_capacity = (
        SELECT COUNT(*)
        FROM table_members
        WHERE table_id = COALESCE(NEW.table_id, OLD.table_id)
        AND status IN ('approved', 'joined', 'attended')
    )
    WHERE id = COALESCE(NEW.table_id, OLD.table_id);
    
    -- Mark table as full if capacity reached
    UPDATE tables
    SET status = 'full'
    WHERE id = COALESCE(NEW.table_id, OLD.table_id)
    AND current_capacity >= max_capacity
    AND status = 'open';
    
    -- Reopen table if space becomes available
    UPDATE tables
    SET status = 'open'
    WHERE id = COALESCE(NEW.table_id, OLD.table_id)
    AND current_capacity < max_capacity
    AND status = 'full';
    
    RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_table_capacity
    AFTER INSERT OR UPDATE OR DELETE ON table_members
    FOR EACH ROW
    EXECUTE FUNCTION update_table_capacity();

-- ==============================================
-- MATCHING SYSTEM
-- ==============================================

-- Matching Queue for automated matching
CREATE TABLE matching_queue (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    timeframe_preference timeframe_preference_type NOT NULL DEFAULT 'today',
    custom_date TIMESTAMPTZ,
    requested_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    status queue_status_type NOT NULL DEFAULT 'pending',
    matched_table_id UUID REFERENCES tables(id) ON DELETE SET NULL,
    matched_at TIMESTAMPTZ
);

CREATE INDEX idx_matching_queue_user_id ON matching_queue(user_id);
CREATE INDEX idx_matching_queue_status ON matching_queue(status);
CREATE INDEX idx_matching_queue_requested_at ON matching_queue(requested_at);
CREATE INDEX idx_matching_queue_timeframe ON matching_queue(timeframe_preference);

-- ==============================================
-- CHAT & MESSAGING SYSTEM
-- ==============================================

-- Messages Table
CREATE TABLE messages (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    table_id UUID NOT NULL REFERENCES tables(id) ON DELETE CASCADE,
    sender_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    content TEXT NOT NULL,
    message_type message_type NOT NULL DEFAULT 'text',
    sent_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    ably_message_id TEXT UNIQUE
);

CREATE INDEX idx_messages_table_id ON messages(table_id);
CREATE INDEX idx_messages_sender_id ON messages(sender_id);
CREATE INDEX idx_messages_sent_at ON messages(sent_at);
CREATE INDEX idx_messages_ably_id ON messages(ably_message_id);

-- Message Read Receipts
CREATE TABLE message_reads (
    message_id UUID NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    read_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (message_id, user_id)
);

CREATE INDEX idx_message_reads_user_id ON message_reads(user_id);
CREATE INDEX idx_message_reads_read_at ON message_reads(read_at);

-- ==============================================
-- RATINGS & REVIEWS SYSTEM
-- ==============================================

-- Ratings Table
CREATE TABLE ratings (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    table_id UUID NOT NULL REFERENCES tables(id) ON DELETE CASCADE,
    rater_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    rated_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    overall_score INTEGER NOT NULL CHECK (overall_score >= 1 AND overall_score <= 5),
    friendliness_score INTEGER NOT NULL CHECK (friendliness_score >= 1 AND friendliness_score <= 5),
    punctuality_score INTEGER NOT NULL CHECK (punctuality_score >= 1 AND punctuality_score <= 5),
    engagement_score INTEGER NOT NULL CHECK (engagement_score >= 1 AND engagement_score <= 5),
    review_text TEXT,
    is_no_show BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(table_id, rater_user_id, rated_user_id),
    CHECK (rater_user_id != rated_user_id)
);

CREATE INDEX idx_ratings_table_id ON ratings(table_id);
CREATE INDEX idx_ratings_rated_user_id ON ratings(rated_user_id);
CREATE INDEX idx_ratings_is_no_show ON ratings(is_no_show);
CREATE INDEX idx_ratings_created_at ON ratings(created_at);

-- Trigger to update user trust score based on ratings
CREATE OR REPLACE FUNCTION update_user_trust_score()
RETURNS TRIGGER AS $$
DECLARE
    avg_score NUMERIC;
    total_ratings INTEGER;
    no_show_count INTEGER;
BEGIN
    SELECT 
        AVG(overall_score),
        COUNT(*),
        SUM(CASE WHEN is_no_show THEN 1 ELSE 0 END)
    INTO avg_score, total_ratings, no_show_count
    FROM ratings
    WHERE rated_user_id = NEW.rated_user_id;
    
    UPDATE users
    SET 
        trust_score = GREATEST(0, LEAST(100, 
            (avg_score * 20) - (no_show_count * 5)
        )),
        total_no_shows = no_show_count
    WHERE id = NEW.rated_user_id;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_trust_score
    AFTER INSERT OR UPDATE ON ratings
    FOR EACH ROW
    EXECUTE FUNCTION update_user_trust_score();

-- ==============================================
-- TRAVEL SYSTEM
-- ==============================================

-- Travel Plans Table
CREATE TABLE travel_plans (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    destination_city TEXT NOT NULL,
    destination_country TEXT NOT NULL,
    destination_lat DOUBLE PRECISION NOT NULL,
    destination_lng DOUBLE PRECISION NOT NULL,
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    trip_purpose trip_purpose_type NOT NULL DEFAULT 'vacation',
    status travel_status_type NOT NULL DEFAULT 'planning',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CHECK (end_date >= start_date)
);

CREATE INDEX idx_travel_plans_user_id ON travel_plans(user_id);
CREATE INDEX idx_travel_plans_location ON travel_plans(destination_lat, destination_lng);
CREATE INDEX idx_travel_plans_start_date ON travel_plans(start_date);
CREATE INDEX idx_travel_plans_end_date ON travel_plans(end_date);
CREATE INDEX idx_travel_plans_status ON travel_plans(status);

-- Travel Matches Table
CREATE TABLE travel_matches (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    travel_plan_id_1 UUID NOT NULL REFERENCES travel_plans(id) ON DELETE CASCADE,
    travel_plan_id_2 UUID NOT NULL REFERENCES travel_plans(id) ON DELETE CASCADE,
    match_score INTEGER NOT NULL CHECK (match_score >= 0 AND match_score <= 100),
    ably_channel_id TEXT,
    matched_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    status travel_match_status_type NOT NULL DEFAULT 'active',
    CHECK (travel_plan_id_1 < travel_plan_id_2),
    UNIQUE(travel_plan_id_1, travel_plan_id_2)
);

CREATE INDEX idx_travel_matches_plan_1 ON travel_matches(travel_plan_id_1);
CREATE INDEX idx_travel_matches_plan_2 ON travel_matches(travel_plan_id_2);
CREATE INDEX idx_travel_matches_status ON travel_matches(status);

-- Trigger to generate travel match channel ID
CREATE OR REPLACE FUNCTION generate_travel_match_channel()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.ably_channel_id IS NULL THEN
        NEW.ably_channel_id := 'travel:' || NEW.id::text || ':chat';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_generate_travel_channel
    BEFORE INSERT ON travel_matches
    FOR EACH ROW
    EXECUTE FUNCTION generate_travel_match_channel();

-- ==============================================
-- SAFETY & MODERATION SYSTEM
-- ==============================================

-- User Blocks Table
CREATE TABLE blocks (
    blocker_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    blocked_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    blocked_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (blocker_user_id, blocked_user_id),
    CHECK (blocker_user_id != blocked_user_id)
);

CREATE INDEX idx_blocks_blocker ON blocks(blocker_user_id);
CREATE INDEX idx_blocks_blocked ON blocks(blocked_user_id);

-- Reports Table
CREATE TABLE reports (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    reporter_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    reported_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    table_id UUID REFERENCES tables(id) ON DELETE SET NULL,
    reason report_reason_type NOT NULL,
    description TEXT,
    status report_status_type NOT NULL DEFAULT 'pending',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    reviewed_at TIMESTAMPTZ,
    reviewer_notes TEXT,
    CHECK (reporter_user_id != reported_user_id)
);

CREATE INDEX idx_reports_reporter ON reports(reporter_user_id);
CREATE INDEX idx_reports_reported ON reports(reported_user_id);
CREATE INDEX idx_reports_table_id ON reports(table_id);
CREATE INDEX idx_reports_status ON reports(status);
CREATE INDEX idx_reports_created_at ON reports(created_at);

-- ==============================================
-- USEFUL VIEWS
-- ==============================================

-- Active Tables View (for map display)
CREATE VIEW active_tables_view AS
SELECT 
    t.*,
    COUNT(tm.id) FILTER (WHERE tm.status IN ('approved', 'joined', 'attended')) as member_count,
    u.display_name as host_name,
    u.trust_score as host_trust_score
FROM tables t
LEFT JOIN table_members tm ON t.id = tm.table_id
LEFT JOIN users u ON t.host_user_id = u.id
WHERE t.status IN ('open', 'full')
GROUP BY t.id, u.display_name, u.trust_score;

-- Map Ready Tables View (with host personality for matching)
CREATE VIEW map_ready_tables AS
SELECT 
    t.id,
    t.title,
    t.description,
    t.activity_type,
    t.venue_name,
    t.venue_address,
    t.location_lat,
    t.location_lng,
    t.scheduled_at,
    t.duration_minutes,
    t.budget_min_per_person,
    t.budget_max_per_person,
    t.max_capacity,
    t.current_capacity,
    t.status,
    t.goal_type,
    t.gender_filter,
    t.requires_approval,
    t.ably_channel_id,
    
    -- Host info
    t.host_user_id as host_id,
    u.display_name as host_name,
    u.bio as host_bio,
    u.trust_score as host_trust_score,
    
    -- Host personality traits (for matching algorithm)
    up.openness,
    up.conscientiousness,
    up.extraversion,
    up.agreeableness,
    up.neuroticism,
    
    -- Capacity info
    COUNT(tm.id) FILTER (WHERE tm.status IN ('approved', 'joined', 'attended')) as member_count,
    COUNT(tm.id) FILTER (WHERE tm.status = 'approved') as approved_count,
    COUNT(tm.id) FILTER (WHERE tm.status = 'pending') as pending_count,
    (t.max_capacity - t.current_capacity) as seats_left,
    CASE 
        WHEN t.current_capacity >= t.max_capacity THEN 'full'
        WHEN t.current_capacity >= (t.max_capacity * 0.8) THEN 'filling_up'
        ELSE 'available'
    END as availability_state
    
FROM tables t
LEFT JOIN users u ON t.host_user_id = u.id
LEFT JOIN user_personality up ON u.id = up.user_id
LEFT JOIN table_members tm ON t.id = tm.table_id
WHERE t.status IN ('open', 'full')
  AND t.scheduled_at > NOW()
GROUP BY t.id, u.display_name, u.bio, u.trust_score, 
         up.openness, up.conscientiousness, up.extraversion, up.agreeableness, up.neuroticism;

-- User Ratings Summary View
CREATE VIEW user_ratings_summary AS
SELECT 
    rated_user_id as user_id,
    COUNT(*) as total_ratings,
    AVG(overall_score) as avg_overall_score,
    AVG(friendliness_score) as avg_friendliness,
    AVG(punctuality_score) as avg_punctuality,
    AVG(engagement_score) as avg_engagement,
    SUM(CASE WHEN is_no_show THEN 1 ELSE 0 END) as no_show_count
FROM ratings
GROUP BY rated_user_id;

-- ==============================================
-- SEED DATA - INTEREST TAGS
-- ==============================================

INSERT INTO interest_tags (name, category) VALUES
    -- Food
    ('Italian Cuisine', 'food'),
    ('Japanese Food', 'food'),
    ('Street Food', 'food'),
    ('Vegan', 'food'),
    ('Coffee Lover', 'food'),
    ('Wine Tasting', 'food'),
    ('BBQ & Grilling', 'food'),
    ('Desserts', 'food'),
    
    -- Activities
    ('Hiking', 'activities'),
    ('Museums', 'activities'),
    ('Concerts', 'activities'),
    ('Board Games', 'activities'),
    ('Photography', 'activities'),
    ('Yoga', 'activities'),
    ('Karaoke', 'activities'),
    
    -- Music
    ('Rock Music', 'music'),
    ('Jazz', 'music'),
    ('Hip Hop', 'music'),
    ('Electronic', 'music'),
    ('Indie', 'music'),
    ('Classical', 'music'),
    
    -- Sports
    ('Basketball', 'sports'),
    ('Soccer', 'sports'),
    ('Running', 'sports'),
    ('Swimming', 'sports'),
    ('Tennis', 'sports'),
    ('Cycling', 'sports'),
    
    -- Arts
    ('Painting', 'arts'),
    ('Theater', 'arts'),
    ('Film', 'arts'),
    ('Literature', 'arts'),
    ('Dance', 'arts'),
    
    -- Tech
    ('Coding', 'tech'),
    ('Startups', 'tech'),
    ('Gaming', 'tech'),
    ('AI & ML', 'tech'),
    ('Crypto', 'tech'),
    
    -- Travel
    ('Backpacking', 'travel'),
    ('Beach Vacation', 'travel'),
    ('City Exploration', 'travel'),
    ('Adventure Travel', 'travel'),
    ('Luxury Travel', 'travel'),
    
    -- Hobbies
    ('Reading', 'hobbies'),
    ('Cooking', 'hobbies'),
    ('Gardening', 'hobbies'),
    ('DIY Projects', 'hobbies'),
    ('Meditation', 'hobbies'),
    ('Language Learning', 'hobbies');

-- ==============================================
-- NOTES
-- ==============================================
-- 1. RLS policies NOT added as per request
-- 2. H3 spatial indexing removed (can be added later if needed)
-- 3. PostGIS removed (can be added later if needed)
-- 4. All triggers and functions are included
-- 5. Views optimized for map display and matching algorithm
-- 6. Schema is production-ready for Supabase
