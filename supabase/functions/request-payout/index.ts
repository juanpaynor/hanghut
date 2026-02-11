import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
    // Handle CORS
    if (req.method === 'OPTIONS') {
        return new Response('ok', { headers: corsHeaders })
    }

    try {
        // 1. Initialize Supabase Client
        const supabaseClient = createClient(
            Deno.env.get('SUPABASE_URL') ?? '',
            Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
        )

        // 2. Validate User Session (Authorization Header)
        // We manually verify the JWT because we need the user_id securely
        const authHeader = req.headers.get('Authorization')
        if (!authHeader) {
            throw new Error('Missing Authorization header')
        }
        const token = authHeader.replace('Bearer ', '')
        const { data: { user }, error: userError } = await supabaseClient.auth.getUser(token)

        if (userError || !user) {
            return new Response(JSON.stringify({ error: 'Unauthorized' }), { status: 401, headers: corsHeaders })
        }

        // 3. Parse Input
        const { amount, bank_account_id } = await req.json()
        if (!amount || amount <= 0) throw new Error('Invalid amount')
        if (!bank_account_id) throw new Error('Missing bank_account_id')

        // 4. Get Partner & Bank Details
        // Find the partner associated with this user
        const { data: partner, error: partnerError } = await supabaseClient
            .from('partners')
            .select('*')
            .eq('user_id', user.id)
            .single()

        if (partnerError || !partner) {
            throw new Error('Partner account not found for this user')
        }

        // Validate Bank Account ownership
        const { data: bankAccount, error: bankError } = await supabaseClient
            .from('bank_accounts')
            .select('*')
            .eq('id', bank_account_id)
            .eq('partner_id', partner.id)
            .single()

        if (bankError || !bankAccount) {
            throw new Error('Invalid bank account')
        }

        // 5. BALANCE CHECK (Revenue - Payouts)
        // A. Total Revenue (Completed transactions)
        const { data: revenueData, error: revenueError } = await supabaseClient
            .from('transactions')
            .select('organizer_payout')
            .eq('partner_id', partner.id)
            .eq('status', 'completed')

        if (revenueError) throw new Error('Failed to calculate revenue')

        // Sum revenue
        const totalRevenue = revenueData.reduce((sum, tx) => sum + (Number(tx.organizer_payout) || 0), 0)

        // B. Total Payouts (Non-failed requests)
        const { data: payoutsData, error: payoutsError } = await supabaseClient
            .from('payouts')
            .select('amount')
            .eq('partner_id', partner.id)
            .neq('status', 'failed') // Count pending, processing, completed
            .neq('status', 'rejected')

        if (payoutsError) throw new Error('Failed to calculate past payouts')

        // Sum payouts
        const totalPayouts = payoutsData.reduce((sum, p) => sum + (Number(p.amount) || 0), 0)

        // C. Available Balance
        const availableBalance = totalRevenue - totalPayouts

        if (availableBalance < amount) {
            throw new Error(`Insufficient balance. Available: ${availableBalance}, Requested: ${amount}`)
        }

        // 6. AUTO-APPROVAL CHECK
        const limit = Number(partner.payout_limit) || 50000 // Default 50k
        const isAutoApprovable = partner.auto_approve_enabled && amount <= limit
        const initialStatus = isAutoApprovable ? 'processing' : 'pending_request'

        // 7. Insert Payout Record (Immutable Lock)
        const { data: payout, error: insertError } = await supabaseClient
            .from('payouts')
            .insert({
                partner_id: partner.id,
                amount: amount,
                currency: 'PHP', // Defaulting to PHP for now
                bank_name: bankAccount.bank_code, // e.g. PH_BDO
                bank_account_number: bankAccount.account_number,
                bank_account_name: bankAccount.account_holder_name,
                status: initialStatus,
                admin_notes: isAutoApprovable ? 'Auto-approved via Edge Function' : 'Pending Manual Review'
            })
            .select()
            .single()

        if (insertError) throw new Error('Failed to create payout record: ' + insertError.message)

        // 8. EXECUTE XENDIT PAYOUT (If Auto-Approved)
        let xenditResponse = null
        if (isAutoApprovable) {
            const xenditSecret = Deno.env.get('XENDIT_SECRET_KEY')
            if (!xenditSecret) {
                // Log critical error but don't fail the request to user, keep it as 'processing' (admin will see it stuck)
                console.error('CRITICAL: Missing XENDIT_SECRET_KEY')
                await supabaseClient.from('payouts').update({ admin_notes: 'Auto-approve failed: Missing Xendit Key' }).eq('id', payout.id)
            } else {
                try {
                    // Xendit Payouts V2 API
                    const response = await fetch('https://api.xendit.co/v2/payouts', {
                        method: 'POST',
                        headers: {
                            'Content-Type': 'application/json',
                            'Authorization': `Basic ${btoa(xenditSecret + ':')}`,
                            'Idempotency-key': payout.id // Use our payout ID as idempotency key
                        },
                        body: JSON.stringify({
                            reference_id: payout.id,
                            channel_code: bankAccount.bank_code,
                            channel_properties: {
                                account_holder_name: bankAccount.account_holder_name,
                                account_number: bankAccount.account_number
                            },
                            amount: amount,
                            currency: 'PHP',
                            description: `Payout for ${partner.business_name}`
                        })
                    })

                    const responseData = await response.json()

                    if (!response.ok) {
                        throw new Error(`Xendit Error: ${responseData.message || JSON.stringify(responseData)}`)
                    }

                    xenditResponse = responseData

                    // Update Payout with Xendit IDs
                    await supabaseClient
                        .from('payouts')
                        .update({
                            xendit_external_id: responseData.reference_id, // Should match payout.id
                            xendit_disbursement_id: responseData.id,
                            status: 'processing' // Confirmed processing by Xendit
                        })
                        .eq('id', payout.id)

                } catch (xenditErr) {
                    console.error('Xendit Payout Failed:', xenditErr)
                    // Revert status to pending_request or failed so admin notices
                    await supabaseClient
                        .from('payouts')
                        .update({
                            status: 'pending_request', // Fallback to manual
                            admin_notes: `Auto-approval failed: ${xenditErr.message}`
                        })
                        .eq('id', payout.id)
                }
            }
        }

        return new Response(
            JSON.stringify({
                success: true,
                payout: payout,
                balance_after: availableBalance - amount
            }),
            { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )

    } catch (error) {
        console.error('Request Payout Error:', error)
        return new Response(
            JSON.stringify({ error: error.message }),
            { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
    }
})
