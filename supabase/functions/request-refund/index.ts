import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req: Request) => {
    // Handle CORS preflight requests
    if (req.method === 'OPTIONS') {
        return new Response('ok', { headers: corsHeaders })
    }

    try {
        // @ts-ignore
        // Validate Env Vars
        const sbUrl = Deno.env.get('SUPABASE_URL');
        const sbAnonKey = Deno.env.get('SUPABASE_ANON_KEY');
        const sbServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
        const xenditKey = Deno.env.get('XENDIT_SECRET_KEY');
        const resendKey = Deno.env.get('RESEND_API_KEY');

        if (!sbUrl) throw new Error('Missing SUPABASE_URL');
        if (!sbAnonKey) throw new Error('Missing SUPABASE_ANON_KEY');
        if (!sbServiceKey) throw new Error('Missing SUPABASE_SERVICE_ROLE_KEY');
        if (!xenditKey) throw new Error('Missing XENDIT_SECRET_KEY');

        // @ts-ignore
        const supabaseClient = createClient(
            sbUrl,
            sbAnonKey,
            { global: { headers: { Authorization: req.headers.get('Authorization')! } } }
        )

        // Init Admin Client for fetching user email if needed
        const supabaseAdmin = createClient(sbUrl, sbServiceKey)

        // Get current user
        const {
            data: { user },
        } = await supabaseClient.auth.getUser()

        if (!user) {
            return new Response(JSON.stringify({ error: 'Unauthorized' }), {
                headers: { ...corsHeaders, 'Content-Type': 'application/json' },
                status: 401,
            })
        }

        const { intent_id, amount, reason, intent_type } = await req.json()

        if (!intent_id || !reason) {
            return new Response(JSON.stringify({ error: 'Missing intent_id or reason', code: 'MISSING_FIELD' }), {
                headers: { ...corsHeaders, 'Content-Type': 'application/json' },
                status: 400,
            })
        }

        const isExperience = intent_type === 'experience';

        // 1. Fetch Purchase Intent & Event/Experience to verify ownership
        let intent;
        let intentError;
        let organizerUserId;
        let eventOrExperienceTitle;

        if (isExperience) {
            const { data, error } = await supabaseClient
                .from('experience_purchase_intents')
                .select('*, experience:tables!table_id(title, host_id), transactions:experience_transactions(xendit_transaction_id, status)')
                .eq('id', intent_id)
                .single();

            intent = data;
            intentError = error;
            organizerUserId = intent?.experience?.host_id;
            eventOrExperienceTitle = intent?.experience?.title;
        } else {
            const { data, error } = await supabaseClient
                .from('purchase_intents')
                .select('*, event:events(title, organizer_id, organizer:partners!organizer_id(user_id)), transactions(xendit_transaction_id, status)')
                .eq('id', intent_id)
                .single();

            intent = data;
            intentError = error;
            organizerUserId = intent?.event?.organizer?.user_id;
            eventOrExperienceTitle = intent?.event?.title;
        }

        if (intentError || !intent) {
            return new Response(JSON.stringify({ error: `${isExperience ? 'Experience' : 'Event'} Purchase intent not found` }), {
                headers: { ...corsHeaders, 'Content-Type': 'application/json' },
                status: 404,
            })
        }

        // 2. Authorization Check: Only Organizer can refund (unless Admin)
        // Check if user is admin/service_role/superuser
        const isAdmin = user.app_metadata?.role === 'admin' || user.app_metadata?.role === 'service_role' || user.user_metadata?.is_admin === true;

        if (organizerUserId !== user.id && !isAdmin) {
            console.error(`Auth mismatch: organizer.user_id=${organizerUserId}, caller=${user.id}`)
            return new Response(JSON.stringify({ error: `Unauthorized: Only ${isExperience ? 'host' : 'event organizer'} can refund` }), {
                headers: { ...corsHeaders, 'Content-Type': 'application/json' },
                status: 403,
            })
        }

        // 3. Check locally if refundable
        // 3. Check locally if refundable
        if (intent.status !== 'completed') {
            console.error(`Refund failed: Intent ${intent.id} status is ${intent.status}`)
            return new Response(JSON.stringify({
                error: `Transaction is not in a refundable state (Status: ${intent.status})`,
                code: 'NOT_COMPLETED',
                current_status: intent.status
            }), {
                headers: { ...corsHeaders, 'Content-Type': 'application/json' },
                status: 400,
            })
        }

        // Get the transaction ID/Reference for Xendit
        // We try transactions table first, fallback to intent.xendit_invoice_id
        let xenditReference = intent.transactions?.[0]?.xendit_transaction_id;

        if (!xenditReference && intent.xendit_invoice_id) {
            console.log(`Using fallback xendit_invoice_id for Intent ${intent.id}`)
            xenditReference = intent.xendit_invoice_id
        }

        if (!xenditReference && intent.xendit_external_id) {
            console.log(`Searching Xendit for external_id: ${intent.xendit_external_id}`)

            // 1. Try Invoices (Legacy)
            try {
                const searchRes = await fetch(`https://api.xendit.co/v2/invoices?external_id=${intent.xendit_external_id}`, {
                    headers: { 'Authorization': `Basic ${btoa(xenditKey + ':')}` }
                })

                if (searchRes.ok) {
                    const searchData = await searchRes.json()
                    if (Array.isArray(searchData) && searchData.length > 0) {
                        xenditReference = searchData[0].id;
                        console.log(`Found missing Xendit ID via Invoice API: ${xenditReference}`)
                    }
                }
            } catch (e) {
                console.warn('Failed to search Xendit Invoices', e)
            }

            // 2. Try Payment Requests (New Sessions API)
            if (!xenditReference) {
                try {
                    console.log(`Searching Xendit Payment Requests for reference_id: ${intent.xendit_external_id}`)
                    // Payment Requests API uses 'reference_id'
                    const prRes = await fetch(`https://api.xendit.co/payment_requests?reference_id=${intent.xendit_external_id}`, {
                        headers: {
                            'Authorization': `Basic ${btoa(xenditKey + ':')}`,
                            // 'api-version': '2022-07-31' // Optional, but good practice if needed
                        }
                    })

                    if (prRes.ok) {
                        const prData = await prRes.json()
                        // Response has 'data' array
                        if (prData.data && Array.isArray(prData.data) && prData.data.length > 0) {
                            // Find the one that is SUCCEEDED potentially? Or just the first one.
                            // Ideally we want the one that is 'SUCCEEDED'
                            const successfulPr = prData.data.find((pr: any) => pr.status === 'SUCCEEDED');
                            const targetPr = successfulPr || prData.data[0];

                            if (targetPr) {
                                xenditReference = targetPr.id; // pr-...
                                console.log(`Found missing Xendit ID via Payment Request API: ${xenditReference}`)
                            }
                        }
                    } else {
                        console.warn('Payment Request search failed status:', prRes.status)
                    }
                } catch (e) {
                    console.warn('Failed to search Xendit Payment Requests', e)
                }
            }

            // Self-heal DB if found
            // Check for missing Payment Method and try to backfill
            if (!intent.payment_method || intent.payment_method === 'unknown') {
                console.log(`Payment method unknown for ${intent.id}, attempting to fetch...`);
                let fetchedMethod = null;

                if (xenditReference) {
                    // Try to fetch Invoice/PR details
                    const endpoint = xenditReference.startsWith('pr-')
                        ? `https://api.xendit.co/payment_requests/${xenditReference}`
                        : `https://api.xendit.co/v2/invoices/${xenditReference}`;

                    try {
                        const detailRes = await fetch(endpoint, {
                            headers: { 'Authorization': `Basic ${btoa(xenditKey + ':')}` }
                        });

                        if (detailRes.ok) {
                            const data = await detailRes.json();
                            // Extract logic similar to webhook
                            if (data.payment_channel) {
                                fetchedMethod = data.payment_channel;
                            } else if (data.payment_method) {
                                const pm = data.payment_method;
                                if (typeof pm === 'string') {
                                    fetchedMethod = pm;
                                } else {
                                    fetchedMethod = pm.ewallet?.channel_code ||
                                        pm.retail_outlet?.channel_code ||
                                        pm.qr_code?.channel_code ||
                                        pm.direct_debit?.channel_code ||
                                        pm.card?.channel_code ||
                                        pm.virtual_account?.channel_code ||
                                        pm.type;
                                }
                            }
                        }
                    } catch (e) {
                        console.warn('Failed to fetch Xendit details for payment method', e);
                    }
                }

                if (fetchedMethod) {
                    console.log(`✅ Backfilled payment method: ${fetchedMethod}`);
                    // Update DB
                    if (isExperience) {
                        await supabaseAdmin.from('experience_purchase_intents')
                            .update({ payment_method: fetchedMethod })
                            .eq('id', intent.id);
                    } else {
                        await supabaseAdmin.from('purchase_intents')
                            .update({ payment_method: fetchedMethod })
                            .eq('id', intent.id);
                    }

                    // Update local object for email
                    intent.payment_method = fetchedMethod;
                }
            }
        }

        if (!xenditReference) {
            // Fallback or error?
            // Note: xendit_external_id in purchase_intents is OUR reference, not Xendit's ID.
            // We need the ID returned by Xendit (e.g. pr-..., or invoice ID).
            // If we didn't save it in transactions, we might be in trouble for old data, 
            // but for new system getting it from transactions is correct.
            console.error(`Refund failed: No Xendit Information found for Intent ${intent.id}`)
            return new Response(JSON.stringify({
                error: 'Transaction record not found or missing Xendit Reference',
                code: 'MISSING_XENDIT_REF',
                details: 'Check transactions table or xendit_invoice_id. External ID lookup failed.'
            }), {
                headers: { ...corsHeaders, 'Content-Type': 'application/json' },
                status: 400,
            })
        }

        // 4. Call Xendit Refund API
        // https://api.xendit.co/refunds
        const xenditSecret = xenditKey
        const authHeader = `Basic ${btoa(xenditSecret + ':')}`

        // 4a. Balance Check (Optional but recommended)
        try {
            const balanceRes = await fetch('https://api.xendit.co/balance', {
                headers: { 'Authorization': authHeader }
            })
            const balanceData = await balanceRes.json()
            const availableBalance = balanceData.balance; // Assuming PHP

            const refundAmount = amount || intent.total_amount;

            if (availableBalance < refundAmount) {
                return new Response(JSON.stringify({
                    error: `Insufficient Xendit Balance. Available: ${availableBalance}, Required: ${refundAmount}`,
                    code: 'INSUFFICIENT_BALANCE',
                    available_balance: availableBalance
                }), {
                    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
                    status: 402, // Payment Required
                })
            }
        } catch (e) {
            console.warn('Failed to check Xendit balance, proceeding anyway...', e)
        }

        // Idempotency key?
        const idempotencyKey = `refund-${intent_id}-${Date.now()}`

        // Validate and Key Metadata
        const validReasons = ["FRAUDULENT", "DUPLICATE", "REQUESTED_BY_CUSTOMER", "CANCELLATION", "OTHERS"];
        const xenditReason = validReasons.includes(reason.toUpperCase()) ? reason.toUpperCase() : "OTHERS";

        const refundPayload = {
            payment_request_id: xenditReference.startsWith('pr-') ? xenditReference : undefined,
            invoice_id: xenditReference.startsWith('inv-') ? xenditReference : undefined,
            payment_id: !xenditReference.startsWith('pr-') && !xenditReference.startsWith('inv-') ? xenditReference : undefined,
            amount: amount || intent.total_amount,
            reason: xenditReason,
            metadata: {
                intent_id: intent_id,
                user_id: user.id,
                custom_reason: reason, // Store original specific reason here
                intent_type: isExperience ? 'experience' : 'event'
            }
        }

        // Cleanup undefined keys
        // @ts-ignore
        Object.keys(refundPayload).forEach(key => refundPayload[key] === undefined && delete refundPayload[key])

        console.log('Sending Refund Request to Xendit:', refundPayload)

        const xenditResponse = await fetch('https://api.xendit.co/refunds', {
            method: 'POST',
            headers: {
                'Authorization': authHeader,
                'Content-Type': 'application/json',
                'Idempotency-Key': idempotencyKey
            },
            body: JSON.stringify(refundPayload)
        })

        const xenditData = await xenditResponse.json()

        if (!xenditResponse.ok) {
            console.error('Xendit Refund Error:', xenditData)
            return new Response(JSON.stringify({ error: xenditData.message || 'Failed to request refund from Xendit', details: xenditData }), {
                headers: { ...corsHeaders, 'Content-Type': 'application/json' },
                status: xenditResponse.status,
            })
        }

        // 5. Success - Update Refund Tracking
        try {
            const refundAmount = amount || intent.total_amount;
            if (isExperience) {
                await supabaseAdmin
                    .from('experience_purchase_intents')
                    .update({
                        refunded_amount: refundAmount,
                        refunded_at: new Date().toISOString()
                    })
                    .eq('id', intent_id)
            } else {
                await supabaseAdmin
                    .from('purchase_intents')
                    .update({
                        refunded_amount: refundAmount,
                        refunded_at: new Date().toISOString()
                    })
                    .eq('id', intent_id)
            }
            console.log(`Updated refund tracking for ${intent_id}: ${refundAmount}`)
        } catch (updateError) {
            console.error('Failed to update refund tracking:', updateError)
        }

        // 6. Send Email Notification
        const resendApiKey = resendKey
        if (resendApiKey) {
            try {
                // Determine recipient email
                let recipientEmail = intent.guest_email
                if (!recipientEmail && intent.user_id) {
                    const { data: userData } = await supabaseAdmin.auth.admin.getUserById(intent.user_id)
                    recipientEmail = userData.user?.email
                }

                if (recipientEmail) {
                    await fetch('https://api.resend.com/emails', {
                        method: 'POST',
                        headers: {
                            'Authorization': `Bearer ${resendApiKey}`,
                            'Content-Type': 'application/json'
                        },
                        body: JSON.stringify({
                            from: 'HangHut Refunds <support@hanghut.com>',
                            to: [recipientEmail],
                            subject: `Refund Initiated for ${eventOrExperienceTitle || 'Your Booking'} 💸`,
                            html: `
                              <div style="font-family: sans-serif; padding: 20px;">
                                <h2>Refund Initiated</h2>
                                <p>Hi there,</p>
                                <p>We've initiated a refund of <strong>PHP ${amount || intent.total_amount}</strong> for your order.</p>
                                <p>It may take 5-10 business days for the funds to appear in your account${intent.payment_method ? ` (${intent.payment_method.toUpperCase()})` : ''}, depending on your bank.</p>
                                <br>
                                <p>Reason: ${reason}</p>
                                <br>
                                <p>Thanks,<br>The HangHut Team</p>
                              </div>
                            `
                        })
                    })
                    console.log(`Refund email sent to ${recipientEmail}`)
                } else {
                    console.log('No recipient email found for refund notification')
                }
            } catch (emailError) {
                console.error('Failed to send refund email:', emailError)
                // Don't fail the request, just log it
            }
        }

        return new Response(JSON.stringify({ success: true, data: xenditData }), {
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
            status: 200,
        })

    } catch (error: any) {
        console.error('CRITICAL UNHANDLED ERROR:', error)

        let errorDetails = error.message;
        if (error.cause) errorDetails += ` (Cause: ${error.cause})`;
        if (error.stack) errorDetails += `\nStack: ${error.stack}`;

        return new Response(JSON.stringify({
            error: 'Internal Server Error',
            message: error.message,
            debug_details: errorDetails
        }), {
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
            status: 500,
        })
    }
})
