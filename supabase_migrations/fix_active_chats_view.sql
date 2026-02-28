-- Unified View for Active Chats (Tables, DMs, Trips)
-- This view aggregates all chat types for a user to enable simple pagination

CREATE OR REPLACE VIEW user_active_chats AS
-- 1. Tables (Hangouts)
SELECT
    t.id AS chat_id,
    tm.user_id AS user_id,
    'table' AS chat_type,
    t.title AS title,
    t.location_name AS subtitle,
    NULL AS image_url, -- Could join with table_photos if needed
    t.cuisine_type AS icon_key,
    GREATEST(tm.joined_at, t.created_at) AS last_activity_at, -- improved sort metric
    jsonb_build_object(
        'table_id', t.id,
        'status', t.status,
        'max_guests', t.max_guests
    ) AS metadata
FROM tables t
JOIN table_members tm ON t.id = tm.table_id
WHERE tm.status IN ('approved', 'joined', 'attended')

UNION ALL

-- 2. Direct Messages (DMs)
SELECT
    dc.id AS chat_id,
    dcp.user_id AS user_id,
    'dm' AS chat_type,
    u.display_name AS title, -- The OTHER user's name
    -- Fetch the actual last message using a LEFT JOIN LATERAL
    COALESCE(
        (
            SELECT 
                CASE 
                    WHEN message_type = 'gif' THEN 'GIF'
                    ELSE content 
                END
            FROM direct_messages 
            WHERE chat_id = dc.id 
            ORDER BY created_at DESC 
            LIMIT 1
        ),
        'Direct Message'
    ) AS subtitle,
    u.avatar_url AS image_url,
    'person' AS icon_key,
    dc.updated_at AS last_activity_at,
    jsonb_build_object(
        'other_user_id', u.id,
        'other_user_name', u.display_name
    ) AS metadata
FROM direct_chats dc
JOIN direct_chat_participants dcp ON dc.id = dcp.chat_id
-- Join to get the OTHER participant for title/image
JOIN direct_chat_participants other_p ON dc.id = other_p.chat_id AND other_p.user_id != dcp.user_id
JOIN users u ON other_p.user_id = u.id

UNION ALL

-- 3. Trip Chats
SELECT
    tgc.id AS chat_id,
    tcp.user_id AS user_id,
    'trip' AS chat_type,
    tgc.destination_city || ' Group' AS title,
    tgc.destination_country AS subtitle,
    NULL AS image_url,
    'flight' AS icon_key,
    tgc.start_date AS last_activity_at, -- Or last_message_at if added to schema
    jsonb_build_object(
        'bucket_id', tgc.ably_channel_id,
        'start_date', tgc.start_date
    ) AS metadata
FROM trip_group_chats tgc
JOIN trip_chat_participants tcp ON tgc.id = tcp.chat_id;
