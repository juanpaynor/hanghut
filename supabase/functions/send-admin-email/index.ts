// Supabase Edge Function: send-admin-email
// Deploy with: supabase functions deploy send-admin-email
//
// This function sends platform-level emails from HangHut Admin
// to the waitlist table (not partner_subscribers).
//
// Expected body:
// {
//   subject: string,
//   html_content: string,
//   sender_name?: string  // defaults to "HangHut"
// }

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY')
const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

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
        const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)

        // Verify the caller is an admin
        const authHeader = req.headers.get('Authorization')
        if (!authHeader) throw new Error('No authorization header')

        const token = authHeader.replace('Bearer ', '')
        const { data: { user }, error: authError } = await supabase.auth.getUser(token)
        if (authError || !user) throw new Error('Unauthorized')

        // Use a user-scoped client for the admin check (RPC needs user JWT context)
        const SUPABASE_ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY')!
        const userClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
            global: { headers: { Authorization: `Bearer ${token}` } }
        })
        const { data: isAdmin } = await userClient.rpc('is_user_admin')
        if (!isAdmin) throw new Error('Admin access required')

        // Parse request body
        const { subject, html_content, sender_name = 'HangHut' } = await req.json()

        if (!subject || !html_content) {
            throw new Error('Missing required fields: subject, html_content')
        }

        // Fetch all waitlist entries
        const { data: recipients, error: fetchError } = await supabase
            .from('waitlist')
            .select('email, full_name')

        if (fetchError) throw new Error(`Failed to fetch waitlist: ${fetchError.message}`)
        if (!recipients || recipients.length === 0) {
            return new Response(
                JSON.stringify({ success: true, sent_count: 0, message: 'No recipients in waitlist' }),
                { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
            )
        }

        // Send emails via Resend BATCH API (up to 100 per call, 1 API request each)
        let sentCount = 0
        let failedCount = 0
        const BATCH_SIZE = 100  // Resend batch limit

        const fromAddress = `${sender_name} <noreply@hanghut.com>`

        for (let i = 0; i < recipients.length; i += BATCH_SIZE) {
            const batch = recipients.slice(i, i + BATCH_SIZE)
            const batchNumber = Math.floor(i / BATCH_SIZE) + 1

            console.log(`📦 Sending batch ${batchNumber} (${batch.length} recipients)...`)

            // Build array of email payloads for the batch endpoint
            const emailPayloads = batch.map((recipient) => ({
                from: fromAddress,
                to: [recipient.email],
                subject: subject,
                html: html_content,
            }))

            try {
                const res = await fetch('https://api.resend.com/emails/batch', {
                    method: 'POST',
                    headers: {
                        'Authorization': `Bearer ${RESEND_API_KEY}`,
                        'Content-Type': 'application/json',
                    },
                    body: JSON.stringify(emailPayloads),
                })

                if (res.ok) {
                    const result = await res.json()
                    sentCount += batch.length
                    console.log(`   ✅ Batch ${batchNumber} sent! (${result.data?.length} emails)`)
                } else {
                    const err = await res.json()
                    failedCount += batch.length
                    console.error(`   ❌ Batch ${batchNumber} failed:`, JSON.stringify(err))
                }
            } catch (err) {
                failedCount += batch.length
                console.error(`   ❌ Batch ${batchNumber} error:`, err)
            }

            // Rate limit safety: wait 600ms between batches (2 req/sec limit)
            if (i + BATCH_SIZE < recipients.length) {
                console.log('   ⏳ Waiting 600ms for rate limit...')
                await new Promise(resolve => setTimeout(resolve, 600))
            }
        }

        // Log the campaign
        await supabase.from('admin_email_campaigns').insert({
            subject,
            html_content,
            sender_name,
            recipient_count: recipients.length,
            sent_count: sentCount,
            failed_count: failedCount,
            status: failedCount === 0 ? 'sent' : 'partial',
            sent_at: new Date().toISOString(),
            sent_by: user.id,
        })

        return new Response(
            JSON.stringify({
                success: true,
                sent_count: sentCount,
                failed_count: failedCount,
                total_recipients: recipients.length,
            }),
            { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )

    } catch (error) {
        console.error('send-admin-email error:', error)
        return new Response(
            JSON.stringify({ success: false, error: error.message }),
            { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
    }
})
