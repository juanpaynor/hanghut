-- Add SELECT policy for purchase_intents to allow Edge Functions to read them

DROP POLICY IF EXISTS "Allow purchase intent select" ON purchase_intents;

CREATE POLICY "Allow purchase intent select"
  ON purchase_intents FOR SELECT
  USING (
    (auth.uid() = user_id) OR
    (auth.role() = 'service_role')
  );
