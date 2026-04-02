import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

/**
 * submit-xendit-kyc
 * 
 * Submits KYC (Know Your Customer) documents to Xendit for a partner's sub-account.
 * This enables GCash, credit card, and other payment channels that require verification.
 * 
 * Flow:
 *   1. Read partner data from DB (business info + document URLs)
 *   2. Download each document from Supabase Storage
 *   3. Upload each document to Xendit File API → get file_id
 *   4. Create Account Holder via Xendit API with all details + file_ids
 *   5. Link Account Holder to the sub-account via Update Account API
 *   6. Update partners.kyc_status to 'submitted'
 */

// Map our business_type values to Xendit's accepted entity types
const BUSINESS_TYPE_MAP: Record<string, string> = {
    'sole_proprietorship': 'SOLE_PROPRIETOR',
    'sole_prop': 'SOLE_PROPRIETOR',
    'corporation': 'CORPORATION',
    'partnership': 'PARTNERSHIP',
    'cooperative': 'COOPERATIVE',
    'ngo': 'NGO',
    'government': 'GOVERNMENT',
}

// Map our business_type to the required KYC document types for PH
const KYC_DOC_REQUIREMENTS: Record<string, { field: string; type: string }[]> = {
    'SOLE_PROPRIETOR': [
        { field: 'business_document_url', type: 'DTI_CERTIFICATE_REGISTRATION_DOCUMENT' },
        { field: 'id_document_url', type: 'GOVERNMENT_ID_DOCUMENT' },
        { field: 'bir_2303_url', type: 'BIR_2303_DOCUMENT' },
    ],
    'CORPORATION': [
        { field: 'business_document_url', type: 'SEC_CERTIFICATE_REGISTRATION_DOCUMENT' },
        { field: 'id_document_url', type: 'GOVERNMENT_ID_DOCUMENT' },
        { field: 'bir_2303_url', type: 'BIR_2303_DOCUMENT' },
        { field: 'articles_of_incorporation_url', type: 'ARTICLES_OF_INCORPORATION_DOCUMENT' },
        { field: 'secretary_certificate_url', type: 'SECRETARY_CERTIFICATE_DOCUMENT' },
        { field: 'latest_gis_url', type: 'GENERAL_INFORMATION_SHEET_DOCUMENT' },
    ],
    'PARTNERSHIP': [
        { field: 'business_document_url', type: 'SEC_CERTIFICATE_REGISTRATION_DOCUMENT' },
        { field: 'id_document_url', type: 'GOVERNMENT_ID_DOCUMENT' },
        { field: 'bir_2303_url', type: 'BIR_2303_DOCUMENT' },
        { field: 'articles_of_incorporation_url', type: 'ARTICLES_OF_INCORPORATION_DOCUMENT' },
        { field: 'secretary_certificate_url', type: 'SECRETARY_CERTIFICATE_DOCUMENT' },
        { field: 'latest_gis_url', type: 'GENERAL_INFORMATION_SHEET_DOCUMENT' },
    ],
}

// Map our sex field to Xendit's gender values
const GENDER_MAP: Record<string, string> = {
    'male': 'MALE',
    'm': 'MALE',
    'female': 'FEMALE',
    'f': 'FEMALE',
    'other': 'OTHER',
}

serve(async (req: Request) => {
    if (req.method === 'OPTIONS') {
        return new Response('ok', { headers: corsHeaders })
    }

    try {
        const sbUrl = Deno.env.get('SUPABASE_URL') ?? ''
        const sbAnonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? ''
        const sbServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
        const xenditKey = Deno.env.get('XENDIT_SECRET_KEY')

        if (!xenditKey) throw new Error('Missing XENDIT_SECRET_KEY')

        const supabaseClient = createClient(sbUrl, sbAnonKey, {
            global: { headers: { Authorization: req.headers.get('Authorization')! } },
        })
        const supabaseAdmin = createClient(sbUrl, sbServiceKey)

        // Auth check
        const { data: { user } } = await supabaseClient.auth.getUser()
        if (!user) {
            return new Response(JSON.stringify({ error: 'Unauthorized' }), {
                headers: { ...corsHeaders, 'Content-Type': 'application/json' },
                status: 401,
            })
        }

        const { partner_id } = await req.json()
        if (!partner_id) {
            return new Response(JSON.stringify({ error: 'Missing partner_id' }), {
                headers: { ...corsHeaders, 'Content-Type': 'application/json' },
                status: 400,
            })
        }

        // 1. Fetch partner data
        const { data: partner, error: partnerError } = await supabaseAdmin
            .from('partners')
            .select('*')
            .eq('id', partner_id)
            .single()

        if (partnerError || !partner) {
            return new Response(JSON.stringify({ error: 'Partner not found' }), {
                headers: { ...corsHeaders, 'Content-Type': 'application/json' },
                status: 404,
            })
        }

        // Authorization: admin or partner owner
        //    Check JWT metadata first, then fall back to DB lookup (web admin panel uses authenticated JWT)
        let isAdmin = user.app_metadata?.role === 'admin' ||
                        user.app_metadata?.role === 'service_role' ||
                        user.user_metadata?.is_admin === true

        if (!isAdmin) {
            const { data: dbUser } = await supabaseAdmin
                .from('users')
                .select('is_admin')
                .eq('id', user.id)
                .single()
            if (dbUser?.is_admin === true) isAdmin = true
        }

        const isOwner = partner.user_id === user.id

        if (!isAdmin && !isOwner) {
            return new Response(JSON.stringify({ error: 'Unauthorized' }), {
                headers: { ...corsHeaders, 'Content-Type': 'application/json' },
                status: 403,
            })
        }

        // 2. Validate prerequisites
        if (!partner.xendit_account_id) {
            return new Response(JSON.stringify({
                error: 'Partner does not have a Xendit sub-account. Create one first via create-xendit-subaccount.',
                code: 'NO_SUBACCOUNT',
            }), {
                headers: { ...corsHeaders, 'Content-Type': 'application/json' },
                status: 400,
            })
        }

        if (partner.kyc_status === 'submitted' || partner.kyc_status === 'verified') {
            return new Response(JSON.stringify({
                success: true,
                message: `KYC already ${partner.kyc_status}`,
                kyc_status: partner.kyc_status,
                already_submitted: true,
            }), {
                headers: { ...corsHeaders, 'Content-Type': 'application/json' },
                status: 200,
            })
        }

        const xenditType = BUSINESS_TYPE_MAP[partner.business_type?.toLowerCase()] || 'SOLE_PROPRIETOR'
        const requiredDocs = KYC_DOC_REQUIREMENTS[xenditType] || KYC_DOC_REQUIREMENTS['SOLE_PROPRIETOR']

        // Check required docs — corporate docs are optional (only if available)
        const coreDocs = requiredDocs.filter(d => 
            !['articles_of_incorporation_url', 'secretary_certificate_url', 'latest_gis_url'].includes(d.field)
        )
        const missingDocs: string[] = []
        for (const doc of coreDocs) {
            if (!partner[doc.field]) {
                missingDocs.push(doc.field)
            }
        }

        if (missingDocs.length > 0) {
            return new Response(JSON.stringify({
                error: 'Missing required KYC documents',
                missing_fields: missingDocs,
                code: 'MISSING_DOCUMENTS',
            }), {
                headers: { ...corsHeaders, 'Content-Type': 'application/json' },
                status: 400,
            })
        }

        // Filter to only docs that actually have URLs (skip optional ones without URLs)
        const docsToUpload = requiredDocs.filter(doc => !!partner[doc.field])

        const authHeader = `Basic ${btoa(xenditKey + ':')}`

        // 3. Upload each document to Xendit and collect file_ids
        console.log(`📄 Uploading KYC documents for partner ${partner_id}...`)

        const kycDocuments: { type: string; country: string; file_id: string }[] = []

        for (const doc of docsToUpload) {
            const docUrl = partner[doc.field] as string
            console.log(`  📎 Uploading ${doc.type} from: ${docUrl}`)

            // Download file from Supabase Storage URL
            const fileResponse = await fetch(docUrl)
            if (!fileResponse.ok) throw new Error(`Failed to download ${doc.field} from storage: ${fileResponse.status}`)

            const fileBlob = await fileResponse.blob()

            // Determine filename and extension
            const urlPath = new URL(docUrl).pathname
            const filename = urlPath.split('/').pop() || `${doc.type}.pdf`

            // Upload to Xendit File API
            const formData = new FormData()
            formData.append('purpose', 'KYC_DOCUMENT')
            formData.append('file', fileBlob, filename)

            const uploadResponse = await fetch('https://api.xendit.co/files', {
                method: 'POST',
                headers: {
                    'Authorization': authHeader,
                },
                body: formData,
            })

            if (!uploadResponse.ok) {
                const uploadError = await uploadResponse.text()
                console.error(`❌ Failed to upload ${doc.type}:`, uploadError)
                throw new Error(`Failed to upload ${doc.type} to Xendit: ${uploadError}`)
            }

            const uploadResult = await uploadResponse.json()
            console.log(`  ✅ Uploaded ${doc.type}: file_id=${uploadResult.id}`)

            kycDocuments.push({
                type: doc.type,
                country: 'PH',
                file_id: uploadResult.id,
            })
        }

        // 4. Create Account Holder
        console.log(`🏢 Creating Account Holder for partner ${partner_id}...`)

        // Parse representative name
        const repName = partner.representative_name || partner.business_name || 'Partner'
        const nameParts = repName.trim().split(' ')
        const givenNames = nameParts[0] || 'Partner'
        const surname = nameParts.length > 1 ? nameParts.slice(1).join(' ') : '-'

        const accountHolderPayload: Record<string, unknown> = {
            business_detail: {
                type: xenditType,
                legal_name: partner.business_name,
                trading_name: partner.business_name,
                description: partner.description || `HangHut partner: ${partner.business_name}`,
                industry_category: 'ENTERTAINMENT_AND_RECREATION',
                country_of_operation: 'PH',
            },
            individual_details: [
                {
                    given_names: givenNames,
                    surname: surname,
                    phone_number: partner.phone_number || partner.contact_number || undefined,
                    email: partner.work_email || undefined,
                    nationality: partner.nationality || 'PH',
                    place_of_birth: partner.place_of_birth || undefined,
                    date_of_birth: partner.date_of_birth || undefined,
                    gender: partner.sex ? (GENDER_MAP[partner.sex.toLowerCase()] || undefined) : undefined,
                    type: 'PIC',
                    role: 'owner',
                },
            ],
            address: (partner.street_line1 || partner.city) ? {
                street_line1: partner.street_line1 || undefined,
                street_line2: partner.street_line2 || undefined,
                city: partner.city || undefined,
                province_state: partner.province_state || undefined,
                postal_code: partner.postal_code || undefined,
                country: 'PH',
            } : undefined,
            kyc_documents: kycDocuments,
            phone_number: partner.phone_number || partner.contact_number || undefined,
            email: partner.work_email || undefined,
        }

        // Add TIN if available
        if (partner.tax_id) {
            (accountHolderPayload.individual_details as any[])[0].tax_identification_number = partner.tax_id
        }

        const holderResponse = await fetch('https://api.xendit.co/account_holders', {
            method: 'POST',
            headers: {
                'Authorization': authHeader,
                'Content-Type': 'application/json',
            },
            body: JSON.stringify(accountHolderPayload),
        })

        const holderData = await holderResponse.json()

        if (!holderResponse.ok) {
            console.error('❌ Create Account Holder failed:', holderData)
            return new Response(JSON.stringify({
                error: 'Failed to create Xendit Account Holder',
                details: holderData,
                code: 'XENDIT_KYC_ERROR',
            }), {
                headers: { ...corsHeaders, 'Content-Type': 'application/json' },
                status: holderResponse.status,
            })
        }

        console.log(`✅ Account Holder created: ${holderData.id}`)

        // 5. Link Account Holder to the sub-account via Update Account API
        console.log(`🔗 Linking Account Holder ${holderData.id} to sub-account ${partner.xendit_account_id}...`)

        const linkResponse = await fetch(`https://api.xendit.co/v2/accounts/${partner.xendit_account_id}`, {
            method: 'PATCH',
            headers: {
                'Authorization': authHeader,
                'Content-Type': 'application/json',
            },
            body: JSON.stringify({
                account_holder_id: holderData.id,
            }),
        })

        const linkData = await linkResponse.json()

        if (!linkResponse.ok) {
            console.error('❌ Link Account Holder failed:', linkData)
            // Still consider partial success — Account Holder was created
            return new Response(JSON.stringify({
                error: 'Account Holder created but failed to link to sub-account',
                account_holder_id: holderData.id,
                details: linkData,
                code: 'LINK_FAILED',
            }), {
                headers: { ...corsHeaders, 'Content-Type': 'application/json' },
                status: linkResponse.status,
            })
        }

        console.log(`✅ Account Holder linked to sub-account`)

        // 6. Update partner KYC status
        const { error: updateError } = await supabaseAdmin
            .from('partners')
            .update({
                kyc_status: 'submitted',
                xendit_account_holder_id: holderData.id,
            })
            .eq('id', partner_id)

        if (updateError) {
            console.error('⚠️ KYC submitted but failed to update DB status:', updateError)
        }

        return new Response(JSON.stringify({
            success: true,
            kyc_status: holderData.kyc?.status || 'NOT_VERIFIED',
            account_holder_id: holderData.id,
            message: 'KYC documents submitted to Xendit. Verification typically takes 1-3 business days.',
        }), {
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
            status: 200,
        })

    } catch (error: any) {
        console.error('CRITICAL ERROR:', error)
        return new Response(JSON.stringify({
            error: 'Internal Server Error',
            message: error.message,
        }), {
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
            status: 500,
        })
    }
})
