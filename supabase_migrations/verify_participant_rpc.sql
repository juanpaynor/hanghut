-- RPC for Secure P2P Verification
-- Performs server-side distance check before verifying a user

CREATE OR REPLACE FUNCTION verify_participant(
    p_table_id UUID,
    p_target_user_id UUID,
    p_verifier_lat FLOAT,
    p_verifier_lng FLOAT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER -- Runs with elevated permissions to check other tables/statuses
AS $$
DECLARE
    v_verifier_id UUID := auth.uid();
    v_verifier_status TEXT;
    v_is_host BOOLEAN;
    v_table_location GEOGRAPHY(POINT, 4326);
    v_distance_meters FLOAT;
BEGIN
    -- 1. Check if Verifier is Authorized (Host or Verified)
    -- Check Host
    SELECT (host_id = v_verifier_id) INTO v_is_host
    FROM public.tables WHERE id = p_table_id;

    -- Check Status if not host
    IF NOT v_is_host THEN
        SELECT arrival_status INTO v_verifier_status
        FROM public.table_members
        WHERE table_id = p_table_id AND user_id = v_verifier_id;
        
        IF v_verifier_status != 'verified' THEN
            RETURN jsonb_build_object('success', false, 'error', 'Verifier must be verified first.');
        END IF;
    END IF;

    -- 2. Check Distance (GPS Gating)
    -- Get table location
    SELECT location INTO v_table_location
    FROM public.tables WHERE id = p_table_id;

    IF v_table_location IS NULL THEN
         -- Fallback if location missing (shouldn't happen with backfill)
         RETURN jsonb_build_object('success', false, 'error', 'Venue location not found.');
    END IF;

    -- Calculate distance
    v_distance_meters := ST_Distance(
        v_table_location, 
        ST_SetSRID(ST_MakePoint(p_verifier_lng, p_verifier_lat), 4326)::geography
    );

    -- 200m Threshold
    IF v_distance_meters > 200 THEN
        RETURN jsonb_build_object(
            'success', false, 
            'error', format('Too far from venue (%s m). Must be within 200m.', round(v_distance_meters::numeric, 0))
        );
    END IF;

    -- 3. Verify the Target User
    UPDATE public.table_members
    SET 
        arrival_status = 'verified',
        verified_at = NOW(),
        verified_by = v_verifier_id
    WHERE table_id = p_table_id AND user_id = p_target_user_id;

    RETURN jsonb_build_object('success', true, 'message', 'User verified successfully');
END;
$$;
