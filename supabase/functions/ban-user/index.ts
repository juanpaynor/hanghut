import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

interface BanUserRequest {
    user_id: string
    action: 'ban' | 'suspend' | 'activate'
    reason?: string
    admin_id: string
}

serve(async (req) => {
    if (req.method === 'OPTIONS') {
        return new Response('ok', { headers: corsHeaders })
    }

    try {
        const { user_id, action, reason, admin_id }: BanUserRequest = await req.json()

        // Validate inputs
        if (!user_id || !action || !admin_id) {
            return new Response(
                JSON.stringify({ error: 'Missing required fields' }),
                { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
            )
        }

        // Initialize Supabase client with service role (has admin permissions)
        const supabaseUrl = Deno.env.get('SUPABASE_URL')!
        const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
        const supabase = createClient(supabaseUrl, supabaseKey)

        // Verify admin has permission (check if admin_id has is_admin = true)
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

        // Map action to status
        const statusMap = {
            'ban': 'banned',
            'suspend': 'suspended',
            'activate': 'active',
        }

        const newStatus = statusMap[action]

        // Update user status
        const { error: updateError } = await supabase
            .from('users')
            .update({
                status: newStatus,
                status_reason: reason || null,
                status_changed_at: new Date().toISOString(),
                status_changed_by: admin_id,
            })
            .eq('id', user_id)

        if (updateError) {
            throw updateError
        }

        // Log admin action
        await supabase
            .from('admin_actions')
            .insert({
                admin_id,
                action_type: action,
                target_user_id: user_id,
                reason: reason || null,
                metadata: {
                    previous_status: 'active', // Could fetch this if needed
                    new_status: newStatus,
                },
            })

        return new Response(
            JSON.stringify({
                success: true,
                message: `User ${action}ed successfully`,
                user_id,
                new_status: newStatus,
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
