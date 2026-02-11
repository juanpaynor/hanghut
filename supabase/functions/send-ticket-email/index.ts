
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { PDFDocument, StandardFonts, rgb, PDFFont } from "https://esm.sh/pdf-lib@1.17.1"
import { encode as base64Encode } from "https://deno.land/std@0.168.0/encoding/base64.ts"

const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY")

const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

interface TicketData {
    ticket_number: string
    qr_code: string
}

interface EmailRequest {
    email: string
    name?: string
    event_title: string
    event_venue: string
    event_date: string // Expected ISO string
    event_cover_image?: string
    ticket_quantity: number
    total_amount: number
    transaction_ref: string
    payment_method?: string // New field
    tickets: TicketData[]
}

// FORMATTER: Date
function formatEventDate(isoDate: string): string {
    try {
        if (!isoDate) return 'Date TBA'
        const date = new Date(isoDate)
        if (isNaN(date.getTime())) return isoDate // Return raw string if parse fails

        return date.toLocaleDateString('en-US', {
            weekday: 'long',
            year: 'numeric',
            month: 'long',
            day: 'numeric',
            hour: 'numeric',
            minute: '2-digit'
        })
    } catch (e) {
        return isoDate || 'Date Error'
    }
}

// FORMATTER: Currency
function formatCurrency(amount: number): string {
    return `PHP ${amount.toLocaleString('en-US', { minimumFractionDigits: 2 })}`
}

// Helper: Generate Invoice PDF
async function generateInvoicePdf(data: EmailRequest): Promise<Uint8Array> {
    console.log('📄 [Step] Generating Invoice PDF...')
    const pdfDoc = await PDFDocument.create()
    const page = pdfDoc.addPage([595.28, 841.89]) // A4
    const { width, height } = page.getSize()
    const font = await pdfDoc.embedFont(StandardFonts.Helvetica)
    const boldFont = await pdfDoc.embedFont(StandardFonts.HelveticaBold)

    // Colors
    // Primary: #6B7FFF (Indigo) -> R:0.42, G:0.5, B:1.0
    const primaryColor = rgb(0.42, 0.5, 1.0)
    const highlightColor = rgb(0.2, 0.2, 0.8) // Darker Indigo for text/lines
    const grayColor = rgb(0.4, 0.4, 0.4)
    const lightGray = rgb(0.95, 0.95, 0.95)

    const formattedDate = formatEventDate(data.event_date)

    // --- HEADER SECTION (Full Width Maroon) ---
    const headerHeight = 140
    page.drawRectangle({
        x: 0,
        y: height - headerHeight,
        width: width,
        height: headerHeight,
        color: primaryColor
    })

    // INVOICE Title (White, Neon underline)
    page.drawText('INVOICE', { x: 50, y: height - 60, size: 36, font: boldFont, color: rgb(1, 1, 1) })

    // Neon Orange Accent Line under title
    page.drawLine({
        start: { x: 50, y: height - 70 },
        end: { x: 200, y: height - 70 },
        thickness: 3,
        color: highlightColor
    })

    // Company Details (White text in header)
    const companyX = width - 250
    const companyY = height - 50

    page.drawText('HangHut Inc.', { x: companyX, y: companyY, size: 14, font: boldFont, color: rgb(1, 1, 1) })
    page.drawText('Level 40, PBcom Tower', { x: companyX, y: companyY - 20, size: 10, font: font, color: rgb(0.9, 0.9, 0.9) })
    page.drawText('Ayala Avenue, Makati', { x: companyX, y: companyY - 34, size: 10, font: font, color: rgb(0.9, 0.9, 0.9) })
    page.drawText('Metro Manila, Philippines', { x: companyX, y: companyY - 48, size: 10, font: font, color: rgb(0.9, 0.9, 0.9) })
    page.drawText('support@hanghut.com', { x: companyX, y: companyY - 62, size: 10, font: boldFont, color: highlightColor })

    // --- INFO ROW ---
    const infoY = height - 190

    // Status Badge (Paid)
    page.drawRectangle({ x: width - 120, y: infoY, width: 70, height: 26, color: rgb(0.9, 1, 0.9), borderColor: rgb(0, 0.6, 0), borderWidth: 1 })
    page.drawText('PAID', { x: width - 103, y: infoY + 7, size: 12, font: boldFont, color: rgb(0, 0.6, 0) })

    // LEFT: Bill To
    page.drawText('BILL TO', { x: 50, y: infoY + 10, size: 9, font: boldFont, color: grayColor })
    page.drawText((data.name || data.email).toUpperCase(), { x: 50, y: infoY - 10, size: 14, font: boldFont, color: rgb(0.1, 0.1, 0.1) })
    page.drawText(data.email, { x: 50, y: infoY - 25, size: 10, font: font, color: grayColor })

    // Payment Method (Below Email)
    if (data.payment_method) {
        page.drawText(`Paid via ${data.payment_method.toUpperCase()}`, { x: 50, y: infoY - 45, size: 9, font: font, color: rgb(0.3, 0.3, 0.3) })
    }

    // RIGHT: Invoice Meta
    const metaX = width - 250
    page.drawText('DATE', { x: metaX, y: infoY + 10, size: 9, font: boldFont, color: grayColor })
    page.drawText(new Date().toLocaleDateString(), { x: metaX, y: infoY - 5, size: 11, font: font, color: rgb(0.1, 0.1, 0.1) })

    page.drawText('REFERENCE', { x: metaX + 100, y: infoY + 10, size: 9, font: boldFont, color: grayColor })
    page.drawText(data.transaction_ref.substring(0, 12), { x: metaX + 100, y: infoY - 5, size: 11, font: font, color: rgb(0.1, 0.1, 0.1) })

    // --- TABLE SECTION ---
    const tableTop = infoY - 60

    // Header Bar
    page.drawRectangle({ x: 40, y: tableTop, width: width - 80, height: 25, color: lightGray })
    page.drawText('DESCRIPTION', { x: 50, y: tableTop + 7, size: 9, font: boldFont, color: rgb(0.3, 0.3, 0.3) })
    page.drawText('QTY', { x: 400, y: tableTop + 7, size: 9, font: boldFont, color: rgb(0.3, 0.3, 0.3) })
    page.drawText('TOTAL', { x: 480, y: tableTop + 7, size: 9, font: boldFont, color: rgb(0.3, 0.3, 0.3) })

    // Item Row
    const rowY = tableTop - 30
    page.drawText(data.event_title, { x: 50, y: rowY, size: 11, font: boldFont, color: rgb(0, 0, 0) })
    page.drawText(`Event Date: ${formattedDate}`, { x: 50, y: rowY - 15, size: 9, font: font, color: grayColor })

    page.drawText(`${data.ticket_quantity}`, { x: 405, y: rowY, size: 11, font: font, color: rgb(0, 0, 0) })
    page.drawText(formatCurrency(data.total_amount), { x: 480, y: rowY, size: 11, font: boldFont, color: rgb(0, 0, 0) })

    // Divider
    const totalLineY = rowY - 40
    page.drawLine({ start: { x: 40, y: totalLineY }, end: { x: width - 40, y: totalLineY }, thickness: 1, color: rgb(0.9, 0.9, 0.9) })

    // --- TOTALS ---
    const totalsY = totalLineY - 30
    // Subtotal area could go here, but focusing on Total

    // Big Total Box
    page.drawText('TOTAL PAID', { x: 350, y: totalsY, size: 12, font: boldFont, color: grayColor })
    page.drawText(formatCurrency(data.total_amount), { x: 450, y: totalsY, size: 18, font: boldFont, color: primaryColor })

    // --- FOOTER ---
    const footerY = 50
    page.drawLine({ start: { x: 40, y: footerY + 20 }, end: { x: width - 40, y: footerY + 20 }, thickness: 1, color: highlightColor }) // Neon footer line

    const year = new Date().getFullYear()
    page.drawText(`\u00A9 ${year} Hanghut Inc. All rights reserved.`, { x: 50, y: footerY, size: 9, font: font, color: grayColor })
    page.drawText('HangHut is a registered trademark.', { x: 50, y: footerY - 14, size: 8, font: font, color: rgb(0.7, 0.7, 0.7) })

    page.drawText('support@hanghut.com', { x: width - 150, y: footerY, size: 9, font: font, color: primaryColor })

    return await pdfDoc.save()
}

// Helper: Generate Tickets PDF
async function generateTicketsPdf(data: EmailRequest): Promise<Uint8Array> {
    console.log('🎟️ [Step] Generating Tickets PDF...')
    const pdfDoc = await PDFDocument.create()
    const font = await pdfDoc.embedFont(StandardFonts.Helvetica)
    const boldFont = await pdfDoc.embedFont(StandardFonts.HelveticaBold)

    const formattedDate = formatEventDate(data.event_date)

    // Embed Cover Image if available
    let coverImage = null
    if (data.event_cover_image) {
        try {
            const imgRes = await fetch(data.event_cover_image)
            const imgBuffer = await imgRes.arrayBuffer()
            // Assume JPEG for now (common in Supabase Storage), fall safely if PNG
            // Ideally check content-type
            try {
                coverImage = await pdfDoc.embedJpg(imgBuffer)
            } catch {
                coverImage = await pdfDoc.embedPng(imgBuffer)
            }
        } catch (e) {
            console.error('Failed to load cover image for PDF', e)
        }
    }

    for (const ticket of data.tickets) {
        const page = pdfDoc.addPage([400, 800]) // Mobile-friendly size
        const { width, height } = page.getSize()

        // --- VISUAL HEADER (Image or Color) ---
        if (coverImage) {
            page.drawImage(coverImage, {
                x: 0,
                y: height - 250,
                width: width,
                height: 250,
            })
            // Darker Blue Tint for Indigo Theme
            page.drawRectangle({ x: 0, y: height - 250, width: width, height: 250, color: rgb(0, 0, 0.2), opacity: 0.3 })
        } else {
            // Fallback Indigo
            page.drawRectangle({ x: 0, y: height - 200, width: width, height: 200, color: rgb(0.42, 0.5, 1.0) })
        }

        // Event Title (Over Image/Color)
        let titleFontSize = 24
        if (data.event_title.length > 20) titleFontSize = 18

        // Multi-line Title Logic
        // Simple manual wrap - split at space if too long?
        // For now, just truncating or shrinking fits better reliably
        page.drawText(data.event_title.toUpperCase(), {
            x: 30, y: height - 60, size: titleFontSize, font: boldFont, color: rgb(1, 1, 1), maxWidth: 340
        })

        page.drawText('OFFICIAL TICKET', { x: 30, y: height - 100, size: 10, font: font, color: rgb(0.9, 0.9, 0.9) })

        // --- BODY ---
        // White Background below image
        // (Page is already white, but let's be explicit if we changed background)

        let currentY = height - 280
        const labelColor = rgb(0.5, 0.5, 0.5)
        const textColor = rgb(0.1, 0.1, 0.1)

        // Date
        page.drawText('DATE & TIME', { x: 30, y: currentY, size: 9, font: boldFont, color: labelColor })
        page.drawText(formattedDate, { x: 30, y: currentY - 15, size: 14, font: font, color: textColor })

        currentY -= 50

        // Venue
        page.drawText('LOCATION', { x: 30, y: currentY, size: 9, font: boldFont, color: labelColor })
        page.drawText(data.event_venue, { x: 30, y: currentY - 15, size: 14, font: font, color: textColor, maxWidth: 340 })

        currentY -= 50

        // Holder
        page.drawText('TICKET HOLDER', { x: 30, y: currentY, size: 9, font: boldFont, color: labelColor })
        page.drawText((data.name || data.email).toUpperCase(), { x: 30, y: currentY - 15, size: 14, font: boldFont, color: textColor })

        // --- QR CODE SECTION ---
        const boxY = 150
        const boxSize = 250
        const boxX = (width - boxSize) / 2

        // "Cut Here" Dashed Line
        for (let i = 0; i < width; i += 15) {
            page.drawLine({ start: { x: i, y: boxY + boxSize + 60 }, end: { x: i + 8, y: boxY + boxSize + 60 }, thickness: 1, color: rgb(0.8, 0.8, 0.8) })
        }

        // Fetch QR Code Image
        try {
            const qrUrl = `https://api.qrserver.com/v1/create-qr-code/?size=500x500&format=png&data=${encodeURIComponent(ticket.qr_code)}`
            // console.log(`   [QR] Fetching: ${qrUrl}`)
            const qrRes = await fetch(qrUrl)
            if (!qrRes.ok) throw new Error(`QR API returned ${qrRes.status}`)
            const qrBuffer = await qrRes.arrayBuffer()
            const qrImage = await pdfDoc.embedPng(qrBuffer)

            page.drawImage(qrImage, {
                x: boxX,
                y: boxY,
                width: boxSize,
                height: boxSize,
            })
        } catch (e) {
            console.error('   [QR] Error:', e)
            page.drawText('QR Load Error', { x: 150, y: boxY + 100, size: 12, font: boldFont, color: rgb(1, 0, 0) })
        }

        // Ticket Number below QR
        const ticketNum = `#${ticket.ticket_number}`
        const numWidth = font.widthOfTextAtSize(ticketNum, 16)
        page.drawText(ticketNum, { x: (width - numWidth) / 2, y: boxY - 30, size: 16, font: font, color: rgb(0.3, 0.3, 0.3) })
    }

    return await pdfDoc.save()
}

serve(async (req) => {
    if (req.method === 'OPTIONS') {
        return new Response('ok', { headers: corsHeaders })
    }

    try {
        console.log('📩 [Start] Processing email request...')
        const requestData: EmailRequest = await req.json()
        console.log(`   [Target] ${requestData.email}, Ref: ${requestData.transaction_ref}`)

        // 1. Generate PDFs
        let invoiceBase64 = ''
        let ticketsBase64 = ''
        try {
            const invoicePdfBytes = await generateInvoicePdf(requestData)
            invoiceBase64 = base64Encode(invoicePdfBytes)

            const ticketsPdfBytes = await generateTicketsPdf(requestData)
            ticketsBase64 = base64Encode(ticketsPdfBytes)
            console.log('📄 [Docs] PDFs generated and encoded successfully')
        } catch (pdfError) {
            console.error('💥 [PDF Error]', pdfError)
            return new Response(JSON.stringify({ error: `PDF Generation Failed: ${pdfError.message}` }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 500 })
        }

        // 2. Format Data for Email
        const formattedAmount = formatCurrency(Number(requestData.total_amount))
        const formattedDate = formatEventDate(requestData.event_date)

        // 3. Premium Email HTML
        const html = `
    <!DOCTYPE html>
    <html>
    <head>
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
    </head>
    <body style="font-family: 'Helvetica Neue', Helvetica, Arial, sans-serif; background-color: #f3f4f6; padding: 40px 0; margin: 0; color: #333;">
      <div style="background-color: #ffffff; max-width: 600px; margin: 0 auto; border-radius: 12px; overflow: hidden; box-shadow: 0 4px 12px rgba(0,0,0,0.05);">
        
        <!-- Header -->
        <div style="background-color: #0f172a; padding: 40px 20px; text-align: center;">
            <h1 style="color: #ffffff; margin: 0; font-size: 24px; font-weight: 700; letter-spacing: -0.5px;">Your Order is Confirmed</h1>
            <p style="color: #94a3b8; margin: 10px 0 0; font-size: 16px;">We're excited to see you there!</p>
        </div>

        <!-- Event Details Card -->
        <div style="padding: 40px 30px;">
            <div style="margin-bottom: 25px;">
                ${requestData.event_cover_image ? `<img src="${requestData.event_cover_image}" alt="Event Cover" style="width: 100%; height: 200px; object-fit: cover; border-radius: 8px; margin-bottom: 20px;">` : ''}
                <h2 style="color: #0f172a; margin: 0; font-size: 20px; line-height: 1.4;">${requestData.event_title}</h2>
            </div>
            
            <table style="width: 100%; border-collapse: collapse;">
                <tr>
                    <td style="padding-bottom: 20px; vertical-align: top; width: 40px;">
                        📅
                    </td>
                    <td style="padding-bottom: 20px; vertical-align: top;">
                        <p style="margin: 0; font-size: 12px; text-transform: uppercase; color: #64748b; font-weight: 600;">Date</p>
                        <p style="margin: 4px 0 0; color: #0f172a; font-weight: 500;">${formattedDate}</p>
                    </td>
                </tr>
                <tr>
                    <td style="padding-bottom: 20px; vertical-align: top;">
                        📍
                    </td>
                    <td style="padding-bottom: 20px; vertical-align: top;">
                        <p style="margin: 0; font-size: 12px; text-transform: uppercase; color: #64748b; font-weight: 600;">Location</p>
                        <p style="margin: 4px 0 0; color: #0f172a; font-weight: 500;">${requestData.event_venue}</p>
                    </td>
                </tr>
            </table>

            <!-- Success Box -->
             <div style="background-color: #f0fdf4; border: 1px solid #dcfce7; border-radius: 8px; padding: 16px; margin-top: 10px; display: flex; align-items: center;">
                <div style="font-size: 20px; margin-right: 12px;">✅</div>
                <div>
                     <p style="margin: 0; font-size: 14px; color: #166534; font-weight: 600;">Payment Successful</p>
                     <p style="margin: 2px 0 0; font-size: 13px; color: #15803d;">Total Paid: ${formattedAmount}</p>
                     ${requestData.payment_method ? `<p style="margin: 2px 0 0; font-size: 12px; color: #15803d; opacity: 0.8;">via ${requestData.payment_method}</p>` : ''}
                </div>
            </div>

            <!-- Attachments Notice -->
            <div style="margin-top: 30px; text-align: center; border-top: 1px dashed #e2e8f0; padding-top: 30px;">
                <p style="color: #475569; font-size: 15px; line-height: 1.6;">
                    Your <strong>${requestData.ticket_quantity} ticket(s)</strong> and receipt are attached to this email as PDF files.
                    <br><span style="font-size: 13px; color: #64748b;">(Please save them or print them out before the event)</span>
                </p>
            </div>
        </div>

        <!-- Footer -->
        <div style="background-color: #f8fafc; padding: 20px; text-align: center; font-size: 12px; color: #94a3b8; border-top: 1px solid #e2e8f0;">
            <p style="margin: 0;">Ref: ${requestData.transaction_ref}</p>
            <p style="margin: 5px 0 0;">&copy; ${new Date().getFullYear()} HangHut. All rights reserved.</p>
        </div>

      </div>
    </body>
    </html>
    `

        // 3. Send Email (with Retry Logic)
        console.log('🚀 [Send] Sending via Resend API...')

        if (!RESEND_API_KEY) {
            throw new Error("Missing RESEND_API_KEY")
        }

        const maxRetries = 3;
        let attempt = 0;
        let sendSuccess = false;
        let responseData = null;
        let finalStatus = 500;

        while (attempt < maxRetries && !sendSuccess) {
            attempt++;
            try {
                const resendRes = await fetch('https://api.resend.com/emails', {
                    method: 'POST',
                    headers: {
                        'Authorization': `Bearer ${RESEND_API_KEY}`,
                        'Content-Type': 'application/json'
                    },
                    body: JSON.stringify({
                        from: 'HangHut Tickets <tickets@hanghut.com>',
                        to: [requestData.email],
                        subject: `Your Tickets for ${requestData.event_title} 🎟️`,
                        html: html,
                        attachments: [
                            {
                                filename: 'Invoice.pdf',
                                content: invoiceBase64
                            },
                            {
                                filename: 'Tickets.pdf',
                                content: ticketsBase64
                            }
                        ]
                    })
                })

                responseData = await resendRes.json()
                finalStatus = resendRes.status

                if (resendRes.ok) {
                    sendSuccess = true;
                } else if (resendRes.status === 429) {
                    // Rate Limit Hit - Wait and Retry
                    console.warn(`⚠️ [Rate Limit] Hit limit on attempt ${attempt}. Waiting...`)
                    const waitTime = Math.pow(2, attempt) * 1000; // 2s, 4s, 8s
                    await new Promise(resolve => setTimeout(resolve, waitTime));
                } else {
                    // Other error (400, 401, 500) - Throw to exit loop
                    throw new Error(responseData.message || JSON.stringify(responseData));
                }

            } catch (e) {
                // If it was a 429 that exhausted retries, or another error
                console.error(`❌ [Attempt ${attempt} Failed]`, e.message || e);
                if (attempt >= maxRetries || finalStatus !== 429) {
                    // Stop trying if max retries reached or if it's not a rate limit issue
                    if (!responseData) responseData = { error: e.message || "Unknown error" };
                    break;
                }
            }
        }

        if (!sendSuccess) {
            console.error('❌ [Resend Error] Failed after retries:', responseData)
            return new Response(JSON.stringify({ error: responseData }), {
                headers: { ...corsHeaders, 'Content-Type': 'application/json' },
                status: finalStatus,
            })
        }

        console.log('✅ [Success] Email sent:', responseData)
        return new Response(JSON.stringify(responseData), {
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
            status: 200,
        })

    } catch (error) {
        console.error('❌ [Global Error]', error)
        return new Response(JSON.stringify({ error: error.message }), {
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
            status: 500,
        })
    }
})
