import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

interface NotificationPayload {
  user_id: string
  title: string
  body: string
  data?: Record<string, string>
}

async function getAccessToken(): Promise<string> {
  const serviceAccount = JSON.parse(Deno.env.get('FIREBASE_SERVICE_ACCOUNT') || '{}')
  if (!serviceAccount.client_email || !serviceAccount.private_key) {
    throw new Error('Missing FIREBASE_SERVICE_ACCOUNT credentials');
  }

  // Helper to convert to base64url encoding (URL-safe)
  const base64url = (input: string): string => {
    const base64 = btoa(input);
    return base64.replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '');
  };

  const header = base64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }))
  const now = Math.floor(Date.now() / 1000)
  const claim = base64url(JSON.stringify({
    iss: serviceAccount.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token',
    exp: now + 3600,
    iat: now,
  }))

  const signatureInput = `${header}.${claim}`

  // Robustly extract key content: handle \n literals and remove headers/whitespace
  const pem = serviceAccount.private_key.replace(/\\n/g, '\n');
  const pemContents = pem
    .replace(/-----BEGIN PRIVATE KEY-----/g, '')
    .replace(/-----END PRIVATE KEY-----/g, '')
    .replace(/\s/g, '');

  // decode base64
  const binaryDerString = atob(pemContents);
  const binaryDer = new Uint8Array(binaryDerString.length);
  for (let i = 0; i < binaryDerString.length; i++) {
    binaryDer[i] = binaryDerString.charCodeAt(i);
  }

  // Import private key
  const privateKey = await crypto.subtle.importKey(
    'pkcs8',
    binaryDer,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign']
  )

  // Sign the JWT
  const signature = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    privateKey,
    new TextEncoder().encode(signatureInput)
  )

  // Convert signature to base64url
  const signatureArray = new Uint8Array(signature);
  const signatureBase64 = btoa(String.fromCharCode(...signatureArray));
  const signatureBase64url = signatureBase64.replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '');

  const jwt = `${signatureInput}.${signatureBase64url}`

  // Exchange JWT for access token
  const response = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`,
  })

  if (!response.ok) {
    const errorText = await response.text();
    console.error('OAuth2 Token Error:', response.status, errorText);
    throw new Error(`Failed to get access token: ${response.status} ${errorText}`);
  }

  const { access_token } = await response.json()
  return access_token
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const rawBody = await req.text()
    console.log('📨 Raw request body:', rawBody)

    let payload;
    try {
      payload = JSON.parse(rawBody)
    } catch (parseError) {
      console.error('❌ JSON Parse Error:', parseError)
      return new Response(
        JSON.stringify({ error: 'Invalid JSON payload', details: parseError.message }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    console.log('📦 Parsed payload:', JSON.stringify(payload, null, 2))

    const { user_id, title, body, data } = payload as NotificationPayload

    if (!user_id || !title || !body) {
      console.error('❌ Missing required fields:', { user_id, title, body })
      return new Response(
        JSON.stringify({ error: 'Missing required fields: user_id, title, body' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Initialize Supabase client
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const supabase = createClient(supabaseUrl, supabaseKey)

    // Fetch user's FCM token and avatar
    const { data: user, error: userError } = await supabase
      .from('users')
      .select('fcm_token, avatar_url')
      .eq('id', user_id)
      .single()

    if (userError || !user?.fcm_token) {
      return new Response(
        JSON.stringify({ error: 'User FCM token not found' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Get OAuth access token
    const accessToken = await getAccessToken()
    const serviceAccount = JSON.parse(Deno.env.get('FIREBASE_SERVICE_ACCOUNT') || '{}')
    const projectId = serviceAccount.project_id

    // Send notification via FCM V1 API
    const fcmResponse = await fetch(
      `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
      {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${accessToken}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          message: {
            token: user.fcm_token,
            notification: {
              title,
              body,
              image: user.avatar_url || undefined, // Include user avatar if available
            },
            data: data || {},
            apns: {
              payload: {
                aps: {
                  sound: 'default', // iOS notification sound
                  badge: 1,
                  'mutable-content': 1, // Enables notification content extension
                },
              },
              fcm_options: {
                image: user.avatar_url || undefined,
              },
            },
            android: {
              priority: 'high',
              notification: {
                sound: 'default', // Android notification sound
                click_action: 'FLUTTER_NOTIFICATION_CLICK',
                color: '#8B5CF6', // Purple notification color
                icon: 'ic_notification', // Will use default if not found
                image: user.avatar_url || undefined,
                channel_id: 'hanghut_social', // Notification channel
              },
            },
          },
        }),
      }
    )

    const fcmResult = await fcmResponse.json()

    if (!fcmResponse.ok) {
      console.error('FCM Error:', fcmResult)
      return new Response(
        JSON.stringify({ error: 'Failed to send notification', details: fcmResult }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    return new Response(
      JSON.stringify({ success: true, message_id: fcmResult.name }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  } catch (error) {
    console.error('Error in send-push function:', error)
    console.error('Error name:', error.name)
    console.error('Error message:', error.message)
    console.error('Error stack:', error.stack)
    return new Response(
      JSON.stringify({
        error: error.message,
        errorName: error.name,
        errorStack: error.stack
      }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
