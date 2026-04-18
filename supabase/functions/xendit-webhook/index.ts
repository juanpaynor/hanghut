/**
 * ============================================================================
 * XENDIT WEBHOOK HANDLER — VERSION 31 (Queue-Based Side Effects)
 * ============================================================================
 *
 * WHAT CHANGED (v30 → v31):
 * -------------------------
 * 1. QUEUE-BASED SIDE EFFECTS — Push notifications, ticket emails, experience
 *    emails, and partner webhooks are now enqueued to `payment_side_effects`
 *    (pgmq) instead of being called synchronously. This reduces webhook
 *    response time from ~5-8s to ~300ms and prevents rate-limit issues
 *    at scale (5,000+ concurrent purchases).
 *
 * 2. NEW CONSUMER — `process-payment-queue` edge function reads the queue
 *    every 10s via pg_cron and processes side-effects with automatic retry.
 *
 * WHAT CHANGED (v29 → v30):
 * -------------------------
 * 1. RE-ENABLED WEBHOOK AUTH — x-callback-token verification is now enforced.
 *    Without this, anyone could send a fake payload and get free tickets.
 *
 * 2. IDEMPOTENCY GUARD — If an intent is already 'completed' or 'refunded',
 *    duplicate webhooks from Xendit retries are safely ignored (return 200).
 *    Prevents duplicate tickets, transactions, emails, and push notifications.
 *
 * 3. ROBUST extractPaymentMethod() — handles all Xendit API payload shapes:
 *    - Invoice API:          data.payment_channel (flat string)
 *    - Payment Request API:  data.payment_method (nested object)
 *    - Sessions API:         data.payments[0].payment_method (array)
 *    - Legacy:               data.payment_method (string)
 *
 * 4. ATOMIC tickets_sold DECREMENT — replaced read-then-write pattern with
 *    direct SQL decrement to prevent race conditions on concurrent webhooks.
 *
 * ============================================================================
 */

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { crypto } from "https://deno.land/std@0.168.0/crypto/mod.ts"

const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-callback-token',
}

/**
 * Extract the human-readable payment method from any Xendit webhook payload.
 *
 * Xendit sends payment_method in different shapes depending on the API:
 *  - Invoice API:          data.payment_channel (string, e.g. "GCASH")
 *  - Payment Request API:  data.payment_method (object with type + channel)
 *  - Sessions API:         data.payments[0].payment_method (object inside payments array)
 *  - Legacy:               data.payment_method (plain string)
 */
function extractPaymentMethod(data: any): string {
    // 1. Invoice / Legacy — flat string field
    if (data.payment_channel) {
        return String(data.payment_channel).toUpperCase()
    }

    // 2. Direct channel_code at top level
    if (data.channel_code) {
        return String(data.channel_code).toUpperCase()
    }

    // Helper: pull channel_code out of a nested payment_method object
    function extractFromPmObject(pm: any): string | null {
        if (!pm || typeof pm !== 'object') return null
        return (
            pm.ewallet?.channel_code ||
            pm.direct_debit?.channel_code ||
            pm.card?.channel_code ||
            pm.qr_code?.channel_code ||
            pm.virtual_account?.channel_code ||
            pm.retail_outlet?.channel_code ||
            pm.over_the_counter?.channel_code ||
            pm.type ||  // fallback to generic type like "EWALLET"
            null
        )
    }

    // 3. Payment Request / direct payment_method object
    if (data.payment_method) {
        const pm = data.payment_method
        if (typeof pm === 'string') {
            return pm.toUpperCase()
        }
        const extracted = extractFromPmObject(pm)
        if (extracted) return String(extracted).toUpperCase()
    }

    // 4. Sessions API — payment method inside payments array
    if (data.payments && Array.isArray(data.payments) && data.payments.length > 0) {
        const firstPayment = data.payments[0]

        // payments[].payment_method
        if (firstPayment.payment_method) {
            const pm = firstPayment.payment_method
            if (typeof pm === 'string') return pm.toUpperCase()
            const extracted = extractFromPmObject(pm)
            if (extracted) return String(extracted).toUpperCase()
        }

        // payments[].channel_code (some payload shapes)
        if (firstPayment.channel_code) {
            return String(firstPayment.channel_code).toUpperCase()
        }

        // payments[].payment_channel
        if (firstPayment.payment_channel) {
            return String(firstPayment.payment_channel).toUpperCase()
        }
    }

    // 5. actions[] fallback (some Session payloads include this)
    if (data.actions && Array.isArray(data.actions) && data.actions.length > 0) {
        const action = data.actions[0]
        if (action.payment_method) {
            const extracted = extractFromPmObject(action.payment_method)
            if (extracted) return String(extracted).toUpperCase()
        }
    }

    return 'UNKNOWN'
}

serve(async (req) => {
    console.log('🚨 WEBHOOK RECEIVED - VERSION 31 (QUEUE-BASED SIDE EFFECTS) 🚨')

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

        // ==========================================
        // 🔒 WEBHOOK AUTH (v30: RE-ENABLED)
        // ==========================================
        // This verifies the request is genuinely from Xendit, NOT from an attacker.
        // This has NOTHING to do with user auth or guest checkout — it's server-to-server.
        const callbackToken = req.headers.get('x-callback-token')
        const webhookToken = Deno.env.get('XENDIT_WEBHOOK_TOKEN')

        console.log(`🔒 Auth: Header=${callbackToken ? 'Present' : 'Missing'}, Env=${webhookToken ? 'Present' : 'Missing'}`)

        if (!webhookToken) {
            console.error('CRITICAL: XENDIT_WEBHOOK_TOKEN is not set in environment variables')
            return new Response('Server Configuration Error', { status: 500 })
        }

        if (callbackToken !== webhookToken) {
            console.error('🚫 WEBHOOK AUTH FAILED: Invalid or missing x-callback-token')
            return new Response(
                JSON.stringify({ error: 'Unauthorized' }),
                { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
            )
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
            const lookupId = reference_id || data?.external_id || payload.external_id;

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
                // Not a regular event ticket. Check if it's an experience booking!
                if (lookupId && lookupId.startsWith('exp_')) {
                    console.log(`🔍 Checking if ${lookupId} is an Experience Intent...`);
                    const { data: expIntent, error: expError } = await supabaseClient
                        .from('experience_purchase_intents')
                        .select('id, status')
                        .eq('xendit_external_id', lookupId)
                        .single()

                    if (expIntent) {
                        // ==========================================
                        // 🛡️ IDEMPOTENCY: Experience (v30)
                        // ==========================================
                        if (expIntent.status === 'completed' || expIntent.status === 'refunded') {
                            console.log(`⚡ Experience intent ${expIntent.id} already ${expIntent.status}, skipping duplicate webhook`)
                            return new Response(
                                JSON.stringify({ success: true, message: `Already ${expIntent.status}` }),
                                { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
                            )
                        }

                        console.log(`✅ Found Experience Intent: ${expIntent.id}. Confirming...`)
                        // Extract payment method using robust helper
                        const expMethod = extractPaymentMethod(data);
                        console.log(`💳 Experience Payment Method: ${expMethod}`);

                        const { data: rpcResult, error: rpcError } = await supabaseClient.rpc('confirm_experience_booking', {
                            p_intent_id: expIntent.id,
                            p_payment_method: expMethod,
                            p_xendit_id: data.id || data.payment_id || lookupId
                        });

                        if (rpcError) {
                            console.error('❌ Experience RPC Error:', rpcError)
                            throw new Error(rpcError.message)
                        }

                        console.log('🎉 Experience Booking Confirmed:', rpcResult)

                        // 📬 Enqueue experience confirmation email for async processing
                        try {
                            console.log('📬 Enqueuing experience confirmation email...')

                            const { data: fullExpIntent } = await supabaseClient
                                .from('experience_purchase_intents')
                                .select('*')
                                .eq('id', expIntent.id)
                                .single()

                            if (fullExpIntent) {
                                const { data: tableInfo } = await supabaseClient
                                    .from('tables')
                                    .select('title, location_name, host_id, image_url')
                                    .eq('id', fullExpIntent.table_id)
                                    .single()

                                let hostName = 'Host'
                                if (tableInfo?.host_id) {
                                    const { data: host } = await supabaseClient
                                        .from('users')
                                        .select('display_name, full_name')
                                        .eq('id', tableInfo.host_id)
                                        .single()
                                    hostName = host?.display_name || host?.full_name || 'Host'
                                }

                                let recipientEmail = fullExpIntent.guest_email
                                let recipientName = fullExpIntent.guest_name
                                if (!recipientEmail && fullExpIntent.user_id) {
                                    const { data: userInfo } = await supabaseClient
                                        .from('users')
                                        .select('email, display_name, full_name')
                                        .eq('id', fullExpIntent.user_id)
                                        .single()
                                    recipientEmail = userInfo?.email
                                    recipientName = recipientName || userInfo?.display_name || userInfo?.full_name
                                }

                                let experienceDate = fullExpIntent.created_at
                                if (fullExpIntent.schedule_id) {
                                    const { data: schedule } = await supabaseClient
                                        .from('experience_schedules')
                                        .select('start_time')
                                        .eq('id', fullExpIntent.schedule_id)
                                        .single()
                                    if (schedule) experienceDate = schedule.start_time
                                }

                                if (recipientEmail) {
                                    const { error: queueError } = await supabaseClient
                                        .rpc('pgmq_send', {
                                            queue_name: 'payment_side_effects',
                                            message: {
                                                type: 'send_experience_email',
                                                data: {
                                                    email: recipientEmail,
                                                    name: recipientName,
                                                    experience_title: tableInfo?.title || 'Experience',
                                                    experience_venue: tableInfo?.location_name || 'Venue',
                                                    experience_date: experienceDate,
                                                    host_name: hostName,
                                                    quantity: fullExpIntent.quantity || 1,
                                                    total_amount: fullExpIntent.total_amount,
                                                    transaction_ref: fullExpIntent.xendit_external_id || fullExpIntent.id,
                                                    payment_method: expMethod,
                                                    intent_id: fullExpIntent.id,
                                                    cover_image_url: tableInfo?.image_url,
                                                },
                                            },
                                        })
                                    if (queueError) {
                                        console.error('⚠️ Failed to enqueue experience email:', queueError)
                                    } else {
                                        console.log('📬 Experience confirmation email enqueued')
                                    }
                                }
                            }
                        } catch (emailErr) {
                            console.error('⚠️ Email enqueue failed (non-critical):', emailErr)
                        }

                        return new Response(JSON.stringify({ success: true, message: 'Experience confirmed' }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
                    }
                }

                console.log('Purchase intent not found (likely a test webhook):', lookupId)
                // Return 200 to satisfy Xendit "Test and save" verification
                return new Response(JSON.stringify({ message: 'Webhook received but intent not found (Test passed)' }), {
                    status: 200,
                    headers: { ...corsHeaders, 'Content-Type': 'application/json' }
                })
            }

            // ==========================================
            // 🛡️ IDEMPOTENCY GUARD (v30: NEW)
            // ==========================================
            // Xendit retries webhooks up to 5x. Without this guard, retries
            // would create duplicate tickets, transactions, emails, and pushes.
            if (intent.status === 'completed' || intent.status === 'refunded') {
                console.log(`⚡ Intent ${intent.id} already ${intent.status}, skipping duplicate webhook`)
                return new Response(
                    JSON.stringify({ success: true, message: `Already ${intent.status}` }),
                    { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
                )
            }

            console.log('Payment successful for intent:', intent.id)

            // ==========================================
            // 💳 EXTRACT PAYMENT METHOD (v30: ROBUST)
            // ==========================================
            const capturedMethod = extractPaymentMethod(data);
            console.log(`💳 Extracted Payment Method: ${capturedMethod}`);
            console.log(`💳 Raw payment_method field:`, JSON.stringify(data.payment_method));
            console.log(`💳 Raw payments array:`, JSON.stringify(data.payments));
            console.log(`💳 Raw payment_channel:`, data.payment_channel);

            // Update purchase intent
            await supabaseClient
                .from('purchase_intents')
                .update({
                    status: 'completed',
                    // NOTE: Do NOT use `created` — for Sessions API, it's session creation time, not payment time.
                    // Use `data.updated` (Xendit completion timestamp) or webhook receive time as fallback.
                    paid_at: data.updated || data.payments?.[0]?.created || new Date().toISOString(),
                    payment_method: capturedMethod,
                })
                .eq('id', intent.id)

            // Record transaction (Create transaction BEFORE tickets to ensure accounting)
            const { data: partner } = await supabaseClient
                .from('partners')
                .select('id, custom_percentage, fixed_fee_per_ticket, pass_fees_to_customer')
                .eq('id', intent.event.organizer_id)
                .single()

            // Use ?? instead of || so that 0% fee partners are handled correctly
            const platformFeePercentage = partner?.custom_percentage ?? 4.0
            const platformFee = Math.round((intent.subtotal * platformFeePercentage) / 100)
            const processingFee = intent.payment_processing_fee || 0
            const fixedFeePerTicket = partner?.fixed_fee_per_ticket ?? 15.0
            const totalFixedFee = fixedFeePerTicket * (intent.quantity || 1)
            const organizerPayout = intent.subtotal - platformFee - totalFixedFee

            console.log(`💰 Fee calc: subtotal=${intent.subtotal}, pct=${platformFeePercentage}%, platformFee=${platformFee}, fixedFee=${totalFixedFee} (${fixedFeePerTicket}×${intent.quantity}), organizerPayout=${organizerPayout}`)

            const { error: txError } = await supabaseClient
                .from('transactions')
                .insert({
                    purchase_intent_id: intent.id,
                    event_id: intent.event_id,
                    partner_id: intent.event.organizer_id,
                    user_id: intent.user_id || null,
                    gross_amount: intent.subtotal,
                    platform_fee: platformFee,
                    payment_processing_fee: processingFee,
                    fixed_fee: totalFixedFee,
                    organizer_payout: organizerPayout,
                    fee_percentage: platformFeePercentage,
                    fee_basis: (partner?.custom_percentage != null && partner.custom_percentage !== 4.0) ? 'custom' : 'standard',
                    xendit_transaction_id: payment_request_id || payment_id || data.id,
                    status: 'completed',
                })

            if (txError) {
                console.error(`❌ Transaction insert failed for intent ${intent.id}:`, txError)
            } else {
                console.log(`✅ Recorded transaction for intent ${intent.id}`)
            }

            // Issue tickets using the RPC function (Single Source of Truth)
            console.log(`🎟️ Issuing tickets for intent ${intent.id} via RPC...`)
            const { data: generatedTickets, error: issueError } = await supabaseClient.rpc('issue_tickets', {
                p_intent_id: intent.id
            })

            if (issueError) {
                console.error('❌ Failed to issue tickets:', issueError)
            } else {
                console.log(`✅ Successfully issued ${generatedTickets?.length ?? 0} tickets`)

                // ==========================================
                // 📬 ENQUEUE SIDE-EFFECTS (v31: QUEUE-BASED)
                // ==========================================
                // Instead of calling functions synchronously (which blocks the
                // webhook response for 5-8s), we enqueue messages for async
                // processing. This lets us return 200 to Xendit in ~300ms.

                const sideEffects: any[] = []

                // 1. Push notification to organizer
                const buyerName = intent.guest_name || intent.user?.full_name || 'Someone';
                const eventTitle = intent.event?.title || 'your event';
                const qty = intent.quantity || 1;

                const { data: partnerData } = await supabaseClient
                    .from('partners')
                    .select('user_id')
                    .eq('id', intent.event.organizer_id)
                    .single();

                if (partnerData?.user_id) {
                    sideEffects.push({
                        type: 'send_push',
                        data: {
                            user_id: partnerData.user_id,
                            title: '🎟️ New Ticket Purchase!',
                            body: `${buyerName} just bought ${qty} ticket${qty > 1 ? 's' : ''} for ${eventTitle}`,
                            image: intent.event?.cover_image_url || null,
                            data: { type: 'ticket_purchase', event_id: intent.event_id },
                        },
                    })
                }

                // 2. Partner webhook (ticket.purchased)
                sideEffects.push({
                    type: 'partner_webhook',
                    data: {
                        event_type: 'ticket.purchased',
                        event_id: intent.event_id,
                        payload: {
                            ticket_count: intent.quantity,
                            total_amount: intent.total_amount,
                            payment_method: capturedMethod,
                            customer: {
                                name: intent.guest_name || intent.user?.full_name,
                                email: intent.guest_email || intent.user?.email,
                            },
                        },
                    },
                })

                // 3. Ticket confirmation email
                const recipientEmail = intent.guest_email || intent.user?.email
                const recipientName = intent.guest_name || intent.user?.full_name

                if (recipientEmail && generatedTickets && generatedTickets.length > 0) {
                    sideEffects.push({
                        type: 'send_ticket_email',
                        data: {
                            email: recipientEmail,
                            name: recipientName,
                            event_title: intent.event?.title || 'Event',
                            event_venue: intent.event?.venue_name || 'Venue',
                            event_date: intent.event?.start_datetime,
                            event_cover_image: intent.event?.cover_image_url,
                            ticket_quantity: intent.quantity,
                            total_amount: intent.total_amount,
                            transaction_ref: intent.xendit_external_id || intent.id,
                            payment_method: capturedMethod,
                            tickets: generatedTickets,
                        },
                    })
                }

                // Enqueue all side-effects in a single batch
                for (const effect of sideEffects) {
                    const { error: queueError } = await supabaseClient
                        .rpc('pgmq_send', {
                            queue_name: 'payment_side_effects',
                            message: effect,
                        })
                    if (queueError) {
                        console.error(`⚠️ Failed to enqueue ${effect.type}:`, queueError)
                    }
                }
                console.log(`📬 Enqueued ${sideEffects.length} side-effects for async processing`)
            }

            return new Response(
                JSON.stringify({ success: true, tickets_issued: intent.quantity }),
                { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
            )
        }

        // Handle payment failure
        if (eventType === 'payment.failed' || eventType === 'payment_request.expired') {
            const external_id = payload.external_id || payload.data?.reference_id || payload.reference_id

            const { data: intent } = await supabaseClient
                .from('purchase_intents')
                .select('*, event:events(tickets_sold)')
                .eq('xendit_external_id', external_id)
                .single()

            if (intent) {
                // Idempotency: skip if already handled
                if (intent.status === 'failed' || intent.status === 'expired' || intent.status === 'completed') {
                    console.log(`⚡ Intent ${intent.id} already ${intent.status}, skipping`)
                    return new Response(
                        JSON.stringify({ success: true, message: `Already ${intent.status}` }),
                        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
                    )
                }

                console.log('Payment failed/expired for intent:', intent.id)

                // Mark intent as failed/expired
                await supabaseClient
                    .from('purchase_intents')
                    .update({ status: eventType === 'payment.failed' ? 'failed' : 'expired' })
                    .eq('id', intent.id)

                // Release reserved capacity (atomic decrement to avoid race conditions)
                await supabaseClient.rpc('atomic_decrement_tickets_sold', {
                    p_event_id: intent.event_id,
                    p_quantity: intent.quantity
                }).then(({ error }) => {
                    if (error) {
                        // Fallback to direct update if RPC doesn't exist yet
                        console.warn('⚠️ atomic_decrement_tickets_sold RPC not found, using direct update:', error.message)
                        return supabaseClient
                            .from('events')
                            .update({ tickets_sold: Math.max(0, intent.event.tickets_sold - intent.quantity) })
                            .eq('id', intent.event_id)
                    }
                })

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
            }

            const { error: updateError } = await supabaseClient
                .from('payouts')
                .update(updatePayload)
                .eq('id', reference_id);

            if (updateError) {
                console.error(`❌ Failed to update payout ${reference_id}:`, updateError);
                return new Response(JSON.stringify({ error: updateError.message }), { status: 500, headers: corsHeaders });
            }

            // 🔧 FIX: When payout fails, unlink transactions so funds become available again
            if (newStatus === 'failed') {
                console.log(`🔓 Unlinking transactions from failed payout ${reference_id}...`);

                const { error: unlinkEventErr } = await supabaseClient
                    .from('transactions')
                    .update({ payout_id: null })
                    .eq('payout_id', reference_id);

                if (unlinkEventErr) {
                    console.error(`⚠️ Failed to unlink event transactions:`, unlinkEventErr);
                }

                const { error: unlinkExpErr } = await supabaseClient
                    .from('experience_transactions')
                    .update({ payout_id: null })
                    .eq('payout_id', reference_id);

                if (unlinkExpErr) {
                    console.error(`⚠️ Failed to unlink experience transactions:`, unlinkExpErr);
                }

                console.log(`✅ Transactions unlinked from failed payout ${reference_id}`);
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

            if (!intentId) {
                console.error('Refund event missing metadata.intent_id');
                return new Response(JSON.stringify({ message: 'Missing intent_id in metadata' }), { status: 200, headers: corsHeaders });
            }

            if (eventType === 'refund.succeeded') {
                const intentType = data.metadata?.intent_type || 'event';

                if (intentType === 'experience') {
                    // --- EXPERIENCE REFUND LOGIC ---

                    // Idempotency check
                    const { data: expCheck } = await supabaseClient
                        .from('experience_purchase_intents')
                        .select('status')
                        .eq('id', intentId)
                        .single()

                    if (expCheck?.status === 'refunded') {
                        console.log(`⚡ Experience intent ${intentId} already refunded, skipping`)
                        return new Response(
                            JSON.stringify({ success: true, message: 'Already refunded' }),
                            { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
                        )
                    }

                    // 1. Mark Experience Intent as Refunded
                    await supabaseClient
                        .from('experience_purchase_intents')
                        .update({ status: 'refunded' })
                        .eq('id', intentId);

                    // 2. Retrieve Intent Details
                    const { data: intent } = await supabaseClient
                        .from('experience_purchase_intents')
                        .select('*, experience:tables!table_id(host_id, partner_id)')
                        .eq('id', intentId)
                        .single();

                    if (intent) {
                        // 3. Record Negative Transaction (Accounting)
                        const refundAmount = data.amount || intent.total_amount;

                        const { data: origTx } = await supabaseClient
                            .from('experience_transactions')
                            .select('*')
                            .eq('purchase_intent_id', intentId)
                            .maybeSingle();

                        if (origTx) {
                            const ratio = refundAmount / intent.total_amount;
                            await supabaseClient.from('experience_transactions').insert({
                                purchase_intent_id: intent.id,
                                table_id: intent.table_id,
                                host_id: intent.experience.host_id,
                                user_id: intent.user_id,
                                gross_amount: -(origTx.gross_amount * ratio),
                                platform_fee: -(origTx.platform_fee * ratio),
                                host_payout: -(origTx.host_payout * ratio),
                                xendit_transaction_id: data.id, // Refund ID
                                status: 'refunded',
                                partner_id: origTx.partner_id // Keep partner_id link
                            });
                        }
                        console.log(`✅ Experience refund processed for intent ${intentId}`);
                    }
                } else {
                    // --- EVENT REFUND LOGIC ---

                    // Idempotency check
                    const { data: eventCheck } = await supabaseClient
                        .from('purchase_intents')
                        .select('status')
                        .eq('id', intentId)
                        .single()

                    if (eventCheck?.status === 'refunded') {
                        console.log(`⚡ Intent ${intentId} already refunded, skipping`)
                        return new Response(
                            JSON.stringify({ success: true, message: 'Already refunded' }),
                            { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
                        )
                    }

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
                        // 3. Release Capacity (atomic decrement)
                        await supabaseClient.rpc('atomic_decrement_tickets_sold', {
                            p_event_id: intent.event_id,
                            p_quantity: intent.quantity
                        }).then(({ error }) => {
                            if (error) {
                                console.warn('⚠️ atomic_decrement_tickets_sold RPC not found, using direct update:', error.message)
                                return supabaseClient.from('events')
                                    .update({ tickets_sold: Math.max(0, intent.event.tickets_sold - intent.quantity) })
                                    .eq('id', intent.event_id)
                            }
                        })

                        // 4. Record Negative Transaction (Accounting)
                        const { data: partner } = await supabaseClient
                            .from('partners')
                            .select('custom_percentage')
                            .eq('id', intent.event.organizer_id)
                            .single();

                        // Use ?? for null-coalescing (0% is valid)
                        const platformFeePercentage = partner?.custom_percentage ?? 4.0;
                        const refundAmount = data.amount || intent.total_amount;

                        // Look up the original transaction for accurate reversal
                        const { data: origTx } = await supabaseClient
                            .from('transactions')
                            .select('platform_fee, organizer_payout, fixed_fee, gross_amount')
                            .eq('purchase_intent_id', intent.id)
                            .eq('status', 'completed')
                            .single();

                        // Calculate proportional reversal based on original transaction
                        const ratio = origTx ? (refundAmount / origTx.gross_amount) : (refundAmount / intent.total_amount);
                        const refundPlatformFee = origTx ? Math.round(origTx.platform_fee * ratio) : Math.round((refundAmount * platformFeePercentage) / 100);
                        const refundFixedFee = origTx ? Math.round((origTx.fixed_fee || 0) * ratio) : 0;
                        const refundPayout = origTx ? Math.round(origTx.organizer_payout * ratio) : (refundAmount - refundPlatformFee);

                        console.log(`💰 Refund calc: amount=${refundAmount}, ratio=${ratio.toFixed(2)}, platformFee=${refundPlatformFee}, fixedFee=${refundFixedFee}, payout=${refundPayout}`);

                        const { error: refundTxError } = await supabaseClient.from('transactions').insert({
                            purchase_intent_id: intent.id,
                            event_id: intent.event_id,
                            partner_id: intent.event.organizer_id,
                            user_id: intent.user_id || null,
                            gross_amount: -refundAmount,
                            platform_fee: -refundPlatformFee,
                            fixed_fee: -refundFixedFee,
                            organizer_payout: -refundPayout,
                            payment_processing_fee: 0,
                            fee_percentage: platformFeePercentage,
                            fee_basis: 'refund',
                            xendit_transaction_id: data.id,
                            status: 'refunded'
                        });

                        if (refundTxError) {
                            console.error(`❌ Refund transaction insert failed for intent ${intentId}:`, refundTxError)
                        } else {
                            console.log(`✅ Refund processed for intent ${intentId}`);
                        }

                        // 📬 Enqueue partner webhook (ticket.refunded) for async processing
                        try {
                            const { error: queueError } = await supabaseClient
                                .rpc('pgmq_send', {
                                    queue_name: 'payment_side_effects',
                                    message: {
                                        type: 'partner_webhook',
                                        data: {
                                            event_type: 'ticket.refunded',
                                            event_id: intent.event_id,
                                            payload: {
                                                intent_id: intentId,
                                                refund_amount: data.amount || intent.total_amount,
                                            },
                                        },
                                    },
                                })
                            if (queueError) {
                                console.error('⚠️ Failed to enqueue refund webhook:', queueError)
                            } else {
                                console.log('📬 Refund partner webhook enqueued')
                            }
                        } catch (webhookErr) {
                            console.error('⚠️ Refund webhook enqueue failed (non-critical):', webhookErr);
                        }
                    }
                }
            } else {
                // Refund Failed
                console.log(`❌ Refund failed for intent ${intentId}: ${data.failure_code}`);
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
