SELECT proname, pg_get_functiondef(oid)
FROM pg_proc
WHERE proname IN ('handle_table_join', 'handle_join_approval', 'handle_join_decline');
