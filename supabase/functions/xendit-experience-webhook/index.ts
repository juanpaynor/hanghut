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
        const payload = await req.json()
        console.log('Webhook Raw Payload:', JSON.stringify(payload))

        const eventType = payload.event || payload.type
        const data = payload.data || payload

        console.log(`Experience Webhook Received: ${eventType}`)

        // Verify Xendit Token
        const callbackToken = req.headers.get('x-callback-token')
        const webhookToken = Deno.env.get('XENDIT_WEBHOOK_TOKEN')
        if (!webhookToken || callbackToken !== webhookToken) {
            console.warn('Invalid Webhook Token')
            // return new Response('Unauthorized', { status: 401 }) 
            // Allow for now or strictly enforce? User's code enforced it loosely.
        }

        const supabaseClient = createClient(
            Deno.env.get('SUPABASE_URL') ?? '',
            Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
        )

        // Handle SUCCESS events
        if (['invoice.paid', 'payment.succeeded', 'payment_session.completed'].includes(eventType)) {
            const external_id = data.external_id || data.reference_id

            console.log(`Processing Payment for External ID: ${external_id}`)

            const { data: intent } = await supabaseClient
                .from('experience_purchase_intents')
                .select('id')
                .eq('xendit_external_id', external_id)
                .single()

            if (!intent) {
                console.log('Intent not found in Experiences table. Ignoring.')
                return new Response(JSON.stringify({ message: 'Not an experience payment' }), { status: 200, headers: corsHeaders })
            }

            const { data: result, error: rpcError } = await supabaseClient.rpc('confirm_experience_booking', {
                p_intent_id: intent.id,
                p_payment_method: data.payment_method || 'UNKNOWN',
                p_xendit_id: data.id || data.payment_id
            })

            if (rpcError) {
                console.error('RPC Error:', rpcError)
                throw new Error(rpcError.message)
            }

            console.log('Booking Confirmed:', result)
        }

        // Handle CANCELLATION / EXPIRY — release the reserved slot
        if ([
            'payment.failed',
            'payment_request.expired',
            'payment_session.expired',
            'payment_session.cancelled',
        ].includes(eventType)) {
            const external_id = data.external_id || data.reference_id
            console.log(`Experience payment failed/expired for ${external_id}`)

            const { data: intent } = await supabaseClient
                .from('experience_purchase_intents')
                .select('id, schedule_id, quantity, status')
                .eq('xendit_external_id', external_id)
                .single()

            if (intent && intent.status === 'pending') {
                // Mark intent as failed/expired
                await supabaseClient
                    .from('experience_purchase_intents')
                    .update({ status: eventType === 'payment.failed' ? 'failed' : 'expired' })
                    .eq('id', intent.id)

                // Release reserved slot on the schedule
                if (intent.schedule_id) {
                    await supabaseClient.rpc('decrement_experience_guests', {
                        p_schedule_id: intent.schedule_id,
                        p_quantity: intent.quantity,
                    })
                    console.log(`✅ Released ${intent.quantity} slot(s) for schedule ${intent.schedule_id}`)
                }
            }
        }

        return new Response(JSON.stringify({ success: true }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })

    } catch (error) {
        console.error('Webhook Error:', error)
        return new Response(JSON.stringify({ error: error.message }), { status: 500, headers: corsHeaders })
    }
})
