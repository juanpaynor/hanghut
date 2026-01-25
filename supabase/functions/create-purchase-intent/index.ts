import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
    // Handle CORS preflight
    if (req.method === 'OPTIONS') {
        return new Response('ok', { headers: corsHeaders })
    }

    try {
        // Initialize Supabase client
        const supabaseClient = createClient(
            Deno.env.get('SUPABASE_URL') ?? '',
            Deno.env.get('SUPABASE_ANON_KEY') ?? '',
            {
                global: {
                    headers: { Authorization: req.headers.get('Authorization')! },
                },
            }
        )

        // Initialize Admin client for privileged operations (RLS bypass)
        const supabaseAdmin = createClient(
            Deno.env.get('SUPABASE_URL') ?? '',
            Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
        )

        // Parse request body first (needed for guest check)
        const { event_id, quantity, channel_code, guest_details, success_url, failure_url } = await req.json()

        // Get authenticated user (if any)
        const {
            data: { user },
        } = await supabaseClient.auth.getUser()

        // Guest Checkout Validation
        if (!user) {
            // If no user, MUST have guest details
            if (!guest_details?.email || !guest_details?.name) {
                return new Response(
                    JSON.stringify({
                        success: false,
                        error: { code: 'UNAUTHORIZED', message: 'Authentication or Guest Details required' }
                    }),
                    { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
                )
            }
        }

        // Get user profile for customer details (only if authenticated)
        let userProfile = null
        if (user) {
            const { data: profile } = await supabaseClient
                .from('users')
                .select('full_name, phone')
                .eq('id', user.id)
                .single()
            userProfile = profile
        }

        // Validate input
        if (!event_id || !quantity || quantity < 1) {
            return new Response(
                JSON.stringify({
                    success: false,
                    error: { code: 'VALIDATION_ERROR', message: 'Invalid event_id or quantity' }
                }),
                { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
            )
        }

        // Call RPC function to reserve tickets (handles atomic capacity locking)
        const { data: intentData, error: reserveError } = await supabaseClient.rpc(
            'reserve_tickets',
            {
                p_event_id: event_id,
                p_user_id: user?.id ?? null,
                p_quantity: quantity,
                p_guest_email: guest_details?.email ?? null,
                p_guest_name: guest_details?.name ?? null,
                p_guest_phone: guest_details?.phone ?? null,
            }
        )

        if (reserveError) {
            console.error('Reserve tickets error:', reserveError)
            return new Response(
                JSON.stringify({
                    success: false,
                    error: {
                        code: reserveError.message.includes('sold out') ? 'SOLD_OUT' : 'SERVER_ERROR',
                        message: reserveError.message
                    }
                }),
                { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
            )
        }

        const intentId = intentData

        // Fetch the created purchase intent using Admin client (bypasses RLS)
        const { data: intent, error: fetchError } = await supabaseAdmin
            .from('purchase_intents')
            .select('*, event:events(*)')
            .eq('id', intentId)
            .single()

        if (fetchError || !intent) {
            throw new Error('Failed to fetch purchase intent')
        }

        // Create Xendit Payment Session (Hosted Checkout)
        const xenditKey = Deno.env.get('XENDIT_SECRET_KEY')
        if (!xenditKey) {
            throw new Error('XENDIT_SECRET_KEY not configured')
        }

        const sessionBody = {
            reference_id: intent.xendit_external_id,
            session_type: 'PAY', // One-time payment
            mode: 'PAYMENT_LINK', // Hosted checkout page
            amount: Math.round(intent.total_amount),
            currency: 'PHP',
            country: 'PH',
            customer: {
                // Append unique timestamp to reference_id to prevent DUPLICATE_ERROR from Xendit
                reference_id: (user?.id ? `${user.id}_${Date.now()}` : `guest_${intent.id}_${Date.now()}`),
                type: 'INDIVIDUAL',
                email: user?.email || guest_details?.email || 'customer@example.com',
                mobile_number: (user ? (userProfile?.phone || '') : (guest_details?.phone || '')) || '+639000000000',
                individual_detail: {
                    given_names: user ? (userProfile?.full_name?.split(' ')[0] || 'Customer') : (guest_details?.name?.split(' ')[0] || 'Guest'),
                    surname: (user ? (userProfile?.full_name?.split(' ').slice(1).join(' ')) : (guest_details?.name?.split(' ').slice(1).join(' '))) || '-',
                },
            },
            description: `${quantity} ticket(s) for ${intent.event.title}`,
            success_return_url: success_url || undefined,
            cancel_return_url: failure_url || undefined,
            metadata: {
                event_id: event_id,
                intent_id: intentId,
                user_id: user?.id || 'guest',
                is_guest: String(!user),
            },
        }

        console.log('Creating Xendit Payment Session:', sessionBody)

        const headers = new Headers()
        headers.set('Authorization', `Basic ${btoa(xenditKey + ':')}`)
        headers.set('Content-Type', 'application/json')
        // headers.set('api-version', '2024-11-11') 

        const xenditResponse = await fetch('https://api.xendit.co/sessions', {
            method: 'POST',
            headers,
            body: JSON.stringify(sessionBody),
        })

        if (!xenditResponse.ok) {
            const xenditError = await xenditResponse.text()
            console.error('Xendit error:', xenditError)

            // Release reserved tickets
            await supabaseClient
                .from('purchase_intents')
                .update({ status: 'failed' })
                .eq('id', intentId)

            await supabaseClient
                .from('events')
                .update({ tickets_sold: intent.event.tickets_sold - quantity })
                .eq('id', event_id)

            throw new Error(`Payment provider error: ${xenditError}`)
        }

        const session = await xenditResponse.json()
        console.log('Xendit Payment Session created:', session)

        // Update purchase intent with Xendit details
        await supabaseClient
            .from('purchase_intents')
            .update({
                xendit_invoice_id: session.id, // Store session ID
                xendit_invoice_url: session.payment_link_url, // For redirect
                payment_method: 'multiple',
            })
            .eq('id', intentId)

        // Return success response with Payment Link
        return new Response(
            JSON.stringify({
                success: true,
                data: {
                    intent_id: intentId,
                    payment_request_id: session.id,
                    subtotal: intent.subtotal,
                    platform_fee: intent.platform_fee,
                    total_amount: intent.total_amount,
                    payment_url: session.payment_link_url,
                    expires_at: intent.expires_at,
                    tickets_reserved: quantity,
                    event: {
                        title: intent.event.title,
                        start_datetime: intent.event.start_datetime,
                    },
                },
            }),
            { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )

    } catch (error) {
        console.error('Create purchase intent error:', error)
        return new Response(
            JSON.stringify({
                success: false,
                error: { message: error.message || 'Internal Server Error' }
            }),
            { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
    }
})
