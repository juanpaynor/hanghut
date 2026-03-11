SELECT proname, prosrc 
FROM pg_proc 
WHERE proname IN ('handle_new_message', 'handle_new_direct_message', 'handle_new_trip_message');
