
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { PDFDocument, StandardFonts, rgb } from "https://esm.sh/pdf-lib@1.17.1"
import { encode as base64Encode } from "https://deno.land/std@0.168.0/encoding/base64.ts"

const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY")

const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

interface ExperienceEmailRequest {
    email: string
    name?: string
    experience_title: string
    experience_venue: string
    experience_date: string
    host_name: string
    quantity: number
    total_amount: number
    transaction_ref: string
    payment_method?: string
    intent_id: string
    cover_image_url?: string
}

function formatEventDate(isoDate: string): string {
    try {
        const d = new Date(isoDate)
        return d.toLocaleString('en-US', {
            weekday: 'long', year: 'numeric', month: 'long', day: 'numeric',
            hour: 'numeric', minute: '2-digit', hour12: true, timeZone: 'Asia/Manila'
        })
    } catch { return isoDate }
}

function formatShortDate(isoDate: string): string {
    try {
        const d = new Date(isoDate)
        return d.toLocaleString('en-US', {
            month: 'short', day: 'numeric', year: 'numeric', timeZone: 'Asia/Manila'
        })
    } catch { return isoDate }
}

function formatTime(isoDate: string): string {
    try {
        const d = new Date(isoDate)
        return d.toLocaleString('en-US', {
            hour: 'numeric', minute: '2-digit', hour12: true, timeZone: 'Asia/Manila'
        })
    } catch { return '' }
}

function formatCurrency(amount: number): string {
    return `₱${amount.toLocaleString('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`
}

// Generate Experience Pass PDF with QR Code
async function generatePassPdf(data: ExperienceEmailRequest): Promise<Uint8Array> {
    console.log('🎟️ Generating Experience Pass PDF...')
    const pdfDoc = await PDFDocument.create()
    const font = await pdfDoc.embedFont(StandardFonts.Helvetica)
    const boldFont = await pdfDoc.embedFont(StandardFonts.HelveticaBold)
    const formattedDate = formatEventDate(data.experience_date)

    let coverImage = null
    if (data.cover_image_url) {
        try {
            const imgRes = await fetch(data.cover_image_url)
            const imgBuffer = await imgRes.arrayBuffer()
            try { coverImage = await pdfDoc.embedJpg(imgBuffer) }
            catch { coverImage = await pdfDoc.embedPng(imgBuffer) }
        } catch (e) { console.error('Cover image load failed', e) }
    }

    const page = pdfDoc.addPage([400, 800])
    const { width, height } = page.getSize()

    // Header
    if (coverImage) {
        page.drawImage(coverImage, { x: 0, y: height - 250, width, height: 250 })
        page.drawRectangle({ x: 0, y: height - 250, width, height: 250, color: rgb(0, 0, 0), opacity: 0.35 })
    } else {
        page.drawRectangle({ x: 0, y: height - 200, width, height: 200, color: rgb(0.08, 0.35, 0.15) })
    }

    let titleFontSize = 24
    if (data.experience_title.length > 20) titleFontSize = 18
    page.drawText(data.experience_title.toUpperCase(), { x: 30, y: height - 60, size: titleFontSize, font: boldFont, color: rgb(1, 1, 1), maxWidth: 340 })
    page.drawText('EXPERIENCE PASS', { x: 30, y: height - 100, size: 10, font, color: rgb(0.85, 0.85, 0.85) })

    // Body
    let currentY = height - 280
    const labelColor = rgb(0.5, 0.5, 0.5)
    const textColor = rgb(0.1, 0.1, 0.1)

    page.drawText('DATE & TIME', { x: 30, y: currentY, size: 9, font: boldFont, color: labelColor })
    page.drawText(formattedDate, { x: 30, y: currentY - 15, size: 13, font, color: textColor, maxWidth: 340 })
    currentY -= 50

    page.drawText('LOCATION', { x: 30, y: currentY, size: 9, font: boldFont, color: labelColor })
    page.drawText(data.experience_venue, { x: 30, y: currentY - 15, size: 13, font, color: textColor, maxWidth: 340 })
    currentY -= 50

    page.drawText('HOST', { x: 30, y: currentY, size: 9, font: boldFont, color: labelColor })
    page.drawText(data.host_name, { x: 30, y: currentY - 15, size: 13, font, color: textColor })
    currentY -= 50

    page.drawText('GUEST', { x: 30, y: currentY, size: 9, font: boldFont, color: labelColor })
    page.drawText((data.name || data.email).toUpperCase(), { x: 30, y: currentY - 15, size: 13, font: boldFont, color: textColor })
    currentY -= 40

    if (data.quantity > 1) {
        page.drawText(`× ${data.quantity} guests`, { x: 30, y: currentY, size: 12, font, color: labelColor })
        currentY -= 30
    }

    // QR Section
    const boxY = 150
    const boxSize = 250
    const boxX = (width - boxSize) / 2

    for (let i = 0; i < width; i += 15) {
        page.drawLine({ start: { x: i, y: boxY + boxSize + 40 }, end: { x: i + 8, y: boxY + boxSize + 40 }, thickness: 1, color: rgb(0.8, 0.8, 0.8) })
    }

    const scanText = 'Show this QR code to the host for check-in'
    const scanTextWidth = font.widthOfTextAtSize(scanText, 10)
    page.drawText(scanText, { x: (width - scanTextWidth) / 2, y: boxY + boxSize + 20, size: 10, font, color: labelColor })

    try {
        const qrUrl = `https://api.qrserver.com/v1/create-qr-code/?size=500x500&format=png&data=${encodeURIComponent(data.intent_id)}`
        const qrRes = await fetch(qrUrl)
        if (!qrRes.ok) throw new Error(`QR API returned ${qrRes.status}`)
        const qrBuffer = await qrRes.arrayBuffer()
        const qrImage = await pdfDoc.embedPng(qrBuffer)
        page.drawImage(qrImage, { x: boxX, y: boxY, width: boxSize, height: boxSize })
    } catch (e) {
        console.error('[QR] Error:', e)
        page.drawText('QR Load Error', { x: 150, y: boxY + 100, size: 12, font: boldFont, color: rgb(1, 0, 0) })
    }

    const refText = `Ref: ${data.transaction_ref.substring(0, 8)}`
    const refWidth = font.widthOfTextAtSize(refText, 12)
    page.drawText(refText, { x: (width - refWidth) / 2, y: boxY - 25, size: 12, font, color: rgb(0.4, 0.4, 0.4) })

    return await pdfDoc.save()
}

serve(async (req) => {
    if (req.method === 'OPTIONS') {
        return new Response('ok', { headers: corsHeaders })
    }

    try {
        console.log('📩 Processing experience confirmation email...')
        const data: ExperienceEmailRequest = await req.json()
        console.log(`   Target: ${data.email}, Experience: ${data.experience_title}`)

        // 1. Generate Pass PDF
        let passBase64 = ''
        try {
            const passPdfBytes = await generatePassPdf(data)
            passBase64 = base64Encode(passPdfBytes)
            console.log('📄 Experience Pass PDF generated')
        } catch (pdfError: unknown) {
            const msg = pdfError instanceof Error ? pdfError.message : 'Unknown error'
            console.error('💥 PDF Error:', msg)
            return new Response(JSON.stringify({ error: `PDF Generation Failed: ${msg}` }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 500 })
        }

        // 2. Format
        const formattedAmount = formatCurrency(Number(data.total_amount))
        const formattedDate = formatShortDate(data.experience_date)
        const formattedTime = formatTime(data.experience_date)
        const fullDate = formatEventDate(data.experience_date)
        const guestName = data.name || 'Guest'
        const firstName = guestName.split(' ')[0]

        // 3. Premium HTML Email — Clean white design
        const html = `
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Booking Confirmed</title>
</head>
<body style="margin: 0; padding: 0; background-color: #f4f4f5; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif;">
    <div style="max-width: 560px; margin: 0 auto; padding: 20px 16px;">

        <!-- Logo Header -->
        <div style="text-align: center; padding: 24px 0 16px;">
            <span style="font-size: 24px; font-weight: 800; color: #18181b; letter-spacing: -1px;">Hang<span style="color: #4f46e5;">Hut</span></span>
        </div>

        <!-- Main Card -->
        <div style="background: #ffffff; border-radius: 20px; overflow: hidden; box-shadow: 0 1px 3px rgba(0,0,0,0.06), 0 4px 16px rgba(0,0,0,0.04);">

            <!-- Hero Banner -->
            ${data.cover_image_url
                ? `<div style="position: relative;">
                     <img src="${data.cover_image_url}" alt="${data.experience_title}" style="width: 100%; height: 200px; object-fit: cover; display: block;" />
                     <div style="position: absolute; bottom: 0; left: 0; right: 0; height: 80px; background: linear-gradient(to top, rgba(0,0,0,0.5), transparent);"></div>
                     <div style="position: absolute; bottom: 16px; left: 20px;">
                       <span style="background: #22c55e; color: #fff; padding: 5px 14px; border-radius: 20px; font-size: 11px; font-weight: 700; letter-spacing: 0.5px; text-transform: uppercase;">✓ Booking Confirmed</span>
                     </div>
                   </div>`
                : `<div style="background: linear-gradient(135deg, #4f46e5 0%, #7c3aed 50%, #a855f7 100%); height: 140px; display: flex; align-items: center; justify-content: center; text-align: center; padding: 20px;">
                     <div>
                       <div style="font-size: 32px; margin-bottom: 8px;">🎉</div>
                       <span style="background: rgba(255,255,255,0.25); color: #fff; padding: 5px 14px; border-radius: 20px; font-size: 11px; font-weight: 700; letter-spacing: 0.5px; text-transform: uppercase;">✓ Booking Confirmed</span>
                     </div>
                   </div>`
            }

            <!-- Content -->
            <div style="padding: 28px 24px 8px;">

                <!-- Greeting -->
                <p style="color: #71717a; font-size: 14px; margin: 0 0 4px;">Hey ${firstName} 👋</p>
                <h1 style="color: #18181b; font-size: 22px; font-weight: 800; margin: 0 0 4px; letter-spacing: -0.3px; line-height: 1.3;">${data.experience_title}</h1>
                <p style="color: #a1a1aa; font-size: 13px; margin: 0 0 24px;">You're all set — see you there!</p>

                <!-- Details Card -->
                <div style="background: #fafafa; border-radius: 14px; border: 1px solid #f0f0f0; overflow: hidden;">

                    <!-- Date & Time -->
                    <div style="padding: 16px 20px; border-bottom: 1px solid #f0f0f0;">
                        <table width="100%" cellpadding="0" cellspacing="0" border="0">
                            <tr>
                                <td width="36" valign="top">
                                    <div style="width: 36px; height: 36px; background: #eef2ff; border-radius: 10px; text-align: center; line-height: 36px; font-size: 16px;">📅</div>
                                </td>
                                <td style="padding-left: 14px;" valign="top">
                                    <p style="margin: 0; color: #a1a1aa; font-size: 11px; text-transform: uppercase; letter-spacing: 0.8px; font-weight: 600;">When</p>
                                    <p style="margin: 2px 0 0; color: #18181b; font-size: 14px; font-weight: 600;">${formattedDate} · ${formattedTime}</p>
                                </td>
                            </tr>
                        </table>
                    </div>

                    <!-- Venue -->
                    <div style="padding: 16px 20px; border-bottom: 1px solid #f0f0f0;">
                        <table width="100%" cellpadding="0" cellspacing="0" border="0">
                            <tr>
                                <td width="36" valign="top">
                                    <div style="width: 36px; height: 36px; background: #fef2f2; border-radius: 10px; text-align: center; line-height: 36px; font-size: 16px;">📍</div>
                                </td>
                                <td style="padding-left: 14px;" valign="top">
                                    <p style="margin: 0; color: #a1a1aa; font-size: 11px; text-transform: uppercase; letter-spacing: 0.8px; font-weight: 600;">Where</p>
                                    <p style="margin: 2px 0 0; color: #18181b; font-size: 14px; font-weight: 600;">${data.experience_venue}</p>
                                </td>
                            </tr>
                        </table>
                    </div>

                    <!-- Host -->
                    <div style="padding: 16px 20px; border-bottom: 1px solid #f0f0f0;">
                        <table width="100%" cellpadding="0" cellspacing="0" border="0">
                            <tr>
                                <td width="36" valign="top">
                                    <div style="width: 36px; height: 36px; background: #f5f3ff; border-radius: 10px; text-align: center; line-height: 36px; font-size: 16px;">👤</div>
                                </td>
                                <td style="padding-left: 14px;" valign="top">
                                    <p style="margin: 0; color: #a1a1aa; font-size: 11px; text-transform: uppercase; letter-spacing: 0.8px; font-weight: 600;">Your Host</p>
                                    <p style="margin: 2px 0 0; color: #18181b; font-size: 14px; font-weight: 600;">${data.host_name}</p>
                                </td>
                            </tr>
                        </table>
                    </div>

                    <!-- Guests -->
                    <div style="padding: 16px 20px;">
                        <table width="100%" cellpadding="0" cellspacing="0" border="0">
                            <tr>
                                <td width="36" valign="top">
                                    <div style="width: 36px; height: 36px; background: #fefce8; border-radius: 10px; text-align: center; line-height: 36px; font-size: 16px;">🎫</div>
                                </td>
                                <td style="padding-left: 14px;" valign="top">
                                    <p style="margin: 0; color: #a1a1aa; font-size: 11px; text-transform: uppercase; letter-spacing: 0.8px; font-weight: 600;">Guests</p>
                                    <p style="margin: 2px 0 0; color: #18181b; font-size: 14px; font-weight: 600;">${data.quantity} guest${data.quantity > 1 ? 's' : ''} · ${guestName}</p>
                                </td>
                            </tr>
                        </table>
                    </div>
                </div>

                <!-- Payment Summary -->
                <div style="margin-top: 16px; background: #18181b; border-radius: 14px; padding: 20px 22px;">
                    <table width="100%" cellpadding="0" cellspacing="0" border="0">
                        <tr>
                            <td>
                                <p style="margin: 0; color: #a1a1aa; font-size: 11px; text-transform: uppercase; letter-spacing: 0.8px; font-weight: 600;">Total Paid</p>
                                <p style="margin: 4px 0 0; color: #ffffff; font-size: 26px; font-weight: 800; letter-spacing: -0.5px;">${formattedAmount}</p>
                                ${data.payment_method ? `<p style="margin: 4px 0 0; color: #71717a; font-size: 12px;">via ${data.payment_method}</p>` : ''}
                            </td>
                            <td style="text-align: right; vertical-align: middle;">
                                <span style="background: #22c55e; color: #fff; padding: 8px 18px; border-radius: 10px; font-size: 13px; font-weight: 700; display: inline-block;">✓ Paid</span>
                            </td>
                        </tr>
                    </table>
                </div>

                <!-- QR Pass Notice -->
                <div style="text-align: center; margin-top: 28px; padding-bottom: 20px;">
                    <div style="display: inline-block; text-align: center;">
                        <div style="width: 48px; height: 48px; background: #eef2ff; border-radius: 14px; margin: 0 auto 12px; text-align: center; line-height: 48px; font-size: 22px;">📎</div>
                        <p style="margin: 0; color: #18181b; font-size: 14px; font-weight: 700;">Experience Pass Attached</p>
                        <p style="margin: 4px 0 0; color: #a1a1aa; font-size: 12px; line-height: 1.5;">Open the PDF attachment and show<br>the QR code to the host for check-in</p>
                    </div>
                </div>

            </div>
        </div>

        <!-- Footer -->
        <div style="text-align: center; padding: 24px 0;">
            <p style="color: #a1a1aa; font-size: 11px; margin: 0;">Ref: ${data.transaction_ref}</p>
            <p style="color: #d4d4d8; font-size: 11px; margin: 8px 0 0;">© ${new Date().getFullYear()} HangHut · All rights reserved</p>
        </div>

    </div>
</body>
</html>
        `

        // 4. Send Email via Resend
        console.log('🚀 Sending via Resend API...')
        if (!RESEND_API_KEY) throw new Error("Missing RESEND_API_KEY")

        const maxRetries = 3
        let attempt = 0
        let sendSuccess = false
        let responseData: Record<string, unknown> | null = null
        let finalStatus = 500

        while (attempt < maxRetries && !sendSuccess) {
            attempt++
            try {
                const resendRes = await fetch('https://api.resend.com/emails', {
                    method: 'POST',
                    headers: {
                        'Authorization': `Bearer ${RESEND_API_KEY}`,
                        'Content-Type': 'application/json'
                    },
                    body: JSON.stringify({
                        from: 'HangHut Experiences <experiences@hanghut.com>',
                        to: [data.email],
                        subject: `You're in! ${data.experience_title} 🎉`,
                        html: html,
                        attachments: [{ filename: 'ExperiencePass.pdf', content: passBase64 }]
                    })
                })

                responseData = await resendRes.json()
                finalStatus = resendRes.status

                if (resendRes.ok) {
                    sendSuccess = true
                } else if (resendRes.status === 429) {
                    console.warn(`⚠️ Rate limit attempt ${attempt}. Waiting...`)
                    await new Promise(resolve => setTimeout(resolve, Math.pow(2, attempt) * 1000))
                } else {
                    throw new Error(String(responseData?.message || JSON.stringify(responseData)))
                }
            } catch (e: unknown) {
                const msg = e instanceof Error ? e.message : 'Unknown error'
                console.error(`❌ Attempt ${attempt} failed:`, msg)
                if (attempt >= maxRetries || finalStatus !== 429) {
                    if (!responseData) responseData = { error: msg }
                    break
                }
            }
        }

        if (!sendSuccess) {
            console.error('❌ Resend failed after retries:', responseData)
            return new Response(JSON.stringify({ error: responseData }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: finalStatus })
        }

        console.log('✅ Experience confirmation email sent:', responseData)
        return new Response(JSON.stringify(responseData), { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 200 })

    } catch (error: unknown) {
        const msg = error instanceof Error ? error.message : 'Unknown error'
        console.error('❌ Global Error:', msg)
        return new Response(JSON.stringify({ error: msg }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 500 })
    }
})
