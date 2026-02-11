import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
    if (req.method === 'OPTIONS') {
        return new Response('ok', { headers: corsHeaders })
    }

    try {
        const { payout_id } = await req.json()

        if (!payout_id) {
            throw new Error('Missing payout_id')
        }

        // 1. Initialize Supabase Client
        const supabaseUrl = Deno.env.get('SUPABASE_URL')!
        const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
        const supabase = createClient(supabaseUrl, supabaseKey)
        const resendApiKey = Deno.env.get('RESEND_API_KEY')!


        // 2. Validate Admin User (Caller)
        const authHeader = req.headers.get('Authorization')
        if (!authHeader) throw new Error('Missing Authorization header')

        const token = authHeader.replace('Bearer ', '')
        const { data: { user }, error: userError } = await supabase.auth.getUser(token)

        if (userError || !user) throw new Error('Unauthorized')

        // Check is_admin flag
        const { data: adminData, error: adminError } = await supabase
            .from('users')
            .select('is_admin')
            .eq('id', user.id)
            .single()

        if (adminError || adminData?.is_admin !== true) {
            return new Response(
                JSON.stringify({ error: 'Unauthorized: Admin privileges required' }),
                { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
            )
        }

        // 3. Fetch Payout & Lock/Update (Atomic Check)
        // We use UPDATE with condition to prevent double-spending without explicit locking
        // If status is NOT 'pending_request', we fail.

        const { data: payout, error: payoutError } = await supabase
            .from('payouts')
            .select(`
                *,
                partners (
                    business_name
                )
            `)
            .eq('id', payout_id)
            .single()

        if (payoutError || !payout) throw new Error('Payout not found')

        if (payout.status !== 'pending_request') {
            throw new Error(`Payout is not pending (Status: ${payout.status})`)
        }

        // 4. Mark as Processing (Atomic Lock)
        const { error: updateError } = await supabase
            .from('payouts')
            .update({
                status: 'processing',
                approved_by: user.id,
                approved_at: new Date().toISOString()
            })
            .eq('id', payout_id)
            .eq('status', 'pending_request') // Optimistic Concurrency Control

        if (updateError) throw new Error('Failed to lock payout record. Try again.')

        // 5. Execute Xendit Payout
        const xenditSecret = Deno.env.get('XENDIT_SECRET_KEY')
        if (!xenditSecret) throw new Error('Missing XENDIT_SECRET_KEY')

        const response = await fetch('https://api.xendit.co/v2/payouts', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'Authorization': `Basic ${btoa(xenditSecret + ':')}`,
                'Idempotency-key': payout.id
            },
            body: JSON.stringify({
                reference_id: payout.id,
                channel_code: payout.bank_name, // Assumes this is a valid Xendit Channel Code (e.g. PH_BDO) stored in DB
                channel_properties: {
                    account_holder_name: payout.bank_account_name,
                    account_number: payout.bank_account_number
                },
                amount: payout.amount,
                currency: 'PHP',
                description: `Payout for ${payout.partners?.business_name}`
            })
        })

        const xenditData = await response.json()

        if (!response.ok) {
            // Revert status to failed if Xendit request fails
            await supabase.from('payouts').update({
                status: 'failed',
                admin_notes: `Xendit Error: ${xenditData.message}`
            }).eq('id', payout_id)

            throw new Error(`Xendit Error: ${xenditData.message || JSON.stringify(xenditData)}`)
        }

        // 6. Update Payout with External IDs
        await supabase.from('payouts').update({
            xendit_external_id: xenditData.reference_id,
            xendit_disbursement_id: xenditData.id
        }).eq('id', payout_id)


        // 7. Send Notification Email (Resend)
        // Need to fetch partner email via User ID
        try {
            const { data: partnerUser, error: partnerUserError } = await supabase
                .from('users')
                .select('email, display_name')
                .eq('id', payout.partner_id) // Wait, partner_id points to 'partners', which has 'user_id'
                .single() // This will likely fail because we need to join partners -> users

            // Correct fetch:
            const { data: partnerRecord } = await supabase
                .from('partners')
                .select('user_id')
                .eq('id', payout.partner_id)
                .single();

            if (partnerRecord) {
                const { data: userRecord } = await supabase
                    .from('users')
                    .select('email')
                    .eq('id', partnerRecord.user_id)
                    .single();

                if (userRecord?.email) {
                    const emailRes = await fetch('https://api.resend.com/emails', {
                        method: 'POST',
                        headers: {
                            'Content-Type': 'application/json',
                            'Authorization': `Bearer ${resendApiKey}`
                        },
                        body: JSON.stringify({
                            from: 'Hanghut Payout <payout@hanghut.com>',
                            to: [userRecord.email],
                            subject: 'Payout Processed',
                            html: `
                                <h1>Payout Approved</h1>
                                <p>Your payout request for <strong>PHP ${payout.amount}</strong> has been approved and is being processed.</p>
                                <p>Reference ID: ${payout.id}</p>
                                <p>Estimated arrival: Instant (or within 1 business day)</p>
                            `
                        })
                    })
                    if (!emailRes.ok) {
                        const err = await emailRes.text()
                        console.error('Email failed:', err)
                    }
                }
            }

        } catch (emailErr) {
            console.error('Failed to send email (non-blocking):', emailErr)
        }

        return new Response(
            JSON.stringify({ success: true, xendit_id: xenditData.id }),
            { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )

    } catch (error) {
        return new Response(
            JSON.stringify({ error: error.message }),
            { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
    }
})
