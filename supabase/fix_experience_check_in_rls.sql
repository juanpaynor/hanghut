-- Fix for Experience Check-In Silently Failing
-- This policy allows a Host to update the 'experience_purchase_intents' table 
-- (specifically for checking in guests) if the host owns the associated 'tables' record.

CREATE POLICY "Hosts can update experience purchase intents"
ON public.experience_purchase_intents
FOR UPDATE
USING (
  EXISTS (
    SELECT 1 FROM public.tables t
    WHERE t.id = experience_purchase_intents.table_id
    AND t.host_id = auth.uid()
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1 FROM public.tables t
    WHERE t.id = experience_purchase_intents.table_id
    AND t.host_id = auth.uid()
  )
);
