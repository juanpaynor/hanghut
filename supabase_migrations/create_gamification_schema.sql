-- Create Badges Table
CREATE TABLE IF NOT EXISTS badges (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    slug TEXT NOT NULL UNIQUE, -- e.g., 'host_bronze'
    name TEXT NOT NULL,
    description TEXT NOT NULL,
    tier TEXT NOT NULL CHECK (tier IN ('bronze', 'silver', 'gold', 'platinum', 'diamond', 'special')),
    category TEXT NOT NULL CHECK (category IN ('hosting', 'social', 'verified', 'special')),
    icon_key TEXT NOT NULL, -- Logical key to map to Flutter icons or Assets
    requirements JSONB DEFAULT '{}'::jsonb, -- e.g., {"min_hosted": 5}
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create User Stats Table (for aggregation)
CREATE TABLE IF NOT EXISTS user_gamification_stats (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    total_events_hosted INTEGER DEFAULT 0,
    total_events_attended INTEGER DEFAULT 0,
    total_connections_made INTEGER DEFAULT 0,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create User Badges Table (Unlocked Badges)
CREATE TABLE IF NOT EXISTS user_badges (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    badge_id UUID NOT NULL REFERENCES badges(id) ON DELETE CASCADE,
    earned_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, badge_id)
);

-- RLS Policies
ALTER TABLE badges ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_gamification_stats ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_badges ENABLE ROW LEVEL SECURITY;

-- Badges are readable by everyone
CREATE POLICY "Badges are viewable by everyone" ON badges FOR SELECT USING (true);

-- User stats readable by everyone (or just self? usually gamification is public)
CREATE POLICY "Stats are viewable by everyone" ON user_gamification_stats FOR SELECT USING (true);

-- User badges readable by everyone
CREATE POLICY "User badges are viewable by everyone" ON user_badges FOR SELECT USING (true);

-- SEED DATA (Safe Insert)
INSERT INTO badges (slug, name, description, tier, category, icon_key, requirements)
VALUES
    -- Hosting Badges
    ('host_bronze', 'Rookie Host', 'Hosted your first event', 'bronze', 'hosting', 'star', '{"min_hosted": 1}'),
    ('host_silver', 'Regular Host', 'Hosted 5 events', 'silver', 'hosting', 'star', '{"min_hosted": 5}'),
    ('host_gold', 'Super Host', 'Hosted 10 events', 'gold', 'hosting', 'star_filled', '{"min_hosted": 10}'),
    ('host_platinum', 'Legendary Host', 'Hosted 25 events', 'platinum', 'hosting', 'crown', '{"min_hosted": 25}'),

    -- Social Badges
    ('social_bronze', 'Newcomer', 'Attended your first event', 'bronze', 'social', 'user', '{"min_attended": 1}'),
    ('social_silver', 'Social Butterfly', 'Attended 5 events', 'silver', 'social', 'users', '{"min_attended": 5}'),
    ('social_gold', 'Life of the Party', 'Attended 10 events', 'gold', 'social', 'party_popper', '{"min_attended": 10}'),

    -- Special
    ('verified_user', 'Verified Member', 'Verified identity', 'special', 'verified', 'verified_user', '{"verified": true}')
ON CONFLICT (slug) DO UPDATE SET
    name = EXCLUDED.name,
    description = EXCLUDED.description,
    tier = EXCLUDED.tier,
    category = EXCLUDED.category,
    icon_key = EXCLUDED.icon_key,
    requirements = EXCLUDED.requirements;
