-- Update map_ready_tables view to include both marker_image_url and host_photo_url
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
