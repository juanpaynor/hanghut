import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { crypto } from "https://deno.land/std@0.168.0/crypto/mod.ts"

const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-callback-token',
}

serve(async (req) => {
    // Handle CORS preflight
    if (req.method === 'OPTIONS') {
        return new Response('ok', { headers: corsHeaders })
    }

    try {
        // Initialize Supabase client with service role (bypasses RLS)
        const supabaseClient = createClient(
            Deno.env.get('SUPABASE_URL') ?? '',
            Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
        )

        // Verify Xendit webhook signature
        const callbackToken = req.headers.get('x-callback-token')
        const webhookToken = Deno.env.get('XENDIT_WEBHOOK_TOKEN')

        if (webhookToken && callbackToken !== webhookToken) {
            console.error('Invalid webhook token')
            return new Response('Unauthorized', { status: 401 })
        }

        // Parse webhook payload
        const payload = await req.json()
        console.log('Xendit webhook received:', JSON.stringify(payload, null, 2))

        const eventType = payload.event || payload.type

        // Handle successful payments (Payment Request, Payment Session, Invoice)
        if (['payment.capture', 'payment_session.completed', 'payment.succeeded', 'invoice.paid'].includes(eventType)) {
            const data = payload.data || payload; // Handle wrapped data

            const {
                reference_id, // v3 uses reference_id matching our external_id
                payment_request_id,
                payment_id,
                status,
                currency,
                payment_method,
                created,
                captures,
            } = data;

            // Use reference_id as the lookup key (this matches our xendit_external_id)
            const lookupId = reference_id || payload.external_id;

            // Find purchase intent
            // Find purchase intent
            let { data: intent, error: intentError } = await supabaseClient
                .from('purchase_intents')
                .select('*, event:events(id, title, organizer_id, tickets_sold), user:users(id, email, full_name)')
                .eq('xendit_external_id', lookupId)
                .single()

            // Fallback: If not found by external ID, try lookup by metadata.intent_id (UUID)
            if (!intent && data.metadata?.intent_id) {
                console.log('Lookup by external_id failed, trying metadata.intent_id:', data.metadata.intent_id)

                // Simplified query without joins to avoid RLS issues
                const { data: fallbackIntent, error: fallbackError } = await supabaseClient
                    .from('purchase_intents')
                    .select('*')
                    .eq('id', data.metadata.intent_id)
                    .single()

                if (fallbackError) {
                    console.error('❌ Fallback lookup error:', fallbackError)
                }

                if (fallbackIntent) {
                    // Fetch related data separately (service role bypasses RLS better for direct queries)
                    const { data: event } = await supabaseClient
                        .from('events')
                        .select('id, title, organizer_id, tickets_sold')
                        .eq('id', fallbackIntent.event_id)
                        .single()

                    const { data: user } = await supabaseClient
                        .from('users')
                        .select('id, email, full_name')
                        .eq('id', fallbackIntent.user_id)
                        .maybeSingle()  // Use maybeSingle for guest checkouts (user_id might be null)

                    intent = { ...fallbackIntent, event, user }
                    intentError = null
                    console.log('✅ Found intent via fallback:', intent.id)
                }
            }

            if (intentError || !intent) {
                console.log('Purchase intent not found (likely a test webhook):', lookupId)
                // Return 200 to satisfy Xendit "Test and save" verification
                return new Response(JSON.stringify({ message: 'Webhook received but intent not found (Test passed)' }), {
                    status: 200,
                    headers: { ...corsHeaders, 'Content-Type': 'application/json' }
                })
            }

            console.log('Payment successful for intent:', intent.id)

            // Update purchase intent
            await supabaseClient
                .from('purchase_intents')
                .update({
                    status: 'completed',
                    paid_at: created || new Date().toISOString(),
                    payment_method: payment_method?.type || 'unknown',
                })
                .eq('id', intent.id)

            // Generate tickets
            const tickets = []
            for (let i = 0; i < intent.quantity; i++) {
                const ticketId = crypto.randomUUID()
                const qrCode = `${ticketId}:${intent.event_id}:${intent.user_id}`

                tickets.push({
                    id: ticketId,
                    purchase_intent_id: intent.id,
                    event_id: intent.event_id,
                    user_id: intent.user_id,
                    ticket_number: `TK-${Math.random().toString(36).substring(2, 10).toUpperCase()}`,
                    qr_code: qrCode,
                    status: 'valid',
                })
            }

            const { error: ticketsError } = await supabaseClient
                .from('tickets')
                .insert(tickets)

            if (ticketsError) {
                console.error('Failed to create tickets:', ticketsError)
                throw ticketsError
            }

            // Record transaction
            const { data: partner } = await supabaseClient
                .from('partners')
                .select('id, custom_percentage')
                .eq('id', intent.event.organizer_id)
                .single()

            const platformFeePercentage = partner?.custom_percentage || 10.0
            const platformFee = (intent.subtotal * platformFeePercentage) / 100
            const processingFee = intent.payment_processing_fee || 0
            const organizerPayout = intent.subtotal - platformFee

            await supabaseClient
                .from('transactions')
                .insert({
                    purchase_intent_id: intent.id,
                    event_id: intent.event_id,
                    partner_id: intent.event.organizer_id,
                    user_id: intent.user_id,
                    gross_amount: intent.subtotal,
                    platform_fee: platformFee,
                    payment_processing_fee: processingFee,
                    organizer_payout: organizerPayout,
                    fee_percentage: platformFeePercentage,
                    fee_basis: partner?.custom_percentage ? 'custom' : 'standard',
                    xendit_transaction_id: payment_request_id || payment_id || data.id,
                    status: 'completed',
                })

            console.log(`✅ Issued ${intent.quantity} tickets for intent ${intent.id}`)

            // Issue tickets using the RPC function (ensures they exist)
            console.log(`🎟️ Issuing tickets for intent ${intent.id}...`)
            const { data: generatedTickets, error: issueError } = await supabaseClient.rpc('issue_tickets', {
                p_intent_id: intent.id
            })

            if (issueError) {
                console.error('❌ Failed to issue tickets:', issueError)
            } else {
                console.log(`✅ Successfully issued ${generatedTickets.length} tickets`)
            }

            // Determine recipient (Guest or User)
            const recipientEmail = intent.guest_email || intent.user?.email
            const recipientName = intent.guest_name || intent.user?.full_name

            if (recipientEmail && generatedTickets && generatedTickets.length > 0) {
                console.log(`📧 Sending ticket email to ${recipientEmail}...`)

                const { error: emailError } = await supabaseClient.functions.invoke('send-ticket-email', {
                    body: {
                        email: recipientEmail,
                        name: recipientName,
                        event_title: intent.event?.title || 'Event',
                        event_venue: intent.event?.venue_name || 'Venue',
                        event_date: intent.event?.start_datetime, // Send raw ISO string
                        ticket_quantity: intent.quantity,
                        total_amount: intent.total_amount,
                        transaction_ref: intent.xendit_external_id || intent.id,
                        tickets: generatedTickets
                    }
                })

                if (emailError) {
                    console.error('❌ Failed to send email:', emailError)
                } else {
                    console.log('✅ Ticket email sent successfully')
                }
            } else {
                console.warn('⚠️ Skipping email: No recipient email or no tickets found')
            }

            return new Response(
                JSON.stringify({ success: true, tickets_issued: intent.quantity }),
                { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
            )
        }

        // Handle payment failure
        if (eventType === 'payment.failed' || eventType === 'payment_request.expired') {
            const external_id = payload.external_id || payload.reference_id

            const { data: intent } = await supabaseClient
                .from('purchase_intents')
                .select('*, event:events(tickets_sold)')
                .eq('xendit_external_id', external_id)
                .single()

            if (intent) {
                console.log('Payment failed/expired for intent:', intent.id)

                // Mark intent as failed/expired
                await supabaseClient
                    .from('purchase_intents')
                    .update({ status: eventType === 'payment.failed' ? 'failed' : 'expired' })
                    .eq('id', intent.id)

                // Release reserved capacity
                await supabaseClient
                    .from('events')
                    .update({ tickets_sold: intent.event.tickets_sold - intent.quantity })
                    .eq('id', intent.event_id)

                console.log(`❌ Released ${intent.quantity} tickets for intent ${intent.id}`)
            }

            return new Response(
                JSON.stringify({ success: true, capacity_released: true }),
                { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
            )
        }

        // Unknown event type
        console.log('Unhandled webhook event:', eventType)
        return new Response(
            JSON.stringify({ success: true, status: 'ignored', event: eventType }),
            { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )

    } catch (error) {
        console.error('Webhook error:', error)
        return new Response(
            JSON.stringify({ success: false, error: error.message }),
            { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
    }
})
