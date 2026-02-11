import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY")

const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

interface User {
    email: string
}

interface Partner {
    id: string
    business_name: string
    users: User
}

interface PayoutRecord {
    id: string
    amount: number
    created_at: string
    partner_id: string
    bank_name: string
    status: string
}

interface WebhookPayload {
    type: 'INSERT'
    table: 'payouts'
    record: PayoutRecord
    schema: 'public'
}

serve(async (req) => {
    // 1. Handle CORS
    if (req.method === 'OPTIONS') {
        return new Response('ok', { headers: corsHeaders })
    }

    try {
        const payload: WebhookPayload = await req.json()
        const record = payload.record

        // Verify payload type
        if (!record || !record.partner_id) {
            console.warn('⚠️ Invalid Payload:', payload)
            // Return 200 to prevent retries on invalid data
            return new Response(JSON.stringify({ message: 'Ignored invalid payload' }), {
                headers: { ...corsHeaders, 'Content-Type': 'application/json' },
                status: 200
            })
        }

        console.log(`💸 New Payout Request: ${record.id} for PHP ${record.amount}`)

        // 2. Initialize Supabase Client (Service Role for admin access)
        const supabaseClient = createClient(
            Deno.env.get('SUPABASE_URL') ?? '',
            Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
        )

        // 3. Fetch Partner and User Email
        const { data: partner, error: partnerError } = await supabaseClient
            .from('partners')
            .select(`
                id, 
                business_name,
                users!partners_user_id_fkey (
                    email
                )
            `)
            .eq('id', record.partner_id)
            .single()

        if (partnerError || !partner) {
            throw new Error(`Partner not found: ${partnerError?.message}`)
        }

        // Handle array or single object for joined relation (users)
        // PostgREST returns object if one-to-one or one-to-many depending on declaration
        // Assuming one-to-one or we take the first
        const userEmail = Array.isArray(partner.users)
            ? partner.users[0]?.email
            : (partner.users as any)?.email

        if (!userEmail) {
            throw new Error('Partner has no associated email')
        }

        // 4. Send Email via Resend
        if (!RESEND_API_KEY) {
            throw new Error("Missing RESEND_API_KEY")
        }

        const formattedDate = new Date(record.created_at).toLocaleDateString('en-US', {
            year: 'numeric', month: 'long', day: 'numeric'
        })
        const formattedAmount = `₱${record.amount.toLocaleString()}`

        const html = `
            <!DOCTYPE html>
            <html>
            <body style="font-family: Arial, sans-serif; line-height: 1.6; color: #333;">
                <div style="max-width: 600px; margin: 0 auto; padding: 20px;">
                    <h2 style="color: #4F46E5;">Payout Request Received</h2>
                    <p>Hi ${partner.business_name},</p>
                    <p>We have received your payout request. Here are the details:</p>
                    
                    <div style="background-color: #F3F4F6; padding: 15px; border-radius: 8px; margin: 20px 0;">
                        <p style="margin: 5px 0;"><strong>Amount:</strong> <span style="font-size: 1.2em; color: #10B981;">${formattedAmount}</span></p>
                        <p style="margin: 5px 0;"><strong>Date:</strong> ${formattedDate}</p>
                        <p style="margin: 5px 0;"><strong>Bank:</strong> ${record.bank_name || 'Default Account'}</p>
                        <p style="margin: 5px 0;"><strong>Status:</strong> <span style="background-color: #FEF3C7; padding: 2px 6px; border-radius: 4px;">${record.status.toUpperCase()}</span></p>
                    </div>

                    <p>Our team will review your request shortly. You will be notified once the transfer is processed.</p>
                    
                    <hr style="border: none; border-top: 1px solid #eee; margin: 30px 0;">
                    <p style="font-size: 12px; color: #888;">HangHut Partners Team</p>
                </div>
            </body>
            </html>
        `

        const resendRes = await fetch('https://api.resend.com/emails', {
            method: 'POST',
            headers: {
                'Authorization': `Bearer ${RESEND_API_KEY}`,
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({
                from: 'HangHut <payouts@hanghut.com>',
                to: [userEmail],
                subject: 'Payout Request Received',
                html: html
            })
        })

        if (!resendRes.ok) {
            const error = await resendRes.json()
            throw new Error(`Resend API Error: ${JSON.stringify(error)}`)
        }

        console.log('✅ Email sent successfully')

        return new Response(JSON.stringify({ success: true }), {
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
            status: 200,
        })

    } catch (error) {
        console.error('❌ Error handling webhook:', error)
        return new Response(JSON.stringify({ error: error.message }), {
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
            status: 500,
        })
    }
})
