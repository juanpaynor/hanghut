import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { JWT } from 'npm:google-auth-library@8'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const BATCH_SIZE = 500 // FCM max per multicast

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
  )

  try {
    const { broadcast_id } = await req.json()

    if (!broadcast_id) {
      return new Response(
        JSON.stringify({ error: 'Missing broadcast_id' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // 1. Fetch the broadcast record
    const { data: broadcast, error: fetchErr } = await supabase
      .from('admin_push_broadcasts')
      .select('*')
      .eq('id', broadcast_id)
      .single()

    if (fetchErr || !broadcast) {
      console.error('❌ Broadcast not found:', fetchErr)
      return new Response(
        JSON.stringify({ error: 'Broadcast not found' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Prevent re-processing
    if (broadcast.status !== 'pending') {
      console.log(`⚠️ Broadcast ${broadcast_id} already ${broadcast.status}, skipping.`)
      return new Response(
        JSON.stringify({ message: `Already ${broadcast.status}` }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // 2. Mark as processing
    await supabase
      .from('admin_push_broadcasts')
      .update({ status: 'processing' })
      .eq('id', broadcast_id)

    console.log(`📡 Processing broadcast: "${broadcast.title}"`)

    // 3. Fetch target FCM tokens based on segment
    let tokenQuery = supabase
      .from('users')
      .select('id, fcm_token')
      .not('fcm_token', 'is', null)

    const segment = broadcast.target_segment || 'all'

    if (segment === 'active_7d') {
      const cutoff = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString()
      tokenQuery = tokenQuery.gte('last_active_at', cutoff)
    } else if (segment === 'active_30d') {
      const cutoff = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString()
      tokenQuery = tokenQuery.gte('last_active_at', cutoff)
    } else if (segment.startsWith('city:')) {
      const city = segment.replace('city:', '')
      tokenQuery = tokenQuery.ilike('city', `%${city}%`)
    }
    // 'all' = no extra filter

    const { data: users, error: usersErr } = await tokenQuery

    if (usersErr) {
      console.error('❌ Error fetching users:', usersErr)
      throw new Error(usersErr.message)
    }

    const tokens = users?.map(u => u.fcm_token).filter(Boolean) ?? []
    const totalRecipients = tokens.length

    console.log(`👥 Found ${totalRecipients} recipients (segment: ${segment})`)

    await supabase
      .from('admin_push_broadcasts')
      .update({ total_recipients: totalRecipients })
      .eq('id', broadcast_id)

    if (totalRecipients === 0) {
      await supabase
        .from('admin_push_broadcasts')
        .update({ status: 'completed', sent_count: 0, completed_at: new Date().toISOString() })
        .eq('id', broadcast_id)

      return new Response(
        JSON.stringify({ message: 'No recipients found', total: 0 }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // 4. Authenticate with FCM
    const serviceAccount = JSON.parse(Deno.env.get('FIREBASE_SERVICE_ACCOUNT') || '{}')
    let privateKey = serviceAccount.private_key
    if (privateKey && privateKey.includes('\\n')) {
      privateKey = privateKey.replace(/\\n/g, '\n')
    }

    const client = new JWT({
      email: serviceAccount.client_email,
      key: privateKey,
      scopes: ['https://www.googleapis.com/auth/firebase.messaging'],
    })

    const result = await client.authorize()
    const accessToken = result.access_token
    if (!accessToken) throw new Error('Failed to get FCM access token')

    const projectId = serviceAccount.project_id

    // 5. Build message template (iOS-compatible, matching send-push structure)
    const buildMessage = (token: string) => {
      const msg: any = {
        message: {
          token,
          notification: {
            title: broadcast.title,
            body: broadcast.body,
          },
          data: {
            click_action: 'FLUTTER_NOTIFICATION_CLICK',
            type: 'broadcast',
            broadcast_id: broadcast_id,
            ...(broadcast.data_payload || {}),
          },
          android: {
            priority: 'high',
            notification: {},
          },
          apns: {
            headers: {
              'apns-priority': '10',
              'apns-push-type': 'alert',
            },
            payload: {
              aps: {
                sound: 'default',
                'content-available': 1,
              },
            },
            fcm_options: {},
          },
        },
      }

      if (broadcast.image_url) {
        msg.message.notification.image = broadcast.image_url
        msg.message.android.notification.image = broadcast.image_url
        msg.message.apns.payload.aps['mutable-content'] = 1
        msg.message.apns.fcm_options = { image: broadcast.image_url }
      }

      return msg
    }

    // 6. Send in batches
    let sentCount = 0
    let failedCount = 0

    for (let i = 0; i < tokens.length; i += BATCH_SIZE) {
      const batch = tokens.slice(i, i + BATCH_SIZE)
      console.log(`📤 Sending batch ${Math.floor(i / BATCH_SIZE) + 1} (${batch.length} tokens)`)

      const results = await Promise.allSettled(
        batch.map(async (token) => {
          const response = await fetch(
            `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
            {
              method: 'POST',
              headers: {
                'Authorization': `Bearer ${accessToken}`,
                'Content-Type': 'application/json',
              },
              body: JSON.stringify(buildMessage(token)),
            }
          )

          if (!response.ok) {
            const err = await response.json()
            // Remove stale tokens (UNREGISTERED = app uninstalled)
            if (err?.error?.details?.[0]?.errorCode === 'UNREGISTERED') {
              await supabase
                .from('users')
                .update({ fcm_token: null })
                .eq('fcm_token', token)
            }
            throw new Error(err?.error?.message || 'FCM send failed')
          }

          return response.json()
        })
      )

      for (const r of results) {
        if (r.status === 'fulfilled') sentCount++
        else failedCount++
      }

      // Progress update every batch
      await supabase
        .from('admin_push_broadcasts')
        .update({ sent_count: sentCount, failed_count: failedCount })
        .eq('id', broadcast_id)
    }

    // 7. Mark completed
    await supabase
      .from('admin_push_broadcasts')
      .update({
        status: 'completed',
        sent_count: sentCount,
        failed_count: failedCount,
        completed_at: new Date().toISOString(),
      })
      .eq('id', broadcast_id)

    console.log(`✅ Broadcast complete: ${sentCount} sent, ${failedCount} failed`)

    return new Response(
      JSON.stringify({ success: true, sent: sentCount, failed: failedCount, total: totalRecipients }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )

  } catch (error) {
    console.error('❌ Broadcast error:', error)

    // Try to mark as failed
    try {
      const { broadcast_id } = await req.clone().json()
      if (broadcast_id) {
        await supabase
          .from('admin_push_broadcasts')
          .update({ status: 'failed', error_message: error.message })
          .eq('id', broadcast_id)
      }
    } catch (_) {}

    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
