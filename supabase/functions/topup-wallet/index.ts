import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

/**
 * topup-wallet
 * 
 * Creates a Xendit payment link to top up a partner's sub-wallet.
 * NO split rule — 100% of the payment goes to the sub-wallet.
 * 
 * Used for:
 *   1. Covering refund costs when sub-wallet balance is low
 *   2. Pre-funding wallet for smooth operations
 *   3. Paying back platform_fee_receivable owed to HangHut
 * 
 * On webhook confirmation (handled separately), auto-settles
 * platform_fee_receivable if > 0.
 */

serve(async (req: Request) => {
    if (req.method === 'OPTIONS') {
        return new Response('ok', { headers: corsHeaders })
    }

    try {
        const sbUrl = Deno.env.get('SUPABASE_URL') ?? ''
        const sbAnonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? ''
        const sbServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
        const xenditKey = Deno.env.get('XENDIT_SECRET_KEY')

        if (!xenditKey) throw new Error('Missing XENDIT_SECRET_KEY')

        const supabaseClient = createClient(sbUrl, sbAnonKey, {
            global: { headers: { Authorization: req.headers.get('Authorization')! } },
        })
        const supabaseAdmin = createClient(sbUrl, sbServiceKey)

        // Auth check
        const { data: { user } } = await supabaseClient.auth.getUser()
        if (!user) {
            return new Response(JSON.stringify({ error: 'Unauthorized' }), {
                headers: { ...corsHeaders, 'Content-Type': 'application/json' },
                status: 401,
            })
        }

        const { partner_id, amount, success_url, failure_url } = await req.json()

        if (!partner_id) {
            return new Response(JSON.stringify({ error: 'Missing partner_id' }), {
                headers: { ...corsHeaders, 'Content-Type': 'application/json' },
                status: 400,
            })
        }

        if (!amount || amount < 100) {
            return new Response(JSON.stringify({ error: 'Amount must be at least ₱100' }), {
                headers: { ...corsHeaders, 'Content-Type': 'application/json' },
                status: 400,
            })
        }

        if (amount > 100000) {
            return new Response(JSON.stringify({ error: 'Amount cannot exceed ₱100,000 per top-up' }), {
                headers: { ...corsHeaders, 'Content-Type': 'application/json' },
                status: 400,
            })
        }

        // 1. Fetch partner
        const { data: partner, error: partnerError } = await supabaseAdmin
            .from('partners')
            .select('id, user_id, business_name, work_email, xendit_account_id, platform_fee_receivable')
            .eq('id', partner_id)
            .single()

        if (partnerError || !partner) {
            return new Response(JSON.stringify({ error: 'Partner not found' }), {
                headers: { ...corsHeaders, 'Content-Type': 'application/json' },
                status: 404,
            })
        }

        // Authorization: admin or partner owner
        const isAdmin = user.app_metadata?.role === 'admin' ||
                        user.app_metadata?.role === 'service_role' ||
                        user.user_metadata?.is_admin === true
        const isOwner = partner.user_id === user.id

        if (!isAdmin && !isOwner) {
            return new Response(JSON.stringify({ error: 'Unauthorized' }), {
                headers: { ...corsHeaders, 'Content-Type': 'application/json' },
                status: 403,
            })
        }

        if (!partner.xendit_account_id) {
            return new Response(JSON.stringify({
                error: 'Partner does not have a Xendit sub-account yet',
                code: 'NO_SUBACCOUNT',
            }), {
                headers: { ...corsHeaders, 'Content-Type': 'application/json' },
                status: 400,
            })
        }

        // 2. Create a unique reference ID for this top-up
        const referenceId = `topup_${partner_id.substring(0, 8)}_${Date.now()}`

        // 3. Create Xendit payment session directed to the sub-account
        // KEY: for-user-id routes payment to sub-wallet, NO split rule
        const authHeader = `Basic ${btoa(xenditKey + ':')}`

        const email = partner.work_email || user.email || 'partner@hanghut.com'
        const nameParts = (partner.business_name || 'Partner').trim().split(' ')
        const givenNames = nameParts[0] || 'Partner'
        const surname = nameParts.length > 1 ? nameParts.slice(1).join(' ') : '-'

        const sessionBody = {
            reference_id: referenceId,
            session_type: 'PAY',
            mode: 'PAYMENT_LINK',
            amount: Math.round(amount),
            currency: 'PHP',
            country: 'PH',
            // Only include payment channels activated in Xendit Dashboard
            // Excludes: QR_PH, OTC, BILLEASE
            allowed_payment_channels: [
                'CARDS',
                'GCASH',
            ],
            customer: {
                reference_id: `${user.id}_topup_${Date.now()}`,
                type: 'INDIVIDUAL',
                email: email,
                individual_detail: {
                    given_names: givenNames,
                    surname: surname,
                },
            },
            description: `Wallet Top-Up for ${partner.business_name}`,
            success_return_url: success_url || undefined,
            cancel_return_url: failure_url || undefined,
            metadata: {
                type: 'wallet_topup',
                partner_id: String(partner_id),
                user_id: String(user.id),
                platform_fee_receivable: String(partner.platform_fee_receivable || 0),
            },
        }

        console.log(`💰 Creating top-up payment for partner ${partner_id}: ₱${amount}`)

        const xenditResponse = await fetch('https://api.xendit.co/sessions', {
            method: 'POST',
            headers: {
                'Authorization': authHeader,
                'Content-Type': 'application/json',
                'for-user-id': partner.xendit_account_id, // Route to sub-wallet
                // NO with-split-rule — 100% goes to sub-wallet
            },
            body: JSON.stringify(sessionBody),
        })

        if (!xenditResponse.ok) {
            const err = await xenditResponse.text()
            console.error('❌ Xendit top-up error:', err)
            throw new Error(`Payment provider error: ${err}`)
        }

        const session = await xenditResponse.json()
        console.log('✅ Top-up payment session created:', session.id)

        // 4. Record the top-up attempt in DB (for tracking/reconciliation)
        const { error: insertError } = await supabaseAdmin
            .from('wallet_topups')
            .insert({
                partner_id: partner_id,
                user_id: user.id,
                amount: amount,
                currency: 'PHP',
                status: 'pending',
                xendit_session_id: session.id,
                reference_id: referenceId,
                platform_fee_settled: 0,
            })

        if (insertError) {
            console.error('⚠️ Failed to record top-up in DB (non-critical):', insertError)
        }

        return new Response(JSON.stringify({
            success: true,
            payment_url: session.payment_link_url,
            reference_id: referenceId,
            amount: amount,
            platform_fee_receivable: partner.platform_fee_receivable || 0,
            message: partner.platform_fee_receivable > 0
                ? `Top-up will auto-settle ₱${Math.min(amount, partner.platform_fee_receivable)} of outstanding platform fees.`
                : 'Top-up will credit your wallet directly.',
        }), {
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
            status: 200,
        })

    } catch (error: any) {
        console.error('CRITICAL ERROR:', error)
        return new Response(JSON.stringify({
            error: 'Internal Server Error',
            message: error.message,
        }), {
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
            status: 500,
        })
    }
})
