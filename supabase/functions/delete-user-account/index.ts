import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

interface DeleteAccountRequest {
    user_id: string
    admin_id: string
    hard_delete?: boolean // true = permanent, false = soft delete (default)
    reason?: string
}

serve(async (req) => {
    if (req.method === 'OPTIONS') {
        return new Response('ok', { headers: corsHeaders })
    }

    try {
        const { user_id, admin_id, hard_delete = false, reason }: DeleteAccountRequest = await req.json()

        if (!user_id || !admin_id) {
            return new Response(
                JSON.stringify({ error: 'Missing required fields' }),
                { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
            )
        }

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

        if (hard_delete) {
            // HARD DELETE: Permanently remove all user data (GDPR compliance)

            // Delete in order (due to foreign key constraints)
            const tablesToCleanup = [
                'message_reactions',
                'messages',
                'post_likes',
                'post_comments',
                'posts',
                'table_participants',
                'tables', // Events hosted by user
                'reports', // Reports made by/against user
                'notifications',
                'admin_actions', // Keep audit trail? Or delete?
            ]

            for (const table of tablesToCleanup) {
                try {
                    await supabase.from(table).delete().eq('user_id', user_id)
                    console.log(`✅ Deleted ${table} for user ${user_id}`)
                } catch (e) {
                    console.warn(`⚠️ Could not delete from ${table}: ${e}`)
                }
            }

            // Delete from Supabase Auth
            const { error: authError } = await supabase.auth.admin.deleteUser(user_id)
            if (authError) {
                console.error('Auth delete error:', authError)
            }

            // Delete user record
            await supabase.from('users').delete().eq('id', user_id)

            // Log deletion
            await supabase
                .from('admin_actions')
                .insert({
                    admin_id,
                    action_type: 'delete',
                    target_user_id: user_id,
                    reason: reason || 'Account permanently deleted by admin',
                    metadata: { hard_delete: true },
                })

            return new Response(
                JSON.stringify({
                    success: true,
                    message: 'User account permanently deleted',
                    user_id,
                    hard_delete: true,
                }),
                { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
            )
        } else {
            // SOFT DELETE: Mark as deleted but keep data
            const { error: updateError } = await supabase
                .from('users')
                .update({
                    status: 'deleted',
                    deleted_at: new Date().toISOString(),
                    status_reason: reason || 'Account deleted by admin',
                    status_changed_by: admin_id,
                    // Optionally anonymize personal data
                    email: `deleted_${user_id}@deleted.com`,
                    display_name: 'Deleted User',
                    avatar_url: null,
                })
                .eq('id', user_id)

            if (updateError) {
                throw updateError
            }

            // Disable auth account (but don't delete)
            // Note: Supabase doesn't have a "disable" API, so we'd need to handle this at app level

            // Log deletion
            await supabase
                .from('admin_actions')
                .insert({
                    admin_id,
                    action_type: 'delete',
                    target_user_id: user_id,
                    reason: reason || 'Account soft deleted by admin',
                    metadata: { hard_delete: false },
                })

            return new Response(
                JSON.stringify({
                    success: true,
                    message: 'User account soft deleted (data retained)',
                    user_id,
                    hard_delete: false,
                }),
                { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
            )
        }
    } catch (error) {
        console.error('Error:', error)
        return new Response(
            JSON.stringify({ error: error.message }),
            { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
    }
})
