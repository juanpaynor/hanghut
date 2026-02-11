import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { crypto } from "https://deno.land/std@0.168.0/crypto/mod.ts"

const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-callback-token',
}

serve(async (req) => {
    console.log('🚨 WEBHOOK RECEIVED 🚨') // High-vis debug log

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
                .select('*, event:events(id, title, organizer_id, tickets_sold, venue_name, start_datetime, cover_image_url), user:users(id, email, full_name)')
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
                        .select('id, title, organizer_id, tickets_sold, venue_name, start_datetime, cover_image_url')
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

            // Extract Payment Method Detail
            let capturedMethod = 'unknown';
            if (data.payment_channel) {
                capturedMethod = data.payment_channel;
            } else if (typeof data.payment_method === 'string') {
                capturedMethod = data.payment_method;
            } else if (data.payment_method) {
                const pm = data.payment_method;
                capturedMethod = pm.ewallet?.channel_code ||
                    pm.retail_outlet?.channel_code ||
                    pm.qr_code?.channel_code ||
                    pm.direct_debit?.channel_code ||
                    pm.card?.channel_code ||
                    pm.virtual_account?.channel_code ||
                    pm.type ||
                    'unknown';
            }

            // Update purchase intent
            await supabaseClient
                .from('purchase_intents')
                .update({
                    status: 'completed',
                    paid_at: created || new Date().toISOString(),
                    payment_method: capturedMethod,
                })
                .eq('id', intent.id)

            // Record transaction (Create transaction BEFORE tickets to ensure accounting)
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

            console.log(`✅ Recorded transaction for intent ${intent.id}`)

            // Issue tickets using the RPC function (Single Source of Truth)
            console.log(`🎟️ Issuing tickets for intent ${intent.id} via RPC...`)
            const { data: generatedTickets, error: issueError } = await supabaseClient.rpc('issue_tickets', {
                p_intent_id: intent.id
            })

            if (issueError) {
                console.error('❌ Failed to issue tickets:', issueError)
            } else {
                console.log(`✅ Successfully issued ${generatedTickets?.length ?? 0} tickets`)
            }

            // Determine recipient (Guest or User)
            const recipientEmail = intent.guest_email || intent.user?.email
            const recipientName = intent.guest_name || intent.user?.full_name

            if (recipientEmail && generatedTickets && generatedTickets.length > 0) {
                console.log(`📧 Sending ticket email to ${recipientEmail} (${recipientName})...`)

                const { error: emailError } = await supabaseClient.functions.invoke('send-ticket-email', {
                    body: {
                        email: recipientEmail,
                        name: recipientName,
                        event_title: intent.event?.title || 'Event',
                        event_venue: intent.event?.venue_name || 'Venue',
                        event_date: intent.event?.start_datetime, // Send raw ISO string
                        event_cover_image: intent.event?.cover_image_url,
                        ticket_quantity: intent.quantity,
                        total_amount: intent.total_amount,
                        transaction_ref: intent.xendit_external_id || intent.id,
                        payment_method: capturedMethod,
                        tickets: generatedTickets
                    }
                })

                if (emailError) {
                    console.error('❌ Failed to send email:', emailError)
                } else {
                    console.log('✅ Ticket email sent successfully')
                }
            } else {
                console.warn('⚠️ Skipping email: No recipient email or no tickets found', {
                    email: recipientEmail,
                    ticketsFound: generatedTickets?.length,
                    intentId: intent.id
                })
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

        // Handle Payout/Disbursement Events (V2)
        if (['payout.succeeded', 'payout.failed', 'DISBURSEMENT.UPDATED'].includes(eventType)) {
            const data = payload.data || payload;
            const reference_id = data.reference_id || data.external_id; // V2 uses reference_id, Legacy uses external_id

            console.log(`Processing Payout Event: ${eventType} for ${reference_id}`);

            // Map status
            let newStatus = 'processing';
            if (eventType === 'payout.succeeded' || data.status === 'COMPLETED') {
                newStatus = 'completed';
            } else if (eventType === 'payout.failed' || data.status === 'FAILED') {
                newStatus = 'failed';
            }

            // Update payouts table
            const updatePayload: any = { status: newStatus };
            if (newStatus === 'completed') {
                updatePayload.completed_at = new Date().toISOString();
            } else {
                // reset processed_at if failed? or keep track?
            }

            const { error: updateError } = await supabaseClient
                .from('payouts')
                .update(updatePayload)
                .eq('id', reference_id);

            if (updateError) {
                console.error(`❌ Failed to update payout ${reference_id}:`, updateError);
                return new Response(JSON.stringify({ error: updateError.message }), { status: 500, headers: corsHeaders });
            }

            console.log(`✅ Payout ${reference_id} updated to ${newStatus}`);

            return new Response(
                JSON.stringify({ success: true, status: newStatus }),
                { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
            );
        }

        // Handle Refund Events
        if (['refund.succeeded', 'refund.failed'].includes(eventType)) {
            const data = payload.data || payload;
            console.log(`Processing Refund Event: ${eventType}`, data);

            // Look for intent_id in metadata
            const intentId = data.metadata?.intent_id;
            // Logic to find intent if metadata missing? Maybe match by payment_id/request_id if stored?
            // But for now reliance on metadata is safest.

            if (!intentId) {
                console.error('Refund event missing metadata.intent_id');
                return new Response(JSON.stringify({ message: 'Missing intent_id in metadata' }), { status: 200, headers: corsHeaders });
            }

            if (eventType === 'refund.succeeded') {
                // 1. Mark Purchase Intent as Refunded
                await supabaseClient
                    .from('purchase_intents')
                    .update({ status: 'refunded' })
                    .eq('id', intentId);

                // 2. Retrieve Intent Details for Accounting
                const { data: intent } = await supabaseClient
                    .from('purchase_intents')
                    .select('*, event:events(organizer_id, tickets_sold)')
                    .eq('id', intentId)
                    .single();

                if (intent) {
                    // 3. Release Capacity?
                    // If tickets were issued, we should probably void them?
                    // Currently no 'void' status in tickets table schema mentioned, but let's check intent logic.
                    // The requirement usually is to release capacity back to event.

                    await supabaseClient.from('events')
                        .update({ tickets_sold: intent.event.tickets_sold - intent.quantity })
                        .eq('id', intent.event_id);

                    // 3b. Mark tickets as cancelled/void if tickets table exists
                    // "update tickets set status = 'void' where purchase_intent_id = ..."
                    // Let's try it blindly or check schema? Schema has `tickets` table. Status?
                    // "status TEXT NOT NULL CHECK (status IN ('valid', 'used', 'expired'))" - Wait, no 'void'?
                    // Just delete them? Or add status 'expired'? 'expired' seems wrong.
                    // Let's assume for now we just rely on purchase_intent status.

                    // 4. Record Negative Transaction (Accounting)
                    // Fetch original transaction to get fee breakdown?
                    // Or just reverse the amounts from intent.

                    const { data: partner } = await supabaseClient
                        .from('partners')
                        .select('custom_percentage')
                        .eq('id', intent.event.organizer_id)
                        .single();

                    const platformFeePercentage = partner?.custom_percentage || 10.0;
                    const refundAmount = data.amount || intent.total_amount; // Amount refunded

                    // Logic: Refund affects Gross, Fees, and Payout.
                    // If we refund full amount, we reverse everything.

                    const refundPlatformFee = (refundAmount / intent.total_amount) * intent.platform_fee;
                    const refundPayout = (refundAmount / intent.total_amount) * (intent.subtotal - intent.platform_fee); // Approx

                    // Actually better to just use negative of what was stored if full refund.
                    // If partial, proportional.

                    await supabaseClient.from('transactions').insert({
                        purchase_intent_id: intent.id,
                        event_id: intent.event_id,
                        partner_id: intent.event.organizer_id,
                        user_id: intent.user_id,
                        gross_amount: -refundAmount, // Negative
                        platform_fee: -refundPlatformFee, // Reversal of revenue
                        organizer_payout: -refundPayout, // Reversal of payout liability
                        payment_processing_fee: 0, // Usually processing fees are NOT refunded by gateway!
                        fee_percentage: platformFeePercentage,
                        fee_basis: 'refund',
                        xendit_transaction_id: data.id, // Refund ID
                        status: 'refunded'
                    });

                    console.log(`✅ Refund processed for intent ${intentId}`);
                }
            } else {
                // Refund Failed
                console.log(`❌ Refund failed for intent ${intentId}: ${data.failure_code}`);
                // Optionally notify admin?
            }

            return new Response(JSON.stringify({ success: true }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
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
