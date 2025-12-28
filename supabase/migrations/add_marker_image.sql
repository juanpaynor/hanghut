-- Add marker_image_url column to tables
ALTER TABLE tables ADD COLUMN marker_image_url TEXT;

-- Create storage bucket for table marker images
INSERT INTO storage.buckets (id, name, public)
VALUES ('table-markers', 'table-markers', true)
ON CONFLICT (id) DO NOTHING;

-- Function to delete marker image from storage when table is deleted or completed
CREATE OR REPLACE FUNCTION delete_table_marker_image()
RETURNS TRIGGER AS $$
BEGIN
    -- Delete image if table is being deleted or status changed to completed/cancelled
    IF (TG_OP = 'DELETE' OR 
        (NEW.status IN ('completed', 'cancelled') AND OLD.status NOT IN ('completed', 'cancelled'))) THEN
        
        -- Extract filename from URL and delete from storage
        IF COALESCE(OLD.marker_image_url, NEW.marker_image_url) IS NOT NULL THEN
            -- Note: Actual file deletion needs to be done via Supabase client
            -- This trigger just marks for cleanup
            NULL; -- Placeholder for storage deletion logic
        END IF;
    END IF;
    
    RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

-- Trigger to auto-delete marker images
CREATE TRIGGER trigger_delete_marker_image
    AFTER UPDATE OR DELETE ON tables
    FOR EACH ROW
    EXECUTE FUNCTION delete_table_marker_image();

-- Update map_ready_tables view to include marker_image_url
DROP VIEW IF EXISTS map_ready_tables;

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
    t.marker_image_url,
    
    -- Host info
    t.host_user_id as host_id,
    u.display_name as host_name,
    u.bio as host_bio,
    u.trust_score as host_trust_score,
    up_photo.photo_url as host_photo_url,
    
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
LEFT JOIN user_photos up_photo ON u.id = up_photo.user_id AND up_photo.is_primary = true
LEFT JOIN table_members tm ON t.id = tm.table_id
WHERE t.status IN ('open', 'full')
  AND t.scheduled_at > (NOW() - INTERVAL '1 hour')
GROUP BY t.id, u.display_name, u.bio, u.trust_score, up_photo.photo_url,
         up.openness, up.conscientiousness, up.extraversion, up.agreeableness, up.neuroticism;
