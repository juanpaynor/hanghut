import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { JWT } from 'npm:google-auth-library@8'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const { user_id, title, body, image, data } = await req.json()
    console.log(`📦 Parsed payload:`, { user_id, title, body, image, data })

    if (!user_id || !title || !body) {
      return new Response(
        JSON.stringify({ error: 'Missing required fields' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const supabaseUrl = Deno.env.get('SUPABASE_URL')
    const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
    const supabase = createClient(supabaseUrl!, supabaseKey!)

    const { data: user, error: userError } = await supabase
      .from('users')
      .select('fcm_token')
      .eq('id', user_id)
      .single()

    if (userError || !user?.fcm_token) {
      console.error('User fetch error or no token:', userError)
      return new Response(
        JSON.stringify({ error: 'User not found or no FCM token' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // --- AUTHENTICATION REFACTOR: google-auth-library@8 ---
    const serviceAccount = JSON.parse(Deno.env.get('FIREBASE_SERVICE_ACCOUNT') || '{}')

    // Check if private key has newlines properly formatted
    let privateKey = serviceAccount.private_key;
    if (privateKey && privateKey.includes('\\n')) {
      privateKey = privateKey.replace(/\\n/g, '\n');
    }

    const client = new JWT({
      email: serviceAccount.client_email,
      key: privateKey,
      scopes: ['https://www.googleapis.com/auth/firebase.messaging'],
    })

    const result = await client.authorize()
    const accessToken = result.access_token

    if (!accessToken) {
      throw new Error('Failed to generate access token via google-auth-library')
    }

    // --- AUTHENTICATION REFACTOR END ---

    const projectId = serviceAccount.project_id

    // Construct FCM Message
    const messagePayload: any = {
      message: {
        token: user.fcm_token,
        notification: {
          title,
          body,
        },
        data: {
          click_action: 'FLUTTER_NOTIFICATION_CLICK',
          ...data, // Merge custom data
        },
        android: {
          priority: 'high',
          notification: {},
        },
        apns: {
          payload: {
            aps: {
              sound: 'default'
            }
          },
          fcm_options: {}
        }
      }
    };

    // Add Image to Payload if provided
    if (image) {
      console.log(`👉 Adding Image to Payload: ${image}`);
      messagePayload.message.notification.image = image;
      messagePayload.message.android.notification.image = image;
      messagePayload.message.apns.payload.aps['mutable-content'] = 1;
      messagePayload.message.apns.fcm_options.image = image;
    }

    const fcmResponse = await fetch(
      `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
      {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${accessToken}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(messagePayload),
      }
    )

    const fcmResult = await fcmResponse.json()

    if (!fcmResponse.ok) {
      console.error('FCM Error:', fcmResult);
      return new Response(
        JSON.stringify({ error: 'Failed to send notification', details: fcmResult }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    console.log('✅ FCM Success:', fcmResult);

    return new Response(
      JSON.stringify(fcmResult),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  } catch (error) {
    console.error('Unexpected error:', error)
    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
