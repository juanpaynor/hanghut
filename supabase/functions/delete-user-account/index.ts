import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

/**
 * delete-user-account
 * 
 * Supports two modes:
 *   1. SELF-DELETION: Authenticated user deletes their own account (no body needed, uses JWT)
 *   2. ADMIN DELETION: Admin deletes another user's account ({ user_id, reason })
 * 
 * Cascades deletion across all user data: DB rows, Storage files, and Auth record.
 */

serve(async (req) => {
    if (req.method === 'OPTIONS') {
        return new Response('ok', { headers: corsHeaders })
    }

    try {
        const supabaseUrl = Deno.env.get('SUPABASE_URL')!
        const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
        const supabase = createClient(supabaseUrl, supabaseKey)

        // Determine who is calling: self-deletion or admin-deletion
        let targetUserId: string
        let reason = 'User requested account deletion'
        let isAdminAction = false

        // Parse body (may be empty for self-deletion)
        let body: { user_id?: string; admin_id?: string; reason?: string } = {}
        try {
            body = await req.json()
        } catch {
            // Empty body is fine for self-deletion
        }

        if (body.admin_id && body.user_id) {
            // ADMIN MODE: verify admin privileges
            const { data: admin } = await supabase
                .from('users')
                .select('is_admin')
                .eq('id', body.admin_id)
                .single()

            if (admin?.is_admin !== true) {
                // DB fallback: check JWT caller
                const authHeader = req.headers.get('Authorization')
                if (authHeader) {
                    const token = authHeader.replace('Bearer ', '')
                    const { data: { user: jwtUser } } = await supabase.auth.getUser(token)
                    if (jwtUser) {
                        const { data: dbAdmin } = await supabase
                            .from('users')
                            .select('is_admin')
                            .eq('id', jwtUser.id)
                            .maybeSingle()
                        if (dbAdmin?.is_admin !== true) {
                            return new Response(
                                JSON.stringify({ error: 'Unauthorized: Admin privileges required' }),
                                { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
                            )
                        }
                    }
                }
            }

            targetUserId = body.user_id
            reason = body.reason || 'Account deleted by admin'
            isAdminAction = true
        } else {
            // SELF-DELETION MODE: resolve user from JWT
            const authHeader = req.headers.get('Authorization')
            if (!authHeader) {
                return new Response(
                    JSON.stringify({ error: 'Missing authorization header' }),
                    { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
                )
            }

            const token = authHeader.replace('Bearer ', '')
            const { data: { user }, error: userError } = await supabase.auth.getUser(token)

            if (userError || !user) {
                return new Response(
                    JSON.stringify({ error: 'Invalid or expired token' }),
                    { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
                )
            }

            targetUserId = user.id
            reason = body.reason || 'User requested account deletion'
        }

        console.log(`🗑️ Starting account deletion for user ${targetUserId} (admin: ${isAdminAction})`)

        // ─── STEP 1: Delete Storage files ───────────────────────────────
        const buckets = [
            { name: 'profile-photos', prefix: targetUserId },
            { name: 'post_images', prefix: targetUserId },
            { name: 'social_images', prefix: targetUserId },
            { name: 'social_videos', prefix: targetUserId },
            { name: 'chat-images', prefix: targetUserId },
        ]

        for (const bucket of buckets) {
            try {
                const { data: files } = await supabase.storage
                    .from(bucket.name)
                    .list(bucket.prefix, { limit: 1000 })

                if (files && files.length > 0) {
                    const paths = files.map(f => `${bucket.prefix}/${f.name}`)
                    const { error: deleteError } = await supabase.storage
                        .from(bucket.name)
                        .remove(paths)

                    if (deleteError) {
                        console.warn(`⚠️ Storage cleanup failed for ${bucket.name}: ${deleteError.message}`)
                    } else {
                        console.log(`✅ Deleted ${paths.length} files from ${bucket.name}`)
                    }
                }
            } catch (e) {
                console.warn(`⚠️ Could not clean storage bucket ${bucket.name}: ${e}`)
            }
        }

        // ─── STEP 2: Delete DB rows (order matters for FK constraints) ──
        const deleteOps = [
            // Reactions & messages
            { table: 'message_reactions', column: 'user_id' },
            { table: 'messages', column: 'sender_id' },
            { table: 'direct_messages', column: 'sender_id' },
            { table: 'trip_messages', column: 'sender_id' },

            // Chat participations
            { table: 'direct_chat_participants', column: 'user_id' },
            { table: 'trip_chat_participants', column: 'user_id' },

            // Group & table memberships
            { table: 'group_members', column: 'user_id' },
            { table: 'table_members', column: 'user_id' },

            // Social content
            { table: 'post_likes', column: 'user_id' },
            { table: 'posts', column: 'user_id' },

            // Notifications
            { table: 'notifications', column: 'user_id' },
            { table: 'notifications', column: 'actor_id' },

            // Reports (by this user)
            { table: 'reports', column: 'reporter_id' },

            // Admin actions referencing this user (FK constraint blocker)
            { table: 'admin_actions', column: 'target_user_id' },
        ]

        for (const op of deleteOps) {
            try {
                const { error } = await supabase
                    .from(op.table)
                    .delete()
                    .eq(op.column, targetUserId)

                if (error) {
                    console.warn(`⚠️ Failed to delete from ${op.table}.${op.column}: ${error.message}`)
                } else {
                    console.log(`✅ Cleaned ${op.table}.${op.column}`)
                }
            } catch (e) {
                console.warn(`⚠️ Error cleaning ${op.table}: ${e}`)
            }
        }

        // ─── STEP 3: Delete user profile row ────────────────────────────
        const { error: profileError } = await supabase
            .from('users')
            .delete()
            .eq('id', targetUserId)

        if (profileError) {
            console.error(`❌ Failed to delete user profile: ${profileError.message}`)
        } else {
            console.log('✅ Deleted user profile')
        }

        // ─── STEP 4: Delete auth record ─────────────────────────────────
        const { error: authError } = await supabase.auth.admin.deleteUser(targetUserId)
        if (authError) {
            console.error(`❌ Failed to delete auth user: ${authError.message}`)
        } else {
            console.log('✅ Deleted auth user')
        }

        // ─── STEP 5: Log the action (if admin) ─────────────────────────
        if (isAdminAction && body.admin_id) {
            await supabase.from('admin_actions').insert({
                admin_id: body.admin_id,
                action_type: 'delete',
                target_user_id: targetUserId,
                reason,
                metadata: { hard_delete: true, self_service: false },
            })
        }

        console.log(`🗑️ Account deletion complete for user ${targetUserId}`)

        return new Response(
            JSON.stringify({
                success: true,
                message: 'Account and all associated data deleted',
                user_id: targetUserId,
            }),
            { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
    } catch (error) {
        console.error('❌ Account deletion error:', error)
        return new Response(
            JSON.stringify({ error: error.message }),
            { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
    }
})
