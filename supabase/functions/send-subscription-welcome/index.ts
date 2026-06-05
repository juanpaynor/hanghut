import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY')
const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

// Perk type → human-readable label and icon
const PERK_ICONS: Record<string, string> = {
    gated_posts: '📝',
    digital_download: '⬇️',
    community_link: '💬',
    merch: '🎁',
    shoutout: '📣',
    early_access: '⚡',
    subscriber_chat: '💬',
    custom: '✨',
}

function perkIcon(type: string): string {
    return PERK_ICONS[type] ?? '✨'
}

function buildHtml(data: {
    fan_name: string
    tier_name: string
    partner_name: string
    partner_slug: string
    price_monthly: number
    current_period_end: string
    perks: { type: string; label: string }[]
    is_renewal: boolean
}): string {
    const renewalDate = new Date(data.current_period_end).toLocaleDateString('en-PH', {
        year: 'numeric', month: 'long', day: 'numeric',
    })
    const priceFormatted = `₱${data.price_monthly.toLocaleString()}/mo`
    const greeting = data.is_renewal
        ? `Your <strong>${data.tier_name}</strong> membership with <strong>${data.partner_name}</strong> has been renewed.`
        : `You're now a <strong>${data.tier_name}</strong> member of <strong>${data.partner_name}</strong>!`

    const perksHtml = data.perks.length > 0
        ? `<div style="margin:24px 0">
            <p style="margin:0 0 12px;font-size:14px;color:#6b7280;font-weight:600;text-transform:uppercase;letter-spacing:.05em">What you've unlocked</p>
            ${data.perks.map(p => `
            <div style="display:flex;align-items:center;gap:10px;padding:10px 0;border-bottom:1px solid #f3f4f6">
                <span style="font-size:20px">${perkIcon(p.type)}</span>
                <span style="font-size:15px;color:#111827">${p.label}</span>
            </div>`).join('')}
          </div>`
        : ''

    return `<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"></head>
<body style="margin:0;padding:0;background:#f9fafb;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif">
  <div style="max-width:560px;margin:40px auto;background:#fff;border-radius:16px;overflow:hidden;box-shadow:0 1px 3px rgba(0,0,0,.1)">
    <!-- Header -->
    <div style="background:linear-gradient(135deg,#7c3aed,#a855f7);padding:32px 32px 24px;text-align:center">
      <p style="margin:0 0 8px;font-size:28px">👑</p>
      <h1 style="margin:0;font-size:22px;font-weight:800;color:#fff">
        ${data.is_renewal ? 'Membership Renewed' : 'Welcome to the members club!'}
      </h1>
    </div>
    <!-- Body -->
    <div style="padding:32px">
      <p style="margin:0 0 16px;font-size:16px;color:#111827">Hi ${data.fan_name || 'there'},</p>
      <p style="margin:0 0 20px;font-size:16px;color:#374151;line-height:1.6">${greeting}</p>
      <!-- Membership details -->
      <div style="background:#f5f3ff;border-radius:12px;padding:20px;margin-bottom:24px">
        <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:8px">
          <span style="font-size:14px;color:#6b7280">Plan</span>
          <span style="font-size:15px;font-weight:700;color:#7c3aed">${data.tier_name}</span>
        </div>
        <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:8px">
          <span style="font-size:14px;color:#6b7280">Amount</span>
          <span style="font-size:15px;font-weight:600;color:#111827">${priceFormatted}</span>
        </div>
        <div style="display:flex;justify-content:space-between;align-items:center">
          <span style="font-size:14px;color:#6b7280">${data.is_renewal ? 'Next renewal' : 'Renews'}</span>
          <span style="font-size:15px;font-weight:600;color:#111827">${renewalDate}</span>
        </div>
      </div>
      ${perksHtml}
      <!-- CTA -->
      <div style="text-align:center;margin:28px 0 8px">
        <a href="https://hanghut.com/${data.partner_slug}/membership"
           style="display:inline-block;background:#7c3aed;color:#fff;text-decoration:none;font-size:16px;font-weight:700;padding:14px 32px;border-radius:12px">
          View your membership →
        </a>
      </div>
    </div>
    <!-- Footer -->
    <div style="padding:20px 32px;border-top:1px solid #f3f4f6;text-align:center">
      <p style="margin:0;font-size:12px;color:#9ca3af">
        Manage your membership at
        <a href="https://hanghut.com/account" style="color:#7c3aed;text-decoration:none">hanghut.com/account</a>
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

        const body = await req.json()
        const { fan_id, tier_name, partner_name, partner_slug, price_monthly, current_period_end, perks = [], is_renewal = false } = body

        if (!fan_id || !tier_name || !partner_name) {
            return new Response(JSON.stringify({ error: 'Missing required fields' }), { status: 400, headers: corsHeaders })
        }

        // Fetch fan email + name from users table
        const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
            auth: { autoRefreshToken: false, persistSession: false },
        })
        const { data: user, error: userError } = await supabase
            .from('users')
            .select('email, display_name')
            .eq('id', fan_id)
            .single()

        if (userError || !user?.email) {
            console.error('Could not fetch fan email:', userError)
            return new Response(JSON.stringify({ error: 'Fan not found' }), { status: 404, headers: corsHeaders })
        }

        const subject = is_renewal
            ? `Your ${tier_name} membership has renewed`
            : `Welcome to ${partner_name} membership! 👑`

        const html = buildHtml({
            fan_name: user.display_name ?? '',
            tier_name,
            partner_name,
            partner_slug,
            price_monthly,
            current_period_end,
            perks,
            is_renewal,
        })

        const res = await fetch('https://api.resend.com/emails', {
            method: 'POST',
            headers: {
                Authorization: `Bearer ${RESEND_API_KEY}`,
                'Content-Type': 'application/json',
            },
            body: JSON.stringify({
                from: `HangHut Memberships <memberships@hanghut.com>`,
                to: [user.email],
                subject,
                html,
            }),
        })

        if (!res.ok) {
            const err = await res.text()
            throw new Error(`Resend error: ${err}`)
        }

        const data = await res.json()
        console.log(`✅ Subscription ${is_renewal ? 'renewal' : 'welcome'} email sent to ${user.email} (${data.id})`)

        return new Response(JSON.stringify({ success: true, id: data.id }), {
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        })
    } catch (err: any) {
        console.error('send-subscription-welcome error:', err)
        return new Response(JSON.stringify({ error: err.message }), {
            status: 400,
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        })
    }
})
