
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY")
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")

const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

interface RequestData {
    partner_id: string
    subject: string
    html_content: string
    sender_name: string
    test_mode?: boolean
}

// FORMATTER: Sanitize Sender Name for Email Address
// "Club XYZ" -> "clubxyz"
function sanitizeSenderName(name: string): string {
    return name.toLowerCase().replace(/[^a-z0-9]/g, "")
}

serve(async (req) => {
    // Handle CORS
    if (req.method === 'OPTIONS') {
        return new Response('ok', { headers: corsHeaders })
    }

    try {
        const { partner_id, subject, html_content, sender_name, test_mode } = await req.json() as RequestData

        if (!partner_id || !subject || !html_content || !sender_name) {
            throw new Error("Missing required fields")
        }

        const supabase = createClient(SUPABASE_URL!, SUPABASE_SERVICE_ROLE_KEY!)

        // 1. Fetch Subscribers
        let subscribers = []
        if (test_mode) {
            console.log('🧪 Test Mode: Using dummy subscribers')
            subscribers = [
                { email: 'rich@hanghut.com', unsubscribe_token: 'test-token-1' },
                // Add more test emails if needed
            ]
        } else {
            console.log(`🔍 Fetching subscribers for partner: ${partner_id}`)
            // Fetch active subscribers for this partner
            // We select email AND unsubscribe_token to inject personalized links
            const { data: subs, error } = await supabase
                .from('partner_subscribers')
                .select('email, unsubscribe_token')
                .eq('partner_id', partner_id)
                .eq('is_active', true)

            if (error) throw error
            subscribers = subs
        }

        console.log(`✅ Found ${subscribers.length} subscribers`)

        if (subscribers.length === 0) {
            return new Response(JSON.stringify({ message: "No active subscribers found", count: 0 }), {
                headers: { ...corsHeaders, 'Content-Type': 'application/json' },
                status: 200
            })
        }

        // 2. Prepare Sender Identity
        const sanitizedSender = sanitizeSenderName(sender_name)
        const fromAddress = `${sender_name} <${sanitizedSender}@hanghut.com>`

        // 3. Batch Sending Logic (Resend Limit: 100 per batch)
        const BATCH_SIZE = 100
        let successCount = 0
        let failedCount = 0

        // Split into chunks
        for (let i = 0; i < subscribers.length; i += BATCH_SIZE) {
            const batch = subscribers.slice(i, i + BATCH_SIZE)
            console.log(`📦 Processing batch ${i / BATCH_SIZE + 1} (${batch.length} recipients)...`)

            // 4. Construct Individual Emails with Unsubscribe Footer
            const emailPayloads = batch.map(sub => {
                const unsubscribeUrl = `https://hanghut.com/unsubscribe?token=${sub.unsubscribe_token}`

                // Append Footer
                const footerHtml = `
                    <div style="margin-top: 40px; border-top: 1px solid #eee; padding-top: 20px; text-align: center; color: #888; font-size: 12px; font-family: sans-serif;">
                        <p>You received this email because you subscribed to updates from <strong>${sender_name}</strong>.</p>
                        <p><a href="${unsubscribeUrl}" style="color: #666; text-decoration: underline;">Unsubscribe</a> from these emails.</p>
                    </div>
                `

                return {
                    from: fromAddress,
                    to: sub.email,
                    subject: subject,
                    html: html_content + footerHtml
                }
            })

            // 5. Send Batch via Resend API
            // Use fetch directly as resend SDK might need complex setup in Deno
            const resendRes = await fetch('https://api.resend.com/emails/batch', {
                method: 'POST',
                headers: {
                    'Authorization': `Bearer ${RESEND_API_KEY}`,
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify(emailPayloads)
            })

            if (resendRes.ok) {
                const result = await resendRes.json()
                // Resend batch returns: { data: [ { id: ... } ] }
                successCount += batch.length
                console.log(`   ✅ Batch sent successfully! IDs: ${result.data?.length}`)
            } else {
                const err = await resendRes.json()
                console.error(`   ❌ Batch failed:`, err)
                failedCount += batch.length
            }

            // 6. Rate Limiting (Safety wait)
            // Resend allows ~2 req/sec. We wait 1000ms to be super safe.
            if (i + BATCH_SIZE < subscribers.length) {
                console.log('   ⏳ Waiting 1s for rate limit...')
                await new Promise(resolve => setTimeout(resolve, 1000))
            }
        }

        // 7. Log Campaign
        if (!test_mode) {
            try {
                await supabase.from('email_campaigns').insert({
                    partner_id: partner_id,
                    subject: subject,
                    html_content: html_content, // Maybe truncate if huge? But useful for history.
                    recipient_count: subscribers.length,
                    sent_count: successCount,
                    failed_count: failedCount,
                    status: failedCount === 0 ? 'sent' : (successCount > 0 ? 'partial_failure' : 'failed'),
                    sent_at: new Date().toISOString()
                })
            } catch (logError) {
                console.error('⚠️ Failed to log campaign stats:', logError)
            }
        }

        return new Response(JSON.stringify({
            success: true,
            total: subscribers.length,
            sent: successCount,
            failed: failedCount
        }), {
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
            status: 200
        })

    } catch (error) {
        console.error('💥 Global Error:', error)
        return new Response(JSON.stringify({ error: error.message }), {
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
            status: 500
        })
    }
})
