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
        const { event_id, quantity, tier_id, promo_code, channel_code, guest_details, success_url, failure_url, subscribed_to_newsletter } = await req.json()

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
        let platformFeePercentage = 10.0 // Default 10%
        if (organizerId) {
            const { data: partner } = await supabaseClient
                .from('partners')
                .select('custom_percentage, pass_fees_to_customer, fixed_fee_per_ticket')
                .eq('id', organizerId)
                .single()

            // Check if distinct custom_percentage exists (it might be 0, so check undefined/null)
            if (partner && partner.custom_percentage !== null && partner.custom_percentage !== undefined) {
                platformFeePercentage = partner.custom_percentage
            }

            // --- PASS FEES LOGIC ---
            if (partner && partner.pass_fees_to_customer) {
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

        // --- UPDATE INTENT WITH PRICING & TIER INFO ---
        const subtotal = unitPrice * quantity
        let platformFee = (subtotal - discountAmount) * (platformFeePercentage / 100)
        let totalAmount = (subtotal - discountAmount) + platformFee
        let feeMetadata = {}

        // Override if Pass Fees is enabled
        // @ts-ignore
        if (req.feeDetails?.passFees) {
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

        console.log(`Updating Intent ${intentId}: Tier=${tierName}, Promo=${promo_code}, Total=${totalAmount}, Fee%=${platformFeePercentage}`)

        const { error: updateError } = await supabaseAdmin // Use Admin to bypass RLS
            .from('purchase_intents')
            .update({
                tier_id: tier_id ?? null,
                promo_code_id: promoCodeId,
                unit_price: unitPrice,
                subtotal: subtotal,
                discount_amount: discountAmount,
                platform_fee: platformFee,
                total_amount: totalAmount,
                pricing_note: `Tier: ${tierName}${promo_code ? ' | Promo: ' + promo_code : ''}`,
                fee_percentage: platformFeePercentage,
                subscribed_to_newsletter: subscribed_to_newsletter ?? false,
                // @ts-ignore
                metadata: Object.keys(feeMetadata).length > 0 ? feeMetadata : null
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
