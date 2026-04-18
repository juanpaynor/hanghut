/**
 * ============================================================================
 * PAYMENT QUEUE CONSUMER — VERSION 1
 * ============================================================================
 *
 * Processes side-effect messages from the `payment_side_effects` queue.
 * This decouples non-critical work (push notifications, emails, partner
 * webhooks) from the xendit-webhook handler so it can return 200 fast.
 *
 * Message types:
 *   - send_push          → invoke send-push edge function
 *   - send_ticket_email  → invoke send-ticket-email edge function
 *   - send_experience_email → invoke send-experience-confirmation edge function
 *   - partner_webhook    → POST to partner webhook dispatch endpoint
 *
 * Triggered by pg_cron every 10 seconds. Reads up to 20 messages per run.
 * Failed messages stay in the queue and are retried on the next run.
 * ============================================================================
 */

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const QUEUE_NAME = 'payment_side_effects'
const BATCH_SIZE = 20
const VISIBILITY_TIMEOUT = 60 // seconds — message hidden from other readers while processing

serve(async (req) => {
  const supabase = createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
  )

  // Read batch of messages from the queue
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

  console.log(`📬 Processing ${messages.length} queued side-effects...`)

  let successCount = 0
  let failCount = 0

  for (const msg of messages) {
    try {
      const payload = msg.message
      const type = payload?.type

      switch (type) {
        case 'send_push': {
          const { error } = await supabase.functions.invoke('send-push', {
            body: payload.data,
          })
          if (error) throw new Error(`send-push failed: ${error.message}`)
          console.log(`✅ Push sent to user ${payload.data?.user_id}`)
          break
        }

        case 'send_ticket_email': {
          const { error } = await supabase.functions.invoke('send-ticket-email', {
            body: payload.data,
          })
          if (error) throw new Error(`send-ticket-email failed: ${error.message}`)
          console.log(`✅ Ticket email sent to ${payload.data?.email}`)
          break
        }

        case 'send_experience_email': {
          const { error } = await supabase.functions.invoke('send-experience-confirmation', {
            body: payload.data,
          })
          if (error) throw new Error(`send-experience-confirmation failed: ${error.message}`)
          console.log(`✅ Experience email sent to ${payload.data?.email}`)
          break
        }

        case 'partner_webhook': {
          const webhookSecret = Deno.env.get('WEBHOOK_INTERNAL_SECRET')
          const appUrl = Deno.env.get('APP_URL') || 'https://hanghut.com'
          if (webhookSecret) {
            const resp = await fetch(`${appUrl}/api/v1/internal/dispatch-webhook`, {
              method: 'POST',
              headers: {
                'Content-Type': 'application/json',
                'Authorization': `Bearer ${webhookSecret}`,
              },
              body: JSON.stringify(payload.data),
            })
            if (!resp.ok) {
              throw new Error(`Partner webhook failed: ${resp.status} ${resp.statusText}`)
            }
            console.log(`✅ Partner webhook dispatched: ${payload.data?.event_type}`)
          } else {
            console.warn('⚠️ WEBHOOK_INTERNAL_SECRET not set, skipping partner webhook')
          }
          break
        }

        default:
          console.warn(`⚠️ Unknown message type: ${type}`, payload)
      }

      // Success — delete from queue
      const { error: deleteError } = await supabase
        .rpc('pgmq_delete', {
          queue_name: QUEUE_NAME,
          msg_id: msg.msg_id,
        })

      if (deleteError) {
        console.error(`⚠️ Failed to delete msg ${msg.msg_id}:`, deleteError)
      }

      successCount++
    } catch (err) {
      // Message stays in queue, will be retried after visibility timeout
      console.error(`❌ Failed to process msg ${msg.msg_id} (will retry):`, err)
      failCount++
    }
  }

  console.log(`📬 Done: ${successCount} succeeded, ${failCount} failed (will retry)`)

  return new Response(
    JSON.stringify({ processed: successCount, failed: failCount, total: messages.length }),
    { status: 200, headers: { 'Content-Type': 'application/json' } }
  )
})
