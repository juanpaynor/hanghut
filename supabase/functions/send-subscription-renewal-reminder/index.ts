import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY')
const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

function buildHtml(data: {
    fan_name: string
    tier_name: string
    partner_name: string
    price_monthly: number
    renewal_date: string
}): string {
    return `<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"></head>
<body style="margin:0;padding:0;background:#f9fafb;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif">
  <div style="max-width:560px;margin:40px auto;background:#fff;border-radius:16px;overflow:hidden;box-shadow:0 1px 3px rgba(0,0,0,.1)">
    <!-- Header -->
    <div style="background:linear-gradient(135deg,#7c3aed,#a855f7);padding:32px 32px 24px;text-align:center">
      <p style="margin:0 0 8px;font-size:28px">🔔</p>
      <h1 style="margin:0;font-size:22px;font-weight:800;color:#fff">Membership renewing in 3 days</h1>
    </div>
    <!-- Body -->
    <div style="padding:32px">
      <p style="margin:0 0 16px;font-size:16px;color:#111827">Hi ${data.fan_name || 'there'},</p>
      <p style="margin:0 0 20px;font-size:16px;color:#374151;line-height:1.6">
        Your <strong>${data.tier_name}</strong> membership with <strong>${data.partner_name}</strong> will automatically renew in 3 days.
      </p>
      <!-- Renewal details -->
      <div style="background:#f5f3ff;border-radius:12px;padding:20px;margin-bottom:24px">
        <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:8px">
          <span style="font-size:14px;color:#6b7280">Plan</span>
          <span style="font-size:15px;font-weight:700;color:#7c3aed">${data.tier_name}</span>
        </div>
        <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:8px">
          <span style="font-size:14px;color:#6b7280">Renewal amount</span>
          <span style="font-size:15px;font-weight:600;color:#111827">₱${data.price_monthly.toLocaleString()}</span>
        </div>
        <div style="display:flex;justify-content:space-between;align-items:center">
          <span style="font-size:14px;color:#6b7280">Renewal date</span>
          <span style="font-size:15px;font-weight:600;color:#111827">${data.renewal_date}</span>
        </div>
      </div>
      <p style="margin:0 0 24px;font-size:14px;color:#6b7280;line-height:1.6">
        If you'd like to cancel before the renewal date, you can manage your membership below.
      </p>
      <!-- CTA -->
      <div style="text-align:center;margin:8px 0">
        <a href="https://hanghut.com/account"
           style="display:inline-block;background:#7c3aed;color:#fff;text-decoration:none;font-size:16px;font-weight:700;padding:14px 32px;border-radius:12px">
          Manage membership
        </a>
      </div>
    </div>
    <!-- Footer -->
    <div style="padding:20px 32px;border-top:1px solid #f3f4f6;text-align:center">
      <p style="margin:0;font-size:12px;color:#9ca3af">
        You're receiving this because you have an active membership on HangHut.
      </p>
      <p style="margin:8px 0 0;font-size:12px;color:#9ca3af">© HangHut · Philippines</p>
    </div>
  </div>
</body>
</html>`
}

serve(async (req) => {
    if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

    try {
        if (!RESEND_API_KEY) throw new Error('RESEND_API_KEY not configured')

        const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
            auth: { autoRefreshToken: false, persistSession: false },
        })

        const body = await req.json()

        // Supports two modes:
        // 1. Direct call: { fan_id, tier_name, partner_name, price_monthly, current_period_end }
        // 2. Batch trigger (pg_cron): { batch: true } — scans fan_subscriptions internally
        if (body.batch) {
            // Batch: find all subscriptions expiring in exactly 3 days
            const target = new Date()
            target.setDate(target.getDate() + 3)
            const targetDate = target.toISOString().split('T')[0] // YYYY-MM-DD

            const { data: subscriptions, error } = await supabase
                .from('fan_subscriptions')
                .select(`
                    id, fan_id, current_period_end,
                    subscription_tiers!inner(name, price_monthly),
                    partners!inner(business_name)
                `)
                .eq('status', 'active')
                .gte('current_period_end', `${targetDate}T00:00:00Z`)
                .lt('current_period_end', `${targetDate}T23:59:59Z`)

            if (error) throw error

            let sent = 0
            for (const sub of subscriptions ?? []) {
                try {
                    const { data: user } = await supabase
                        .from('users')
                        .select('email, display_name')
                        .eq('id', sub.fan_id)
                        .single()

                    if (!user?.email) continue

                    const tier = sub.subscription_tiers as any
                    const partner = sub.partners as any
                    const renewalDate = new Date(sub.current_period_end).toLocaleDateString('en-PH', {
                        year: 'numeric', month: 'long', day: 'numeric',
                    })

                    await fetch('https://api.resend.com/emails', {
                        method: 'POST',
                        headers: {
                            Authorization: `Bearer ${RESEND_API_KEY}`,
                            'Content-Type': 'application/json',
                        },
                        body: JSON.stringify({
                            from: 'HangHut Memberships <memberships@hanghut.com>',
                            to: [user.email],
                            subject: `Your ${partner.business_name} membership renews in 3 days`,
                            html: buildHtml({
                                fan_name: user.display_name ?? '',
                                tier_name: tier.name,
                                partner_name: partner.business_name,
                                price_monthly: tier.price_monthly,
                                renewal_date: renewalDate,
                            }),
                        }),
                    })
                    sent++
                } catch (e) {
                    console.error(`⚠️ Failed reminder for sub ${sub.id}:`, e)
                }
            }

            return new Response(JSON.stringify({ success: true, sent }), {
                headers: { ...corsHeaders, 'Content-Type': 'application/json' },
            })
        }

        // Single send (direct call from web)
        const { fan_id, tier_name, partner_name, price_monthly, current_period_end } = body
        if (!fan_id || !tier_name || !partner_name) {
            return new Response(JSON.stringify({ error: 'Missing required fields' }), { status: 400, headers: corsHeaders })
        }

        const { data: user, error: userError } = await supabase
            .from('users')
            .select('email, display_name')
            .eq('id', fan_id)
            .single()

        if (userError || !user?.email) {
            return new Response(JSON.stringify({ error: 'Fan not found' }), { status: 404, headers: corsHeaders })
        }

        const renewalDate = new Date(current_period_end).toLocaleDateString('en-PH', {
            year: 'numeric', month: 'long', day: 'numeric',
        })

        const res = await fetch('https://api.resend.com/emails', {
            method: 'POST',
            headers: {
                Authorization: `Bearer ${RESEND_API_KEY}`,
                'Content-Type': 'application/json',
            },
            body: JSON.stringify({
                from: 'HangHut Memberships <memberships@hanghut.com>',
                to: [user.email],
                subject: `Your ${partner_name} membership renews in 3 days`,
                html: buildHtml({
                    fan_name: user.display_name ?? '',
                    tier_name,
                    partner_name,
                    price_monthly,
                    renewal_date: renewalDate,
                }),
            }),
        })

        if (!res.ok) throw new Error(`Resend error: ${await res.text()}`)
        const data = await res.json()
        console.log(`✅ Renewal reminder sent to ${user.email} (${data.id})`)

        return new Response(JSON.stringify({ success: true, id: data.id }), {
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        })
    } catch (err: any) {
        console.error('send-subscription-renewal-reminder error:', err)
        return new Response(JSON.stringify({ error: err.message }), {
            status: 400,
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        })
    }
})
