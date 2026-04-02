import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

/**
 * get-subaccount-balance
 * 
 * Fetches a partner's real Xendit sub-wallet balance (available + pending settlement).
 * This is the source of truth for how much money is in the partner's sub-account.
 * 
 * Flow:
 *   1. Auth check (admin or partner owner via DB fallback)
 *   2. Look up partners.xendit_account_id
 *   3. GET /balance (account_type=CASH) with for-user-id header → available balance
 *   4. GET /balance (account_type=HOLDING) with for-user-id → pending settlement
 *   5. Return { available_balance, pending_settlement, currency }
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

        const { partner_id } = await req.json()
        if (!partner_id) {
            return new Response(JSON.stringify({ error: 'Missing partner_id' }), {
                headers: { ...corsHeaders, 'Content-Type': 'application/json' },
                status: 400,
            })
        }

        // 1. Fetch partner
        const { data: partner, error: partnerError } = await supabaseAdmin
            .from('partners')
            .select('id, user_id, xendit_account_id, platform_fee_receivable')
            .eq('id', partner_id)
            .single()

        if (partnerError || !partner) {
            return new Response(JSON.stringify({ error: 'Partner not found' }), {
                headers: { ...corsHeaders, 'Content-Type': 'application/json' },
                status: 404,
            })
        }

        // 2. Authorization: admin or partner owner
        let isAdmin = user.app_metadata?.role === 'admin' ||
                      user.app_metadata?.role === 'service_role' ||
                      user.user_metadata?.is_admin === true

        if (!isAdmin) {
            const { data: dbUser } = await supabaseAdmin
                .from('users')
                .select('is_admin')
                .eq('id', user.id)
                .maybeSingle()
            if (dbUser?.is_admin === true) isAdmin = true
        }

        const isOwner = partner.user_id === user.id

        if (!isAdmin && !isOwner) {
            return new Response(JSON.stringify({ error: 'Unauthorized' }), {
                headers: { ...corsHeaders, 'Content-Type': 'application/json' },
                status: 403,
            })
        }

        // 3. Check sub-account exists
        if (!partner.xendit_account_id) {
            return new Response(JSON.stringify({
                available_balance: 0,
                pending_settlement: 0,
                platform_fee_receivable: (partner.platform_fee_receivable as number) || 0,
                currency: 'PHP',
                has_subaccount: false,
                message: 'Partner does not have a Xendit sub-account yet',
            }), {
                headers: { ...corsHeaders, 'Content-Type': 'application/json' },
                status: 200,
            })
        }

        const authHeader = `Basic ${btoa(xenditKey + ':')}`
        const forUserHeader = partner.xendit_account_id

        // 4. Fetch available balance from Xendit
        console.log(`💰 Fetching balance for partner ${partner_id} (xendit: ${forUserHeader})...`)

        const balanceResponse = await fetch('https://api.xendit.co/balance', {
            method: 'GET',
            headers: {
                'Authorization': authHeader,
                'for-user-id': forUserHeader,
            },
        })

        let availableBalance = 0
        let currency = 'PHP'

        if (balanceResponse.ok) {
            const balanceData = await balanceResponse.json()
            availableBalance = balanceData.balance || 0
            currency = balanceData.currency || 'PHP'
            console.log(`  ✅ Available balance: ${currency} ${availableBalance}`)
        } else {
            const balanceError = await balanceResponse.text()
            console.error(`  ⚠️ Failed to fetch balance (${balanceResponse.status}):`, balanceError)
            // Don't fail — return 0 balance with a warning
        }

        // 5. Fetch pending settlement (HOLDING balance) from Xendit
        let pendingSettlement = 0

        const holdingResponse = await fetch(
            'https://api.xendit.co/balance?account_type=HOLDING',
            {
                method: 'GET',
                headers: {
                    'Authorization': authHeader,
                    'for-user-id': forUserHeader,
                },
            }
        )

        if (holdingResponse.ok) {
            const holdingData = await holdingResponse.json()
            pendingSettlement = holdingData.balance || 0
            console.log(`  ✅ Pending settlement (HOLDING): ${currency} ${pendingSettlement}`)
        } else {
            const holdingError = await holdingResponse.text()
            console.error(`  ⚠️ Failed to fetch holding balance (${holdingResponse.status}):`, holdingError)
            // Don't fail — return 0 pending
        }

        const receivable = (partner.platform_fee_receivable as number) || 0

        return new Response(JSON.stringify({
            available_balance: availableBalance,
            pending_settlement: pendingSettlement,
            platform_fee_receivable: receivable,
            currency: currency,
            has_subaccount: true,
            xendit_account_id: forUserHeader,
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
