import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

interface ResetPasswordRequest {
    user_email: string
    admin_id: string
}

serve(async (req) => {
    if (req.method === 'OPTIONS') {
        return new Response('ok', { headers: corsHeaders })
    }

    try {
        const { user_email, admin_id }: ResetPasswordRequest = await req.json()

        if (!user_email || !admin_id) {
            return new Response(
                JSON.stringify({ error: 'Missing required fields' }),
                { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
            )
        }

        // Initialize Supabase client
        const supabaseUrl = Deno.env.get('SUPABASE_URL')!
        const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
        const supabase = createClient(supabaseUrl, supabaseKey)

        // Verify admin permission
        const { data: admin, error: adminError } = await supabase
            .from('users')
            .select('is_admin')
            .eq('id', admin_id)
            .single()

        if (adminError || admin?.is_admin !== true) {
            return new Response(
                JSON.stringify({ error: 'Unauthorized: Admin privileges required' }),
                { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
            )
        }

        // Get user ID from email
        const { data: user, error: userError } = await supabase
            .from('users')
            .select('id')
            .eq('email', user_email)
            .single()

        if (userError || !user) {
            return new Response(
                JSON.stringify({ error: 'User not found' }),
                { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
            )
        }

        // Trigger password reset email using Supabase Auth Admin API
        const { error: resetError } = await supabase.auth.admin.generateLink({
            type: 'recovery',
            email: user_email,
        })

        if (resetError) {
            throw resetError
        }

        // Log admin action
        await supabase
            .from('admin_actions')
            .insert({
                admin_id,
                action_type: 'reset_password',
                target_user_id: user.id,
                reason: 'Password reset triggered by admin',
            })

        return new Response(
            JSON.stringify({
                success: true,
                message: 'Password reset email sent',
                user_email,
            }),
            { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
    } catch (error) {
        console.error('Error:', error)
        return new Response(
            JSON.stringify({ error: error.message }),
            { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
    }
})
