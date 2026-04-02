import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

/**
 * create-split-rule
 * 
 * Creates a Xendit split rule for a partner, defining how payments are
 * split between the partner's sub-account and HangHut's master account.
 * 
 * Called by the admin panel when setting or changing a partner's commission %.
 * The returned split_rule_id is stored on the partners table and used in
 * all subsequent payment intents (create-purchase-intent, create-experience-intent).
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

        // Auth check — admin only
        const { data: { user } } = await supabaseClient.auth.getUser()
        if (!user) {
            return new Response(JSON.stringify({ error: 'Unauthorized' }), {
                headers: { ...corsHeaders, 'Content-Type': 'application/json' },
                status: 401,
            })
        }

        //    Check JWT metadata first, then fall back to DB lookup (web admin panel uses authenticated JWT)
        let isAdmin = user.app_metadata?.role === 'admin' ||
                        user.app_metadata?.role === 'service_role' ||
                        user.user_metadata?.is_admin === true

        console.log(`🔐 Auth check for user ${user.id}: app_metadata.role=${user.app_metadata?.role}, user_metadata.is_admin=${user.user_metadata?.is_admin}, isAdmin(jwt)=${isAdmin}`)

        if (!isAdmin) {
            // Fallback: check users table for is_admin column (used by web admin panel)
            const { data: dbUser, error: dbError } = await supabaseAdmin
                .from('users')
                .select('is_admin')
                .eq('id', user.id)
                .maybeSingle()

            console.log(`🔐 DB fallback: dbUser=${JSON.stringify(dbUser)}, dbError=${JSON.stringify(dbError)}`)

            if (dbUser?.is_admin === true) isAdmin = true
        }

        if (!isAdmin) {
            console.log(`❌ Admin check failed for user ${user.id} — returning 403`)
            return new Response(JSON.stringify({ error: 'Admin access required' }), {
                headers: { ...corsHeaders, 'Content-Type': 'application/json' },
                status: 403,
            })
        }

        const { partner_id, platform_percentage } = await req.json()

        if (!partner_id) {
            return new Response(JSON.stringify({ error: 'Missing partner_id' }), {
                headers: { ...corsHeaders, 'Content-Type': 'application/json' },
                status: 400,
            })
        }

        if (platform_percentage === undefined || platform_percentage === null) {
            return new Response(JSON.stringify({ error: 'Missing platform_percentage' }), {
                headers: { ...corsHeaders, 'Content-Type': 'application/json' },
                status: 400,
            })
        }

        if (platform_percentage < 0 || platform_percentage > 100) {
            return new Response(JSON.stringify({ error: 'platform_percentage must be between 0 and 100' }), {
                headers: { ...corsHeaders, 'Content-Type': 'application/json' },
                status: 400,
            })
        }

        // 1. Fetch partner
        const { data: partner, error: partnerError } = await supabaseAdmin
            .from('partners')
            .select('id, business_name, xendit_account_id, split_rule_id')
            .eq('id', partner_id)
            .single()

        if (partnerError || !partner) {
            return new Response(JSON.stringify({ error: 'Partner not found' }), {
                headers: { ...corsHeaders, 'Content-Type': 'application/json' },
                status: 404,
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

        const partnerPercentage = Math.round((100 - platform_percentage) * 100) / 100 // 2 decimal places

        // 2. Create Xendit Split Rule
        const authHeader = `Basic ${btoa(xenditKey + ':')}`

        const masterAccountId = Deno.env.get('XENDIT_MASTER_ACCOUNT_ID')
        if (!masterAccountId) {
            throw new Error('Missing XENDIT_MASTER_ACCOUNT_ID environment variable')
        }

        // Sanitize for Xendit: name/description only allow [a-zA-Z0-9 ]
        const sanitizedName = (partner.business_name?.replace(/[^a-zA-Z0-9 ]/g, '') || 'Partner').trim()
        // Convert percentage to clean integer string (4.0 → "4", 15.5 → "15") to avoid dots
        const pctLabel = String(Math.round(platform_percentage))
        const partnerId8 = partner_id.substring(0, 8).replace(/[^a-zA-Z0-9]/g, '')

        const rawName = `HangHut ${partnerId8} ${pctLabel}pct`
        const rawDesc = `${pctLabel} pct platform fee for ${sanitizedName}`

        const splitRulePayload = {
            name: rawName.replace(/[^a-zA-Z0-9 ]/g, '').trim(),
            description: rawDesc.replace(/[^a-zA-Z0-9 ]/g, '').trim(),
            routes: [
                {
                    percent_amount: platform_percentage,
                    currency: 'PHP',
                    destination_account_id: masterAccountId,
                    reference_id: `platform_fee_${partner_id.substring(0, 8)}`,
                },
                // The remaining percentage stays in the Source Account (the partner's sub-account)
            ],
        }

        console.log(`📊 Creating split rule for partner ${partner_id}: ${partnerPercentage}% partner / ${platform_percentage}% platform`)

        const xenditResponse = await fetch('https://api.xendit.co/split_rules', {
            method: 'POST',
            headers: {
                'Authorization': authHeader,
                'Content-Type': 'application/json',
            },
            body: JSON.stringify(splitRulePayload),
        })

        const xenditData = await xenditResponse.json()

        if (!xenditResponse.ok) {
            console.error('❌ Xendit Split Rule Error:', xenditData)
            return new Response(JSON.stringify({
                error: xenditData.message || 'Failed to create split rule',
                details: xenditData,
            }), {
                headers: { ...corsHeaders, 'Content-Type': 'application/json' },
                status: xenditResponse.status,
            })
        }

        console.log(`✅ Split rule created: ${xenditData.id}`)

        // 3. Store split_rule_id on partner
        const { error: updateError } = await supabaseAdmin
            .from('partners')
            .update({
                split_rule_id: xenditData.id,
                custom_percentage: platform_percentage,
            })
            .eq('id', partner_id)

        if (updateError) {
            console.error('⚠️ Split rule created but failed to save to DB:', updateError)
            // Still return success — the split rule exists in Xendit
            return new Response(JSON.stringify({
                success: true,
                split_rule_id: xenditData.id,
                warning: 'Split rule created in Xendit but failed to save to database. Please update manually.',
            }), {
                headers: { ...corsHeaders, 'Content-Type': 'application/json' },
                status: 200,
            })
        }

        const previousRuleId = partner.split_rule_id
        console.log(`✅ Stored split_rule_id=${xenditData.id} for partner ${partner_id}${previousRuleId ? ` (replaced ${previousRuleId})` : ''}`)

        return new Response(JSON.stringify({
            success: true,
            split_rule_id: xenditData.id,
            platform_percentage: platform_percentage,
            partner_percentage: partnerPercentage,
            previous_split_rule_id: previousRuleId || null,
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
