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

        // Parse request body
        const { event_id, quantity, tier_id, promo_code, channel_code, guest_details, success_url, failure_url, subscribed_to_newsletter, registration_id, metadata: clientMetadata } = await req.json()

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

        // Validate basic input
        if (!event_id || !quantity || quantity < 1) {
            return new Response(
                JSON.stringify({
                    success: false,
                    error: { code: 'VALIDATION_ERROR', message: 'Invalid event_id or quantity' }
                }),
                { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
            )
        }

        // --- APPROVAL GATE (server-side enforcement) ---
        // require_approval events MUST have an APPROVED event_registrations row
        // before any ticket is reserved or issued. The app gates this client-side
        // (submit_event_request → "pending" → stop), but a server guard is the only
        // thing that stops a caller which skips registration entirely (e.g. the web
        // checkout). Registration creation itself stays in submit_event_request RPC —
        // we only VERIFY here, never create.
        const { data: gateEvent, error: gateError } = await supabaseClient
            .from('events')
            .select('require_approval')
            .eq('id', event_id)
            .single()

        if (gateError || !gateEvent) {
            return new Response(
                JSON.stringify({ success: false, error: { code: 'VALIDATION_ERROR', message: 'Invalid Event' } }),
                { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
            )
        }

        if (gateEvent.require_approval) {
            // Must reference a registration
            if (!registration_id) {
                return new Response(
                    JSON.stringify({
                        success: false,
                        error: { code: 'REGISTRATION_REQUIRED', message: 'This event requires approval. Submit a registration request before purchasing.' }
                    }),
                    { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
                )
            }

            const { data: reg, error: regError } = await supabaseClient
                .from('event_registrations')
                .select('id, status, event_id, user_id, guest_email')
                .eq('id', registration_id)
                .single()

            // Must exist and belong to this event
            if (regError || !reg || reg.event_id !== event_id) {
                return new Response(
                    JSON.stringify({
                        success: false,
                        error: { code: 'REGISTRATION_INVALID', message: 'Registration not found for this event.' }
                    }),
                    { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
                )
            }

            // Must belong to this caller (prevents using someone else's approval)
            const ownsRegistration = user
                ? reg.user_id === user.id
                : (!!reg.guest_email && reg.guest_email.toLowerCase() === (guest_details?.email ?? '').toLowerCase())

            if (!ownsRegistration) {
                return new Response(
                    JSON.stringify({
                        success: false,
                        error: { code: 'REGISTRATION_INVALID', message: 'Registration does not match this account.' }
                    }),
                    { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
                )
            }

            // Must be approved (organizer-approved; 'auto_approved' is for non-approval events)
            if (reg.status !== 'approved') {
                const code = reg.status === 'pending'
                    ? 'REGISTRATION_PENDING'
                    : reg.status === 'rejected'
                        ? 'REGISTRATION_REJECTED'
                        : 'REGISTRATION_NOT_APPROVED'
                return new Response(
                    JSON.stringify({
                        success: false,
                        error: { code, message: `Registration is ${reg.status}. Payment is only allowed after the organizer approves.` }
                    }),
                    { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
                )
            }
            // approved → fall through to normal reserve / payment / issue flow
        }

        // --- PRICING LOGIC ---
        let unitPrice = 0
        let tierName = 'General Admission'
        let organizerId = null

        if (tier_id) {
            // Fetch Tier Price AND Organizer ID via Event relation
            const { data: tier, error: tierError } = await supabaseClient
                .from('ticket_tiers')
                .select('price, name, quantity_sold, quantity_total, events(organizer_id)')
                .eq('id', tier_id)
                .eq('event_id', event_id)
                .single()

            if (tierError || !tier) {
                return new Response(JSON.stringify({ success: false, error: { message: 'Invalid Ticket Tier' } }), { status: 400, headers: corsHeaders })
            }

            // Check Tier Capacity
            if (tier.quantity_sold + quantity > tier.quantity_total) {
                return new Response(JSON.stringify({ success: false, error: { message: 'Selected ticket tier is sold out' } }), { status: 400, headers: corsHeaders })
            }

            unitPrice = tier.price
            tierName = tier.name
            // @ts-ignore
            organizerId = tier.events?.organizer_id
        } else {
            // Fallback to Event Price (Legacy / Simple Events)
            const { data: event, error: eventError } = await supabaseClient
                .from('events')
                .select('ticket_price, organizer_id')
                .eq('id', event_id)
                .single()

            if (eventError || !event) {
                return new Response(JSON.stringify({ success: false, error: { message: 'Invalid Event' } }), { status: 400, headers: corsHeaders })
            }
            unitPrice = event.ticket_price
            organizerId = event.organizer_id
        }

        // --- FETCH PLATFORM FEE ---
        let platformFeePercentage = 4.0 // Default 4% (processing baseline)
        // First-party partners settle directly to the main Xendit account
        // (no sub-account, no split rule, no PLATFORM fee override).
        let useMainWallet = false
        // Cards + GCash require Xendit to have ACTIVATED the capabilities on the
        // sub-account (account_holder.capabilities.status:live) — which only happens
        // after KYC passes. xendit_cards_gcash_live is the true signal; gating on
        // kyc_status='verified' alone would offer them before they're actually live.
        let organizerCardsGcashLive = false
        if (organizerId) {
            const { data: partner } = await supabaseClient
                .from('partners')
                .select('custom_percentage, pass_fees_to_customer, fixed_fee_per_ticket, xendit_account_id, split_rule_id, use_main_wallet, xendit_cards_gcash_live')
                .eq('id', organizerId)
                .single()

            useMainWallet = partner?.use_main_wallet === true
            organizerCardsGcashLive = partner?.xendit_cards_gcash_live === true

            // Check if distinct custom_percentage exists (it might be 0, so check undefined/null)
            if (partner && partner.custom_percentage !== null && partner.custom_percentage !== undefined) {
                platformFeePercentage = partner.custom_percentage
            }

            // --- PASS FEES LOGIC ---
            // Guard with unitPrice > 0 — free events have no booking fee.
            // Without this guard, a free event with pass_fees_to_customer=true
            // would compute totalAmount = fixedFee, skipping the free-event short-circuit
            // and either charging the customer or 500ing at Xendit.
            if (partner && partner.pass_fees_to_customer && unitPrice > 0) {
                // Split Fee Model: Customer pays Ticket Price + Fixed Fee
                // Organizer absorbs Percentage Fee + Processing Fee
                const subtotal = unitPrice * quantity

                // Fixed Fee (what customer pays on top of ticket price)
                const fixedFee = (partner.fixed_fee_per_ticket || 15.00) * quantity

                // Deductible Fees (calculated on BASE price, absorbed by organizer)
                const platformFee = subtotal * (platformFeePercentage / 100)
                const processingFee = subtotal * 0.04 // 4% of BASE PRICE (updated from 3%)

                // Store calculation specifics for later use
                // @ts-ignore
                req.feeDetails = {
                    passFees: true,
                    fixedFee,
                    platformFee,
                    processingFee,
                    basePrice: subtotal
                }
            }
        }

        // --- PROMO CODE LOGIC ---
        let discountAmount = 0
        let promoCodeId = null

        if (promo_code) {
            const { data: promo, error: promoError } = await supabaseClient
                .from('promo_codes')
                .select('*')
                .eq('event_id', event_id)
                .eq('code', promo_code.toUpperCase())
                .eq('is_active', true)
                .single()

            if (promo) {
                // Check Limits (Expiry / Usage)
                const now = new Date()
                if (promo.expires_at && new Date(promo.expires_at) < now) {
                    return new Response(JSON.stringify({ success: false, error: { message: 'Promo code expired' } }), { status: 400, headers: corsHeaders })
                }
                if (promo.usage_limit && promo.usage_count >= promo.usage_limit) {
                    return new Response(JSON.stringify({ success: false, error: { message: 'Promo code usage limit reached' } }), { status: 400, headers: corsHeaders })
                }

                promoCodeId = promo.id

                // Calculate Discount
                const subtotal = unitPrice * quantity
                if (promo.discount_type === 'percentage') {
                    discountAmount = subtotal * (promo.discount_amount / 100)
                } else {
                    discountAmount = promo.discount_amount // Fixed amount
                }

                // Cap discount at subtotal
                if (discountAmount > subtotal) discountAmount = subtotal
            } else {
                return new Response(JSON.stringify({ success: false, error: { message: 'Invalid Promo Code' } }), { status: 400, headers: corsHeaders })
            }
        }

        const { data: intentData, error: reserveError } = await supabaseClient.rpc(
            'reserve_tickets',
            {
                p_event_id: event_id,
                p_user_id: user?.id ?? null,
                p_quantity: quantity,
                p_guest_email: guest_details?.email ?? user?.email ?? null,
                p_guest_name: guest_details?.name ?? userProfile?.full_name ?? null,
                p_guest_phone: guest_details?.phone ?? userProfile?.phone ?? null,
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

        // --- SUBSCRIBER DISCOUNT ---
        // Price order: base → subscriber discount → promo code → booking fee.
        // We verify server-side (never trust the client amount). Guest checkouts
        // can't have a subscription so we skip entirely for non-authenticated users.
        let subscriberDiscountAmount = 0
        let subscriberDiscountMeta: Record<string, unknown> = {}

        if (user && clientMetadata?.has_subscriber_discount === true) {
            try {
                const { data: discountResult } = await supabaseClient.rpc(
                    'get_subscriber_event_discount',
                    { p_event_id: event_id }
                )

                if (discountResult?.has_discount === true) {
                    // Discount applies to min(quantity, max_tickets) tickets
                    const eligibleQty = Math.min(quantity, discountResult.max_tickets ?? 1)
                    const saving = Math.round((unitPrice - discountResult.discounted_price) * eligibleQty)
                    if (saving > 0) {
                        subscriberDiscountAmount = saving
                        subscriberDiscountMeta = {
                            applied: true,
                            saving,
                            discounted_price: discountResult.discounted_price,
                            original_price: discountResult.original_price,
                            eligible_tickets: eligibleQty,
                            tier_id: discountResult.subscription_tier_id,
                        }
                        console.log(`👑 Subscriber discount applied: -₱${saving} (${eligibleQty}× tickets, tier ${discountResult.subscription_tier_id})`)
                    }
                } else if (discountResult?.has_discount === false) {
                    // Sub expired mid-checkout — honour the price the user was shown.
                    // Fall back to the client-sent saving so they aren't overcharged.
                    const fallbackSaving = Number(clientMetadata?.subscriber_saving ?? 0)
                    if (fallbackSaving > 0) {
                        subscriberDiscountAmount = fallbackSaving
                        subscriberDiscountMeta = {
                            applied: true,
                            saving: fallbackSaving,
                            fallback: true, // subscription lapsed between page load and checkout
                        }
                        console.log(`👑 Subscriber discount fallback (sub lapsed): -₱${fallbackSaving}`)
                    }
                }
            } catch (e) {
                // Non-fatal — proceed without subscriber discount rather than blocking payment
                console.warn('⚠️ Subscriber discount check failed (non-fatal):', e)
            }
        }

        // --- UPDATE INTENT WITH PRICING & TIER INFO ---
        const subtotal = unitPrice * quantity
        // Subscriber discount applies after promo code
        const totalDiscount = discountAmount + subscriberDiscountAmount
        let platformFee = (subtotal - totalDiscount) * (platformFeePercentage / 100)
        // Customer pays ticket price only. Platform fee is deducted from organizer payout via Xendit fees override (see sessionBody.fees).
        let totalAmount = subtotal - totalDiscount
        let feeMetadata: Record<string, unknown> = {}

        // Override if Pass Fees is enabled (will only be set when unitPrice > 0,
        // see the guard in the pass-fees block above)
        // @ts-ignore
        if (req.feeDetails?.passFees && unitPrice > 0) {
            // @ts-ignore
            const details = req.feeDetails

            // Split Fee Model: 
            // - Customer pays: Subtotal + Fixed Fee
            // - Organizer absorbs: Platform Fee + Processing Fee
            // 
            // NOTE: Even though the Total Amount (Gross) is `ticketPrice + FixedFee`,
            // we calculate the Deductible Fees based on the **BASE Ticket Price**
            // to match the organizer's simplified view.
            // The Platform (HangHut) will absorb the small variance incurred by 
            // Xendit charging on the Gross Amount.

            // Total = Subtotal + Fixed Fees ONLY (what customer pays)
            totalAmount = subtotal + details.fixedFee

            // Platform Fee is what the platform earns (deducted from organizer payout)
            platformFee = details.platformFee

            feeMetadata = {
                pass_fees: true,
                platform_fee: details.platformFee,
                fixed_fee: details.fixedFee,
                processing_fee: details.processingFee,
                base_price: subtotal
            }
        }

        console.log(`Updating Intent ${intentId}: Tier=${tierName}, Promo=${promo_code}, SubDiscount=${subscriberDiscountAmount}, Total=${totalAmount}, Fee%=${platformFeePercentage}`)

        const combinedMetadata = {
            ...(Object.keys(feeMetadata).length > 0 ? feeMetadata : {}),
            ...(Object.keys(subscriberDiscountMeta).length > 0 ? { subscriber_discount: subscriberDiscountMeta } : {}),
        }

        const { error: updateError } = await supabaseAdmin // Use Admin to bypass RLS
            .from('purchase_intents')
            .update({
                tier_id: tier_id ?? null,
                promo_code_id: promoCodeId,
                unit_price: unitPrice,
                subtotal: subtotal,
                discount_amount: discountAmount + subscriberDiscountAmount,
                platform_fee: platformFee,
                total_amount: totalAmount,
                pricing_note: `Tier: ${tierName}${promo_code ? ' | Promo: ' + promo_code : ''}${subscriberDiscountAmount > 0 ? ' | Subscriber discount: -₱' + subscriberDiscountAmount : ''}`,
                fee_percentage: platformFeePercentage,
                subscribed_to_newsletter: subscribed_to_newsletter ?? false,
                metadata: Object.keys(combinedMetadata).length > 0 ? combinedMetadata : null
            })
            .eq('id', intentId)

        if (updateError) {
            console.error('Failed to update intent pricing:', updateError)
            throw new Error('Failed to update intent pricing details')
        }


        // Fetch the created purchase intent using Admin client (bypasses RLS)
        const { data: intent, error: fetchError } = await supabaseAdmin
            .from('purchase_intents')
            .select('*, event:events(*)')
            .eq('id', intentId)
            .single()

        if (fetchError || !intent) {
            throw new Error('Failed to fetch purchase intent')
        }

        // --- FREE EVENT SHORT-CIRCUIT ---
        // Skip Xendit entirely — Xendit rejects sessions with amount=0.
        // Mark completed, issue tickets sync, enqueue confirmation email, return.
        if (Math.round(Number(intent.total_amount)) === 0) {
            console.log(`🎟️ Free event — short-circuiting Xendit for intent ${intentId}`)

            await supabaseAdmin
                .from('purchase_intents')
                .update({
                    status: 'completed',
                    paid_at: new Date().toISOString(),
                    payment_method: 'FREE',
                })
                .eq('id', intentId)

            const { data: tickets, error: issueError } = await supabaseAdmin.rpc(
                'issue_tickets',
                {
                    p_intent_id: intentId,
                    p_registration_id: registration_id ?? intent.metadata?.registration_id ?? null,
                }
            )

            if (issueError) {
                console.error('❌ Failed to issue free tickets:', issueError)
                throw new Error(`Failed to issue free tickets: ${issueError.message}`)
            }

            // Enqueue confirmation email (best-effort, non-blocking)
            const recipientEmail = user?.email || guest_details?.email
            const recipientName = user
                ? (userProfile?.full_name ?? null)
                : (guest_details?.name ?? null)

            if (recipientEmail && Array.isArray(tickets) && tickets.length > 0) {
                const { error: queueError } = await supabaseAdmin.rpc('pgmq_send', {
                    queue_name: 'payment_side_effects',
                    message: {
                        type: 'send_ticket_email',
                        data: {
                            email: recipientEmail,
                            name: recipientName,
                            event_title: intent.event?.title || 'Event',
                            event_venue: intent.event?.venue_name || 'Venue',
                            event_date: intent.event?.start_datetime,
                            event_end_date: intent.event?.end_datetime,
                            event_cover_image: intent.event?.cover_image_url,
                            ticket_quantity: quantity,
                            total_amount: 0,
                            transaction_ref: intent.xendit_external_id || intentId,
                            payment_method: 'FREE',
                            tickets,
                        },
                    },
                })
                if (queueError) {
                    console.error('⚠️ Failed to enqueue free ticket email:', queueError)
                }
            }

            return new Response(
                JSON.stringify({
                    success: true,
                    data: {
                        intent_id: intentId,
                        free: true,
                        total_amount: 0,
                        tickets_reserved: quantity,
                        tier_name: tierName,
                        event: {
                            title: intent.event?.title,
                            start_datetime: intent.event?.start_datetime,
                        },
                    },
                }),
                { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
            )
        }

        // Create Xendit Payment Session (Hosted Checkout)
        const xenditKey = Deno.env.get('XENDIT_SECRET_KEY')
        if (!xenditKey) {
            throw new Error('XENDIT_SECRET_KEY not configured')
        }

        // Hanghut's total take per session (overrides static split rule).
        // = platform % on base, plus the fixed fee if pass_fees_to_customer is enabled.
        // Xendit's processing fee is deducted from this slice (Hanghut absorbs the variance).
        // @ts-ignore
        const passFees = req.feeDetails?.passFees === true
        // @ts-ignore
        const fixedFeeAmount = passFees ? req.feeDetails.fixedFee : 0
        const hanghutTake = Math.round(platformFee + fixedFeeAmount)

        const sessionBody = {
            reference_id: intent.xendit_external_id,
            session_type: 'PAY', // One-time payment
            mode: 'PAYMENT_LINK', // Hosted checkout page
            amount: Math.round(intent.total_amount),
            currency: 'PHP',
            country: 'PH',
            // Payment channels. Base set works for any account (incl. unverified
            // sub-accounts). CARDS + GCASH are gated by Xendit behind KYC, so we
            // only add them for the main wallet (verified platform account) or a
            // sub-account whose KYC is verified. QRPH stays main-wallet-only.
            allowed_payment_channels: [
                ...(useMainWallet ? ['QRPH'] : []),
                ...(useMainWallet || organizerCardsGcashLive ? ['CARDS', 'GCASH'] : []),
                'PAYMAYA',
                'GRABPAY',
                'BPI_DIRECT_DEBIT',
                'UBP_DIRECT_DEBIT',
                'RCBC_DIRECT_DEBIT',
            ],
            // Route Hanghut's take to the platform sub-account (overrides split rule per session).
            // Skipped for first-party events — the money already lands in the main account,
            // so a PLATFORM fee split is meaningless (and Xendit rejects it without a sub-account).
            ...(organizerId && hanghutTake > 0 && !useMainWallet ? {
                fees: [{ type: 'PLATFORM', value: hanghutTake }]
            } : {}),
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
            description: `${quantity}x ${tierName} for ${intent.event.title}`,
            success_return_url: success_url || undefined,
            cancel_return_url: failure_url || undefined,
            metadata: {
                event_id: event_id,
                intent_id: intentId,
                user_id: user?.id || 'guest',
                is_guest: String(!user),
                tier_id: tier_id || 'default',
                promo_code: promo_code || ''
            },
        }

        console.log('Creating Xendit Payment Session:', sessionBody)

        const headers = new Headers()
        headers.set('Authorization', `Basic ${btoa(xenditKey + ':')}`)
        headers.set('Content-Type', 'application/json')

        // XenPlatform: Route payment to organizer's sub-account with split rule.
        // First-party partners (use_main_wallet) skip this entirely — the payment
        // settles directly to the main Xendit account.
        if (organizerId && !useMainWallet) {
            const { data: orgPartner } = await supabaseAdmin
                .from('partners')
                .select('xendit_account_id, split_rule_id')
                .eq('id', organizerId)
                .single()

            if (orgPartner?.xendit_account_id) {
                headers.set('for-user-id', orgPartner.xendit_account_id)
                if (orgPartner.split_rule_id) {
                    headers.set('with-split-rule', orgPartner.split_rule_id)
                }
                console.log(`🏦 XenPlatform: routing to sub-account ${orgPartner.xendit_account_id}, split rule ${orgPartner.split_rule_id}`)
            }
        } else if (useMainWallet) {
            console.log(`🏦 Main wallet: first-party event ${event_id} settles directly to main account`)
        }

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
                    discount_amount: intent.discount_amount,
                    platform_fee: intent.platform_fee,
                    total_amount: intent.total_amount,
                    payment_url: session.payment_link_url,
                    expires_at: intent.expires_at,
                    tickets_reserved: quantity,
                    tier_name: tierName,
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
