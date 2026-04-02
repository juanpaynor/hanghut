-- ============================================================================
-- ATOMIC DECREMENT TICKETS_SOLD
-- ============================================================================
-- Used by the Xendit webhook to safely release ticket capacity without
-- race conditions. Instead of read-then-write (which can produce negative
-- values or incorrect counts under concurrent requests), this function
-- uses a direct SQL UPDATE with GREATEST to clamp at 0.
--
-- Usage from Supabase client:
--   supabaseClient.rpc('atomic_decrement_tickets_sold', {
--     p_event_id: 'uuid-here',
--     p_quantity: 2
--   })
-- ============================================================================

CREATE OR REPLACE FUNCTION atomic_decrement_tickets_sold(
    p_event_id UUID,
    p_quantity INTEGER
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    UPDATE events
    SET tickets_sold = GREATEST(0, tickets_sold - p_quantity)
    WHERE id = p_event_id;
END;
$$;

COMMENT ON FUNCTION atomic_decrement_tickets_sold IS
    'Atomically decrements tickets_sold for an event, clamping at 0. Used by webhook handlers to avoid read-then-write race conditions.';
