
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

        // 3. Premium HTML Email
        const html = `
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Booking Confirmed</title>
</head>
<body style="margin: 0; padding: 0; background-color: #0f0f0f; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif;">
    <div style="max-width: 600px; margin: 0 auto; background-color: #0f0f0f;">
        
        <!-- Hero Section -->
        <div style="position: relative; text-align: center;">
            ${data.cover_image_url
                ? `<div style="background-image: url('${data.cover_image_url}'); background-size: cover; background-position: center; height: 280px; border-radius: 0 0 24px 24px;">
                     <div style="background: linear-gradient(to top, #0f0f0f 0%, rgba(15,15,15,0.6) 50%, rgba(15,15,15,0.2) 100%); height: 280px; border-radius: 0 0 24px 24px; display: flex; align-items: flex-end; justify-content: center; padding-bottom: 30px;">
                       <div>
                         <div style="background: #22c55e; color: #fff; display: inline-block; padding: 6px 16px; border-radius: 20px; font-size: 12px; font-weight: 700; letter-spacing: 1px; text-transform: uppercase;">✓ Confirmed</div>
                       </div>
                     </div>
                   </div>`
                : `<div style="background: linear-gradient(135deg, #166534 0%, #15803d 50%, #22c55e 100%); height: 200px; border-radius: 0 0 24px 24px; display: flex; align-items: center; justify-content: center;">
                     <div style="text-align: center;">
                       <div style="background: rgba(255,255,255,0.2); color: #fff; display: inline-block; padding: 6px 16px; border-radius: 20px; font-size: 12px; font-weight: 700; letter-spacing: 1px; text-transform: uppercase;">✓ Confirmed</div>
                     </div>
                   </div>`
            }
        </div>

        <!-- Content -->
        <div style="padding: 30px 24px;">
            
            <!-- Greeting -->
            <p style="color: #a1a1aa; font-size: 15px; margin: 0 0 4px;">Hey ${firstName},</p>
            <h1 style="color: #ffffff; font-size: 26px; font-weight: 800; margin: 0 0 6px; letter-spacing: -0.5px; line-height: 1.2;">${data.experience_title}</h1>
            <p style="color: #71717a; font-size: 14px; margin: 0 0 28px;">You're all set. See you there! 🎉</p>

            <!-- Details Card -->
            <div style="background: #1a1a1a; border-radius: 16px; padding: 24px; border: 1px solid #2a2a2a;">
                
                <!-- Date & Time Row -->
                <div style="display: flex; margin-bottom: 20px;">
                    <div style="background: #22c55e; width: 44px; height: 44px; border-radius: 12px; text-align: center; line-height: 44px; font-size: 18px; flex-shrink: 0;">📅</div>
                    <div style="margin-left: 14px;">
                        <p style="margin: 0; color: #71717a; font-size: 11px; text-transform: uppercase; letter-spacing: 1px; font-weight: 600;">When</p>
                        <p style="margin: 3px 0 0; color: #ffffff; font-size: 15px; font-weight: 600;">${formattedDate}</p>
                        <p style="margin: 2px 0 0; color: #a1a1aa; font-size: 13px;">${formattedTime}</p>
                    </div>
                </div>

                <!-- Divider -->
                <div style="border-top: 1px solid #2a2a2a; margin: 0 -24px; padding: 0;"></div>

                <!-- Venue Row -->
                <div style="display: flex; margin-top: 20px; margin-bottom: 20px;">
                    <div style="background: #3b82f6; width: 44px; height: 44px; border-radius: 12px; text-align: center; line-height: 44px; font-size: 18px; flex-shrink: 0;">📍</div>
                    <div style="margin-left: 14px;">
                        <p style="margin: 0; color: #71717a; font-size: 11px; text-transform: uppercase; letter-spacing: 1px; font-weight: 600;">Where</p>
                        <p style="margin: 3px 0 0; color: #ffffff; font-size: 15px; font-weight: 600;">${data.experience_venue}</p>
                    </div>
                </div>

                <!-- Divider -->
                <div style="border-top: 1px solid #2a2a2a; margin: 0 -24px; padding: 0;"></div>

                <!-- Host Row -->
                <div style="display: flex; margin-top: 20px; margin-bottom: 20px;">
                    <div style="background: #a855f7; width: 44px; height: 44px; border-radius: 12px; text-align: center; line-height: 44px; font-size: 18px; flex-shrink: 0;">👤</div>
                    <div style="margin-left: 14px;">
                        <p style="margin: 0; color: #71717a; font-size: 11px; text-transform: uppercase; letter-spacing: 1px; font-weight: 600;">Your Host</p>
                        <p style="margin: 3px 0 0; color: #ffffff; font-size: 15px; font-weight: 600;">${data.host_name}</p>
                    </div>
                </div>

                <!-- Divider -->
                <div style="border-top: 1px solid #2a2a2a; margin: 0 -24px; padding: 0;"></div>

                <!-- Guests Row -->
                <div style="display: flex; margin-top: 20px;">
                    <div style="background: #f59e0b; width: 44px; height: 44px; border-radius: 12px; text-align: center; line-height: 44px; font-size: 18px; flex-shrink: 0;">🎫</div>
                    <div style="margin-left: 14px;">
                        <p style="margin: 0; color: #71717a; font-size: 11px; text-transform: uppercase; letter-spacing: 1px; font-weight: 600;">Guests</p>
                        <p style="margin: 3px 0 0; color: #ffffff; font-size: 15px; font-weight: 600;">${data.quantity} guest${data.quantity > 1 ? 's' : ''}</p>
                    </div>
                </div>
            </div>

            <!-- Payment Summary -->
            <div style="background: linear-gradient(135deg, #052e16 0%, #14532d 100%); border-radius: 16px; padding: 20px 24px; margin-top: 16px; border: 1px solid #166534;">
                <div style="display: flex; justify-content: space-between; align-items: center;">
                    <div>
                        <p style="margin: 0; color: #86efac; font-size: 12px; font-weight: 600; text-transform: uppercase; letter-spacing: 0.5px;">Total Paid</p>
                        <p style="margin: 4px 0 0; color: #ffffff; font-size: 24px; font-weight: 800;">${formattedAmount}</p>
                        ${data.payment_method ? `<p style="margin: 4px 0 0; color: #4ade80; font-size: 12px;">via ${data.payment_method}</p>` : ''}
                    </div>
                    <div style="text-align: right;">
                        <div style="background: #22c55e; color: #fff; padding: 8px 16px; border-radius: 10px; font-size: 13px; font-weight: 700;">✓ Paid</div>
                    </div>
                </div>
            </div>

            <!-- QR Pass Notice -->
            <div style="text-align: center; margin-top: 32px; padding: 24px 0; border-top: 1px dashed #2a2a2a;">
                <div style="background: #1a1a1a; display: inline-block; padding: 12px 24px; border-radius: 12px; border: 1px solid #2a2a2a;">
                    <p style="margin: 0; color: #ffffff; font-size: 14px; font-weight: 600;">📎 Your Experience Pass is attached</p>
                    <p style="margin: 6px 0 0; color: #71717a; font-size: 12px;">Show the QR code to the host for check-in</p>
                </div>
            </div>

        </div>

        <!-- Footer -->
        <div style="padding: 20px 24px 40px; text-align: center; border-top: 1px solid #1a1a1a;">
            <p style="color: #3f3f46; font-size: 11px; margin: 0;">Ref: ${data.transaction_ref}</p>
            <p style="color: #3f3f46; font-size: 11px; margin: 6px 0 0;">© ${new Date().getFullYear()} HangHut · All rights reserved</p>
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
