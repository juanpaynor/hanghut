
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

// UUID validation regex
const UUID_REGEX = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

serve(async (req) => {
  // Handle CORS preflight requests
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // 1. Validate HTTP Method
    if (req.method !== 'POST') {
      return new Response(
        JSON.stringify({ error: 'Method not allowed. Use POST.' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 405 }
      )
    }

    // 2. Parse and Validate Request
    const { ticket_id, event_id, scanner_id } = await req.json()

    // Validate required fields
    if (!ticket_id || !event_id || !scanner_id) {
      return new Response(
        JSON.stringify({
          valid: false,
          error: 'MISSING_FIELDS',
          message: 'Missing required fields: ticket_id, event_id, scanner_id'
        }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 400 }
      )
    }

    // Validate UUID format
    if (!UUID_REGEX.test(ticket_id) || !UUID_REGEX.test(event_id) || !UUID_REGEX.test(scanner_id)) {
      return new Response(
        JSON.stringify({
          valid: false,
          error: 'INVALID_UUID',
          message: 'One or more IDs are not valid UUIDs'
        }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 400 }
      )
    }

    // 3. Init Supabase Client with Service Role (RPC is SECURITY DEFINER so it's safe)
    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
      {
        auth: {
          autoRefreshToken: false,
          persistSession: false
        }
      }
    )

    // 4. Call Atomic RPC
    const { data, error } = await supabaseClient.rpc('check_in_ticket', {
      p_ticket_id: ticket_id,
      p_event_id: event_id,
      p_scanner_id: scanner_id
    })

    if (error) {
      console.error('RPC Error:', error)
      return new Response(
        JSON.stringify({
          valid: false,
          error: 'RPC_ERROR',
          message: error.message
        }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 500 }
      )
    }

    // 5. Return Result (data is already a JSONB object from the RPC)
    return new Response(
      JSON.stringify(data),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: data.valid ? 200 : 400
      }
    )

  } catch (error) {
    console.error('Unexpected error:', error)
    return new Response(
      JSON.stringify({
        valid: false,
        error: 'INTERNAL_ERROR',
        message: error instanceof Error ? error.message : 'Unknown error'
      }),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 500
      }
    )
  }
})
