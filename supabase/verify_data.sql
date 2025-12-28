-- Query to check user profile data after signup/profile setup
-- Run this in Supabase SQL Editor to verify data was inserted correctly

-- Check users table
SELECT 
    id,
    email,
    display_name,
    bio,
    date_of_birth,
    gender_identity,
    trust_score,
    created_at
FROM users
ORDER BY created_at DESC
LIMIT 5;

-- Check user personality (Big 5 traits)
SELECT 
    u.email,
    u.display_name,
    up.openness,
    up.conscientiousness,
    up.extraversion,
    up.agreeableness,
    up.neuroticism,
    up.completed_at
FROM user_personality up
JOIN users u ON up.user_id = u.id
ORDER BY up.completed_at DESC
LIMIT 5;

-- Check user preferences
SELECT 
    u.email,
    u.display_name,
    pref.budget_min,
    pref.budget_max,
    pref.primary_goal,
    pref.preferred_meetup_mode,
    pref.gender_preference,
    pref.preferred_group_size_min,
    pref.preferred_group_size_max
FROM user_preferences pref
JOIN users u ON pref.user_id = u.id
ORDER BY u.created_at DESC
LIMIT 5;

-- Check user photos
SELECT 
    u.email,
    u.display_name,
    p.photo_url,
    p.is_primary,
    p.uploaded_at
FROM user_photos p
JOIN users u ON p.user_id = u.id
ORDER BY p.uploaded_at DESC
LIMIT 5;

-- Check user interests
SELECT 
    u.email,
    u.display_name,
    STRING_AGG(it.name, ', ' ORDER BY it.name) as interests
FROM user_interests ui
JOIN users u ON ui.user_id = u.id
JOIN interest_tags it ON ui.interest_tag_id = it.id
GROUP BY u.id, u.email, u.display_name
ORDER BY u.created_at DESC
LIMIT 5;

-- Complete profile view for latest user
SELECT 
    u.id,
    u.email,
    u.display_name,
    u.bio,
    u.date_of_birth,
    u.gender_identity,
    u.trust_score,
    
    -- Personality
    up.openness,
    up.conscientiousness,
    up.extraversion,
    up.agreeableness,
    up.neuroticism,
    
    -- Preferences
    pref.budget_min,
    pref.budget_max,
    pref.primary_goal,
    pref.preferred_meetup_mode,
    
    -- Photos
    (SELECT COUNT(*) FROM user_photos WHERE user_id = u.id) as photo_count,
    (SELECT photo_url FROM user_photos WHERE user_id = u.id AND is_primary = true) as primary_photo,
    
    -- Interests
    (SELECT COUNT(*) FROM user_interests WHERE user_id = u.id) as interest_count,
    (SELECT STRING_AGG(it.name, ', ') 
     FROM user_interests ui 
     JOIN interest_tags it ON ui.interest_tag_id = it.id 
     WHERE ui.user_id = u.id) as interests
    
FROM users u
LEFT JOIN user_personality up ON u.id = up.user_id
LEFT JOIN user_preferences pref ON u.id = pref.user_id
ORDER BY u.created_at DESC
LIMIT 1;
