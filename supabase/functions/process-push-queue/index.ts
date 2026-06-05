/**
 * ============================================================================
 * PUSH NOTIFICATION QUEUE CONSUMER
 * ============================================================================
 *
 * Processes push notification messages from the `push_notifications` queue.
 *   1. Reads up to 50 messages in one batch
 *   2. Fetches ALL recipient FCM tokens in a single DB query
 *   3. Authenticates with Google FCM once
 *   4. Sends all notifications via individual FCM calls (batched in parallel)
 *
 * Triggered by pg_cron every 30 seconds.
 *
 * IMPORTANT: failures ALWAYS archive the message (no infinite retry).
 * Push delivery is best-effort — a failed FCM call is a stale notification,
 * not something to retry forever. Without this, a single poison-pill blocks
 * the whole queue (batch_size=50 keeps re-popping the same failures).
 * ============================================================================
 */

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { JWT } from 'npm:google-auth-library@8'

const QUEUE_NAME = 'push_notifications'
const BATCH_SIZE = 50
const VISIBILITY_TIMEOUT = 60
const FCM_CONCURRENCY = 20

serve(async (_req) => {
  const supabase = createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
  )

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

  const tokenMap: Record<string, string> = {}
  for (const u of users ?? []) {
    if (u.fcm_token) tokenMap[u.id] = u.fcm_token
  }

  console.log(`👥 Token map built for ${Object.keys(tokenMap).length} users`)

  const serviceAccount = JSON.parse(Deno.env.get('FIREBASE_SERVICE_ACCOUNT') || '{}')
  let privateKey = serviceAccount.private_key
  if (privateKey && privateKey.includes('\\n')) {
    privateKey = privateKey.replace(/\\n/g, '\n')
  }

  console.log(`🔑 Firebase project: ${serviceAccount.project_id}`)

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

  console.log('✅ FCM access token obtained')

  const projectId = serviceAccount.project_id
  const fcmUrl = `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`

  let successCount = 0
  let skipCount = 0
  let failCount = 0
  const archiveIds: number[] = []

  for (let i = 0; i < messages.length; i += FCM_CONCURRENCY) {
    const chunk = messages.slice(i, i + FCM_CONCURRENCY)

    await Promise.allSettled(
      chunk.map(async (msg: any) => {
        const payload = msg.message
        const token = tokenMap[payload.user_id]

        console.log(`📨 msg_id=${msg.msg_id} user_id=${payload.user_id} has_token=${!!token}`)

        // Best-effort delivery: ALWAYS archive to prevent poison-pill loops.
        // A failed push is a missed notification, not a reason to retry forever.
        try {
          if (!token) {
            console.warn(`⚠️ No token for user ${payload.user_id} — skipping`)
            skipCount++
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

          const respBody = await resp.json()

          if (!resp.ok) {
            const errorCode = respBody?.error?.details?.[0]?.errorCode
            console.error(`❌ FCM error for user ${payload.user_id}: status=${resp.status} code=${errorCode} body=${JSON.stringify(respBody)}`)

            if (errorCode === 'UNREGISTERED' || errorCode === 'INVALID_ARGUMENT') {
              console.warn(`⚠️ Clearing stale/invalid token for user ${payload.user_id}`)
              await supabase.from('users').update({ fcm_token: null }).eq('id', payload.user_id)
              skipCount++
              return
            }

            failCount++
            return
          }

          console.log(`✅ FCM sent to user ${payload.user_id}: ${JSON.stringify(respBody)}`)
          successCount++
        } catch (err) {
          console.error(`❌ Exception sending push to user ${payload.user_id}:`, err)
          failCount++
        } finally {
          archiveIds.push(msg.msg_id)
        }
      })
    )
  }

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
