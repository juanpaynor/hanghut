-- Drop the existing view thoroughly
DROP VIEW IF EXISTS map_ready_tables;

-- Recreate properly mapping the new `tables` schema columns to what the Dart frontend expects
CREATE OR REPLACE VIEW map_ready_tables AS
SELECT 
    t.id,
    t.title,
    t.description,
    t.cuisine_type as activity_type,
    t.location_name as venue_name,
    t.venue_address,
    t.latitude as location_lat,
    t.longitude as location_lng,
    t.latitude,
    t.longitude,
    t.datetime,
    t.datetime as scheduled_at,
    t.datetime as scheduled_time,
    t.max_guests as max_capacity,
    t.current_capacity,
    t.status,
    t.marker_image_url,
    t.price_per_person,
    t.currency,
    t.experience_type,
    t.is_experience,
    t.images,
    t.requirements,
    t.included_items,
    t.verified_by_hanghut,
    
    -- Host info 
    t.host_id,
    u.display_name as host_name,
    COALESCE(t.host_bio, u.bio) as host_bio,
    u.trust_score as host_trust_score,
    COALESCE(t.host_avatar_url, u.avatar_url, up_photo.photo_url) as host_photo_url,
    
    -- Host personality traits (for matching algorithm)
    up.openness,
    up.conscientiousness,
    up.extraversion,
    up.agreeableness,
    up.neuroticism,
    
    -- Capacity info 
    COALESCE(tm_stats.member_count, 0) as member_count,
    COALESCE(tm_stats.approved_count, 0) as approved_count,
    COALESCE(tm_stats.pending_count, 0) as pending_count,
    (t.max_guests - t.current_capacity) as seats_left,
    CASE 
        WHEN t.current_capacity >= t.max_guests THEN 'full'
        WHEN t.current_capacity >= (t.max_guests * 0.8) THEN 'filling_up'
        ELSE 'available'
    END as availability_state
    
FROM tables t
LEFT JOIN users u ON t.host_id = u.id
LEFT JOIN user_personality up ON u.id = up.user_id
LEFT JOIN user_photos up_photo ON u.id = up_photo.user_id AND up_photo.is_primary = true
LEFT JOIN (
    SELECT 
        table_id,
        COUNT(id) FILTER (WHERE status IN ('approved', 'joined')) as member_count,
        COUNT(id) FILTER (WHERE status = 'approved') as approved_count,
        COUNT(id) FILTER (WHERE status = 'pending') as pending_count
    FROM table_members
    GROUP BY table_id
) tm_stats ON t.id = tm_stats.table_id
WHERE t.status IN ('open', 'full')
  AND t.datetime > (NOW() - INTERVAL '12 hours');
