-- OPTIMIZE TRIP SCHEMA

-- 1. Standardize on 'user_trips' table
-- We ensure all columns needed by the UI are present
CREATE TABLE IF NOT EXISTS public.user_trips (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    
    destination_city TEXT NOT NULL,
    destination_country TEXT NOT NULL,
    
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    
    travel_style TEXT, -- 'budget', 'moderate', 'luxury'
    interests TEXT[], -- Array of strings
    goals TEXT[], -- Array of strings
    
    description TEXT,
    status TEXT DEFAULT 'upcoming', -- 'upcoming', 'active', 'completed'
    
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. Index for geospatial/temporal queries
CREATE INDEX IF NOT EXISTS idx_user_trips_dest ON public.user_trips(destination_city, destination_country);
CREATE INDEX IF NOT EXISTS idx_user_trips_dates ON public.user_trips(start_date, end_date);

-- 3. RPC: Find Trip Matches (Overlapping dates in same city)
CREATE OR REPLACE FUNCTION get_trip_matches(target_trip_id UUID)
RETURNS TABLE (
    user_id UUID,
    display_name TEXT,
    avatar_url TEXT,
    match_score INTEGER,
    start_date DATE,
    end_date DATE,
    overlap_days INTEGER
) AS $$
DECLARE
    target_city TEXT;
    target_country TEXT;
    target_start DATE;
    target_end DATE;
    target_interests TEXT[];
BEGIN
    -- Get target trip details
    SELECT destination_city, destination_country, start_date, end_date, interests
    INTO target_city, target_country, target_start, target_end, target_interests
    FROM user_trips 
    WHERE id = target_trip_id;

    RETURN QUERY
    SELECT 
        u.id,
        u.display_name,
        u.avatar_url,
        -- Simple match score logic: Base 50 + 10 per overlapping day + 10 per shared interest
        (50 + 
         (LEAST(t.end_date, target_end) - GREATEST(t.start_date, target_start)) * 10 
         -- Add interest intersection logic here if generic array overlap supported easily, else keep simple
        )::INTEGER as match_score,
        t.start_date,
        t.end_date,
        (LEAST(t.end_date, target_end) - GREATEST(t.start_date, target_start))::INTEGER as overlap_days
    FROM user_trips t
    JOIN users u ON t.user_id = u.id
    WHERE 
        t.destination_city = target_city 
        AND t.destination_country = target_country
        AND t.id != target_trip_id -- Exclude self
        AND t.start_date <= target_end 
        AND t.end_date >= target_start; -- Overlap Condition
END;
$$ LANGUAGE plpgsql;

-- 4. RPC: Get Popular Destinations (Buckets) via Group Chat counts
-- This helps populate a "Trending Trips" list
CREATE OR REPLACE FUNCTION get_trending_trips()
RETURNS TABLE (
    city TEXT,
    country TEXT,
    traveler_count BIGINT,
    bucket_id TEXT
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        destination_city, 
        destination_country, 
        COUNT(DISTINCT user_id) as count,
        MAX(destination_city || '_' || destination_country) as bucket_id 
    FROM user_trips
    WHERE start_date > NOW() 
    GROUP BY destination_city, destination_country
    ORDER BY count DESC
    LIMIT 10;
END;
$$ LANGUAGE plpgsql;

-- 5. RLS
ALTER TABLE public.user_trips ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can insert own trips" 
ON public.user_trips FOR INSERT 
TO authenticated 
WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can view all public trips" 
ON public.user_trips FOR SELECT 
TO authenticated 
USING (true); -- Public by default for matching
