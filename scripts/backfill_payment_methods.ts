
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

// Configuration
const SUPABASE_URL = Deno.env.get('SUPABASE_URL') || '';
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || '';
const XENDIT_SECRET_KEY = Deno.env.get('XENDIT_SECRET_KEY') || '';

if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY || !XENDIT_SECRET_KEY) {
    console.error('❌ Missing environment variables. usage: SUPABASE_URL=... deno run ...');
    Deno.exit(1);
}

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

async function backfillPaymentMethods() {
    console.log('🚀 Starting Payment Method Backfill...');

    // 1. Fetch intents that need backfilling
    const { data: intents, error } = await supabase
        .from('purchase_intents')
        .select('id, xendit_invoice_id, xendit_external_id, status, payment_method')
        .eq('status', 'completed')
        .or('payment_method.is.null,payment_method.eq.unknown,payment_method.eq.multiple');

    if (error) {
        console.error('❌ Error fetching intents:', error);
        return;
    }

    console.log(`Found ${intents.length} intents to process.`);

    let updatedCount = 0;
    let errorCount = 0;

    for (const intent of intents) {
        if (!intent.xendit_invoice_id) {
            console.log(`⚠️ Intent ${intent.id} has no xendit_invoice_id. Skipping.`);
            continue;
        }

        try {
            // 2. Fetch Session/Invoice from Xendit
            // Try Session API first (v2)
            let paymentMethod = null;

            console.log(`Processing ${intent.id} (Xendit ID: ${intent.xendit_invoice_id})...`);

            const headers = new Headers();
            headers.set('Authorization', `Basic ${btoa(XENDIT_SECRET_KEY + ':')}`);

            // Fetch Session
            const sessionRes = await fetch(`https://api.xendit.co/sessions/${intent.xendit_invoice_id}`, { headers });

            if (sessionRes.ok) {
                const session = await sessionRes.json();
                if (session.payment_method) {
                    const pm = session.payment_method;
                    if (typeof pm === 'object') {
                        paymentMethod =
                            pm.ewallet?.channel_code ||
                            pm.retail_outlet?.channel_code ||
                            pm.qr_code?.channel_code ||
                            pm.direct_debit?.channel_code ||
                            pm.card?.channel_code ||
                            pm.virtual_account?.channel_code ||
                            pm.type;
                    }
                }
            } else {
                // Try Invoice API (Legacy)
                const invoiceRes = await fetch(`https://api.xendit.co/v2/invoices/${intent.xendit_invoice_id}`, { headers });
                if (invoiceRes.ok) {
                    const invoice = await invoiceRes.json();
                    paymentMethod = invoice.payment_channel || invoice.payment_method;
                }
            }

            if (paymentMethod) {
                paymentMethod = String(paymentMethod).toUpperCase();

                // 3. Update Supabase
                const { error: updateError } = await supabase
                    .from('purchase_intents')
                    .update({ payment_method: paymentMethod })
                    .eq('id', intent.id);

                if (updateError) {
                    console.error(`❌ Failed to update DB for ${intent.id}:`, updateError);
                    errorCount++;
                } else {
                    console.log(`✅ Updated ${intent.id}: ${paymentMethod}`);
                    updatedCount++;
                }
            } else {
                console.log(`⚠️ Could not determine payment method for ${intent.id}`);
                errorCount++;
            }

        } catch (e) {
            console.error(`❌ Unexpected error for ${intent.id}:`, e);
            errorCount++;
        }

        // Rate limit logging
        await new Promise(r => setTimeout(r, 200)); // 5 req/sec safety
    }

    console.log(`\n🎉 Backfill Complete! Updated: ${updatedCount}, Errors: ${errorCount}`);
}

backfillPaymentMethods();
