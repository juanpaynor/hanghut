/**
 * ============================================================================
 * PUSH NOTIFICATION QUEUE CONSUMER — VERSION 1
 * ============================================================================
 *
 * Processes push notification messages from the `push_notifications` queue.
 * Instead of 1 edge-function call per notification (old approach), this:
 *   1. Reads up to 50 messages in one batch
 *   2. Fetches ALL recipient FCM tokens in a single DB query
 *   3. Authenticates with Google FCM once
 *   4. Sends all notifications via individual FCM calls (batched in parallel)
 *
 * Triggered by pg_cron every 5 seconds.
 * Failed messages stay in the queue and are retried on the next run.
 * ============================================================================
 */

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { JWT } from 'npm:google-auth-library@8'

const QUEUE_NAME = 'push_notifications'
const BATCH_SIZE = 50
const VISIBILITY_TIMEOUT = 60
// Max parallel FCM sends per batch to avoid overwhelming the network
const FCM_CONCURRENCY = 20

serve(async (_req) => {
  const supabase = createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
  )

  // 1. Read batch of messages from the queue
  const { data: messages, error: readError } = await supabase
    .rpc('pgmq_read', {
      queue_name: QUEUE_NAME,
      sleep_seconds: 0,
      batch_size: BATCH_SIZE,
    })

  if (readError) {
    console.error('❌ Queue read error:', readError)
    return new Response(JSON.stringify({ error: readError.message }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    })
  }

  if (!messages || messages.length === 0) {
    return new Response(JSON.stringify({ processed: 0 }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    })
  }

  console.log(`📬 Processing ${messages.length} push notifications...`)

  // 2. Collect unique user_ids and fetch their FCM tokens in one query
  const userIds = [...new Set(messages.map((m: any) => m.message.user_id).filter(Boolean))]

  const { data: users, error: usersError } = await supabase
    .from('users')
    .select('id, fcm_token')
    .in('id', userIds)
    .not('fcm_token', 'is', null)

  if (usersError) {
    console.error('❌ Users fetch error:', usersError)
    return new Response(JSON.stringify({ error: usersError.message }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    })
  }

  // Build user_id -> fcm_token map
  const tokenMap: Record<string, string> = {}
  for (const u of users ?? []) {
    if (u.fcm_token) tokenMap[u.id] = u.fcm_token
  }

  // 3. Authenticate with Google FCM once
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
  if (!accessToken) {
    console.error('❌ Failed to get FCM access token')
    return new Response(JSON.stringify({ error: 'FCM auth failed' }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    })
  }

  const projectId = serviceAccount.project_id
  const fcmUrl = `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`

  // 4. Send notifications in parallel batches
  let successCount = 0
  let skipCount = 0
  let failCount = 0
  const archiveIds: number[] = []

  // Process in chunks of FCM_CONCURRENCY
  for (let i = 0; i < messages.length; i += FCM_CONCURRENCY) {
    const chunk = messages.slice(i, i + FCM_CONCURRENCY)

    const results = await Promise.allSettled(
      chunk.map(async (msg: any) => {
        const payload = msg.message
        const token = tokenMap[payload.user_id]

        if (!token) {
          // No FCM token — skip but still archive
          skipCount++
          archiveIds.push(msg.msg_id)
          return
        }

        const fcmPayload: any = {
          message: {
            token,
            notification: {
              title: payload.title,
              body: payload.body,
            },
            data: {
              click_action: 'FLUTTER_NOTIFICATION_CLICK',
              ...(payload.data || {}),
            },
            android: {
              priority: 'high',
              notification: {},
            },
            apns: {
              payload: {
                aps: { sound: 'default' },
              },
              fcm_options: {},
            },
          },
        }

        // Add image if present
        if (payload.image) {
          fcmPayload.message.notification.image = payload.image
          fcmPayload.message.android.notification.image = payload.image
          fcmPayload.message.apns.payload.aps['mutable-content'] = 1
          fcmPayload.message.apns.fcm_options.image = payload.image
        }

        const resp = await fetch(fcmUrl, {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${accessToken}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify(fcmPayload),
        })

        if (!resp.ok) {
          const err = await resp.json()
          // If token is unregistered, still archive (don't retry)
          if (err?.error?.details?.[0]?.errorCode === 'UNREGISTERED') {
            console.warn(`⚠️ Stale token for user ${payload.user_id}, archiving`)
            archiveIds.push(msg.msg_id)
            skipCount++
            return
          }
          throw new Error(`FCM ${resp.status}: ${JSON.stringify(err)}`)
        }

        successCount++
        archiveIds.push(msg.msg_id)
      })
    )

    // Count failures (messages stay in queue for retry)
    for (const r of results) {
      if (r.status === 'rejected') {
        failCount++
        console.error('❌ FCM send failed:', r.reason)
      }
    }
  }

  // 5. Archive successfully processed messages
  if (archiveIds.length > 0) {
    for (const id of archiveIds) {
      await supabase.rpc('pgmq_archive', {
        queue_name: QUEUE_NAME,
        msg_id: id,
      })
    }
  }

  const summary = { processed: messages.length, sent: successCount, skipped: skipCount, failed: failCount }
  console.log('✅ Push queue summary:', summary)

  return new Response(JSON.stringify(summary), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  })
})
