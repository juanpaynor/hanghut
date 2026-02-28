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
        const supabaseClient = createClient(
            Deno.env.get('SUPABASE_URL') ?? '',
            Deno.env.get('SUPABASE_ANON_KEY') ?? '',
            { global: { headers: { Authorization: req.headers.get('Authorization')! } } }
        )

        const supabaseAdmin = createClient(
            Deno.env.get('SUPABASE_URL') ?? '',
            Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
        )

        const { table_id, schedule_id, quantity = 1, guest_details, success_url, failure_url } = await req.json()

        // 1. Auth Check

        // Strict: Experiences require a logged-in user account.
        const { data: { user } } = await supabaseClient.auth.getUser()

        if (!user) {
            return new Response(JSON.stringify({ error: 'Authentication required. Guest checkout is not allowed for experiences.' }), { status: 401, headers: corsHeaders })
        }

        // Fetch user profile for name and phone
        let userProfile = null
        if (user) {
            const { data: profile } = await supabaseClient
                .from('users')
                .select('full_name, phone')
                .eq('id', user.id)
                .single()
            userProfile = profile
        }

        // 2. Reserve Spot via RPC
        const { data: intentId, error: reserveError } = await supabaseClient.rpc('reserve_experience', {
            p_table_id: table_id,
            p_schedule_id: schedule_id,
            p_user_id: user?.id ?? null,
            p_quantity: quantity,
            p_guest_email: guest_details?.email ?? user?.email ?? null,
            p_guest_name: guest_details?.name ?? userProfile?.full_name ?? null,
            p_guest_phone: guest_details?.phone ?? userProfile?.phone ?? null
        })

        if (reserveError) throw new Error(reserveError.message)

        // 3. Fetch Created Intent and Details
        const { data: intent, error: fetchError } = await supabaseAdmin
            .from('experience_purchase_intents')
            .select('*, table:tables(title, price_per_person)')
            .eq('id', intentId)
            .single()

        if (fetchError || !intent) throw new Error('Failed to fetch purchase intent')

        // 4. Create Xendit Invoice
        const xenditKey = Deno.env.get('XENDIT_SECRET_KEY')
        if (!xenditKey) throw new Error('XENDIT_SECRET_KEY not configured')

        console.log(`🎟️ Creating Xendit Invoice for Experience Intent: ${intentId}`)

        const sessionBody = {
            reference_id: intent.xendit_external_id,
            session_type: 'PAY',
            mode: 'PAYMENT_LINK',
            amount: Math.round(intent.total_amount),
            currency: 'PHP',
            country: 'PH',
            customer: {
                reference_id: user?.id ? `${user.id}_${Date.now()}` : `guest_${intent.id}_${Date.now()}`,
                type: 'INDIVIDUAL',
                email: user?.email || guest_details?.email || 'customer@example.com',
                mobile_number: userProfile?.phone || guest_details?.phone || '+639000000000',
                individual_detail: {
                    given_names: userProfile?.full_name?.split(' ')[0] || guest_details?.name?.split(' ')[0] || 'Guest',
                    surname: userProfile?.full_name?.split(' ').slice(1).join(' ') || guest_details?.name?.split(' ').slice(1).join(' ') || '-',
                }
            },
            description: `${quantity}x ${intent.table.title}`,
            success_return_url: success_url || undefined,
            cancel_return_url: failure_url || undefined,
            metadata: {
                table_id: table_id,
                schedule_id: schedule_id,
                intent_id: intentId,
                user_id: user?.id || 'guest'
            }
        }

        const headers = new Headers()
        headers.set('Authorization', `Basic ${btoa(xenditKey + ':')}`)
        headers.set('Content-Type', 'application/json')

        const xenditResponse = await fetch('https://api.xendit.co/sessions', {
            method: 'POST',
            headers,
            body: JSON.stringify(sessionBody)
        })

        if (!xenditResponse.ok) {
            const err = await xenditResponse.text()
            console.error('❌ Xendit Error:', err)
            throw new Error(`Payment provider error: ${err}`)
        }

        const session = await xenditResponse.json()
        console.log('✅ Xendit Payment Session Created:', session)

        // 5. Update Intent with Xendit Data
        await supabaseAdmin
            .from('experience_purchase_intents')
            .update({
                xendit_invoice_id: session.id,
                xendit_invoice_url: session.payment_link_url
            })
            .eq('id', intentId)

        return new Response(JSON.stringify({
            success: true,
            data: {
                intent_id: intentId,
                payment_url: session.payment_link_url
            }
        }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })

    } catch (error) {
        console.error('Error:', error)
        return new Response(JSON.stringify({ error: error.message }), { status: 400, headers: corsHeaders })
    }
})
