-- Create SQL function to find existing direct chat between two users
CREATE OR REPLACE FUNCTION find_direct_chat(user_id_1 UUID, user_id_2 UUID)
RETURNS TABLE (chat_id UUID) AS $$
BEGIN
  RETURN QUERY
  SELECT dcp1.chat_id
  FROM direct_chat_participants dcp1
  INNER JOIN direct_chat_participants dcp2 
    ON dcp1.chat_id = dcp2.chat_id
  WHERE dcp1.user_id = user_id_1 
    AND dcp2.user_id = user_id_2
  LIMIT 1;
END;
$$ LANGUAGE plpgsql;
