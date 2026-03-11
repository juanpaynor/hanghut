SELECT column_name, data_type 
FROM information_schema.columns 
WHERE table_name IN ('table_members', 'trip_chat_participants', 'direct_chat_participants', 'messages', 'direct_messages', 'trip_messages');
