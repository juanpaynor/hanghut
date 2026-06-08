/**
 * sync-payout-statuses
 *
 * Safety net for payouts stuck in 'processing' because Xendit's
 * payout.succeeded / payout.failed webhooks were missed or not configured.
 *
 * Runs on pg_cron every 4 hours. For each payout that has been 'processing'
 * for more than 2 hours, calls GET /v2/payouts/{xendit_disbursement_id} and
 * syncs the result back to our payouts table.
 *
 * Xendit V2 payout statuses:
 *   ACCEPTED, LOCKED → still in-flight → leave as 'processing'
 *   SUCCEEDED        → completed
 *   FAILED, CANCELLED → failed (also unlinks transactions so balance is restored)
 */

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  const xenditKey = Deno.env.get('XENDIT_SECRET_KEY')
  const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''

  if (!xenditKey) {
    return new Response(JSON.stringify({ error: 'Missing XENDIT_SECRET_KEY' }), {
      status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }

  const supabase = createClient(supabaseUrl, serviceKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  })

  // Fetch payouts stuck in processing for > 2 hours
  const { data: stuckPayouts, error: fetchError } = await supabase
    .from('payouts')
    .select('id, xendit_disbursement_id, partner_id, amount')
    .eq('status', 'processing')
    .lt('updated_at', new Date(Date.now() - 2 * 60 * 60 * 1000).toISOString())
    .not('xendit_disbursement_id', 'is', null)

  if (fetchError) {
    console.error('❌ Failed to fetch stuck payouts:', fetchError)
    return new Response(JSON.stringify({ error: fetchError.message }), {
      status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }

  if (!stuckPayouts || stuckPayouts.length === 0) {
    console.log('✅ No stuck payouts found')
    return new Response(JSON.stringify({ synced: 0, skipped: 0 }), {
      status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }

  console.log(`🔍 Checking ${stuckPayouts.length} stuck payout(s)...`)

  const authHeader = `Basic ${btoa(xenditKey + ':')}`
  let synced = 0
  let skipped = 0

  for (const payout of stuckPayouts) {
    try {
      const res = await fetch(
        `https://api.xendit.co/v2/payouts/${payout.xendit_disbursement_id}`,
        { headers: { Authorization: authHeader } },
      )

      if (!res.ok) {
        console.warn(`⚠️ Xendit returned ${res.status} for payout ${payout.id} — skipping`)
        skipped++
        continue
      }

      const xenditPayout = await res.json()
      const xenditStatus: string = xenditPayout.status ?? ''

      console.log(`  Payout ${payout.id}: Xendit status = ${xenditStatus}`)

      if (xenditStatus === 'SUCCEEDED') {
        await supabase
          .from('payouts')
          .update({ status: 'completed', completed_at: new Date().toISOString() })
          .eq('id', payout.id)
        console.log(`  ✅ Marked completed`)
        synced++

      } else if (xenditStatus === 'FAILED' || xenditStatus === 'CANCELLED') {
        await supabase
          .from('payouts')
          .update({
            status: 'failed',
            admin_notes: `Auto-synced from Xendit: ${xenditStatus}`,
          })
          .eq('id', payout.id)

        // Unlink transactions so balance is restored
        await Promise.all([
          supabase.from('transactions').update({ payout_id: null }).eq('payout_id', payout.id),
          supabase.from('experience_transactions').update({ payout_id: null }).eq('payout_id', payout.id),
        ])

        console.log(`  ❌ Marked failed, transactions unlinked`)
        synced++

      } else {
        // ACCEPTED, LOCKED — still in-flight, leave it
        console.log(`  ⏳ Still in-flight (${xenditStatus}) — leaving as processing`)
        skipped++
      }
    } catch (e) {
      console.error(`  ❌ Error processing payout ${payout.id}:`, e)
      skipped++
    }
  }

  console.log(`Done — synced: ${synced}, skipped: ${skipped}`)

  return new Response(JSON.stringify({ synced, skipped }), {
    status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
})
