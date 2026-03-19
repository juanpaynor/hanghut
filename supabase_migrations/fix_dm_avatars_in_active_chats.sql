-- =========================================================================
-- FIX v2: DM Avatars - don't require is_primary = true
-- =========================================================================
-- Previous fix filtered by is_primary = true, but many users don't have
-- that flag set. This version grabs the first photo, preferring primary.

CREATE OR REPLACE VIEW public.user_active_chats AS
 SELECT t.id AS chat_id,
    tm.user_id,
    'table'::text AS chat_type,
    t.title,
    t.location_name AS subtitle,
    NULL::text AS image_url,
    t.cuisine_type AS icon_key,
    COALESCE((SELECT max("timestamp") FROM messages m WHERE m.table_id = t.id), GREATEST(tm.joined_at, t.created_at)) AS last_activity_at,
    jsonb_build_object('table_id', t.id, 'status', t.status, 'max_guests', t.max_guests) AS metadata,
    (SELECT count(*) FROM messages m WHERE m.table_id = t.id AND m.sender_id != tm.user_id AND (tm.last_read_at IS NULL OR m.timestamp > tm.last_read_at)) AS unread_count,
    ((SELECT count(*) FROM messages m WHERE m.table_id = t.id AND m.sender_id != tm.user_id AND (tm.last_read_at IS NULL OR m.timestamp > tm.last_read_at)) > 0) AS has_unread
   FROM tables t
     JOIN table_members tm ON t.id = tm.table_id
  WHERE tm.status = ANY (ARRAY['approved'::member_status_type, 'joined'::member_status_type, 'attended'::member_status_type])
UNION ALL
 SELECT dc.id AS chat_id,
    dcp.user_id,
    'dm'::text AS chat_type,
    u.display_name AS title,
    COALESCE(( SELECT
                CASE
                    WHEN direct_messages.message_type = 'gif'::text THEN 'GIF'::text
                    ELSE direct_messages.content
                END AS content
           FROM direct_messages
          WHERE direct_messages.chat_id = dc.id
          ORDER BY direct_messages.created_at DESC
         LIMIT 1), 'Direct Message'::text) AS subtitle,
    -- FIX v3: NEVER use avatar_url - only user_photos
    (
      SELECT up.photo_url FROM user_photos up
      WHERE up.user_id = u.id
      ORDER BY up.is_primary DESC NULLS LAST, up.display_order ASC NULLS LAST
      LIMIT 1
    ) AS image_url,
    'person'::text AS icon_key,
    COALESCE((SELECT max(created_at) FROM direct_messages m WHERE m.chat_id = dc.id), dc.updated_at) AS last_activity_at,
    jsonb_build_object('other_user_id', u.id, 'other_user_name', u.display_name) AS metadata,
    (SELECT count(*) FROM direct_messages m WHERE m.chat_id = dc.id AND m.sender_id != dcp.user_id AND (dcp.last_read_at IS NULL OR m.created_at > dcp.last_read_at)) AS unread_count,
    ((SELECT count(*) FROM direct_messages m WHERE m.chat_id = dc.id AND m.sender_id != dcp.user_id AND (dcp.last_read_at IS NULL OR m.created_at > dcp.last_read_at)) > 0) AS has_unread
   FROM direct_chats dc
     JOIN direct_chat_participants dcp ON dc.id = dcp.chat_id
     JOIN direct_chat_participants other_p ON dc.id = other_p.chat_id AND other_p.user_id <> dcp.user_id
     JOIN users u ON other_p.user_id = u.id
UNION ALL
 SELECT tgc.id AS chat_id,
    tcp.user_id,
    'trip'::text AS chat_type,
    tgc.destination_city || ' Group'::text AS title,
    tgc.destination_country AS subtitle,
    NULL::text AS image_url,
    'flight'::text AS icon_key,
    COALESCE((SELECT max(sent_at) FROM trip_messages m WHERE m.chat_id = tgc.id), tgc.start_date) AS last_activity_at,
    jsonb_build_object('bucket_id', tgc.ably_channel_id, 'start_date', tgc.start_date) AS metadata,
    (SELECT count(*) FROM trip_messages m WHERE m.chat_id = tgc.id AND m.sender_id != tcp.user_id AND (tcp.last_read_at IS NULL OR m.sent_at > tcp.last_read_at)) AS unread_count,
    ((SELECT count(*) FROM trip_messages m WHERE m.chat_id = tgc.id AND m.sender_id != tcp.user_id AND (tcp.last_read_at IS NULL OR m.sent_at > tcp.last_read_at)) > 0) AS has_unread
   FROM trip_group_chats tgc
     JOIN trip_chat_participants tcp ON tgc.id = tcp.chat_id;
