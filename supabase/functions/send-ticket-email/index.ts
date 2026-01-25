
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
    ticket_quantity: number
    total_amount: number
    transaction_ref: string
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

    const formattedDate = formatEventDate(data.event_date)

    // Header Background
    page.drawRectangle({ x: 0, y: height - 100, width: width, height: 100, color: rgb(0.96, 0.96, 0.96) })

    // Header Text
    page.drawText('INVOICE', { x: 50, y: height - 60, size: 24, font: boldFont, color: rgb(0.1, 0.1, 0.1) })
    page.drawText('HangHut Inc.', { x: 50, y: height - 85, size: 10, font: font, color: rgb(0.5, 0.5, 0.5) })

    // RIGHT Header
    const textDate = `Date: ${new Date().toLocaleDateString()}`
    const textRef = `Ref: ${data.transaction_ref}`
    page.drawText(textDate, { x: width - 50 - font.widthOfTextAtSize(textDate, 10), y: height - 60, size: 10, font: font, color: rgb(0.3, 0.3, 0.3) })
    page.drawText(textRef, { x: width - 50 - font.widthOfTextAtSize(textRef, 10), y: height - 75, size: 10, font: font, color: rgb(0.3, 0.3, 0.3) })

    // Bill To Section
    const startY = height - 150
    page.drawText('BILL TO:', { x: 50, y: startY, size: 8, font: boldFont, color: rgb(0.6, 0.6, 0.6) })
    page.drawText(data.name || data.email, { x: 50, y: startY - 15, size: 12, font: boldFont, color: rgb(0, 0, 0) })
    page.drawText(data.email, { x: 50, y: startY - 30, size: 10, font: font, color: rgb(0.4, 0.4, 0.4) })

    // Table Headers
    const tableY = startY - 70
    page.drawRectangle({ x: 40, y: tableY - 10, width: width - 80, height: 25, color: rgb(0.95, 0.95, 0.95) })
    page.drawText('DESCRIPTION', { x: 50, y: tableY, size: 9, font: boldFont, color: rgb(0.4, 0.4, 0.4) })
    page.drawText('AMOUNT', { x: 480, y: tableY, size: 9, font: boldFont, color: rgb(0.4, 0.4, 0.4) })

    // Line Item
    const itemY = tableY - 40
    const desc = `${data.event_title} (${data.ticket_quantity} Tickets)`
    const price = formatCurrency(data.total_amount)

    page.drawText(desc, { x: 50, y: itemY, size: 10, font: font, color: rgb(0.1, 0.1, 0.1) })
    page.drawText(price, { x: 480, y: itemY, size: 10, font: font, color: rgb(0.1, 0.1, 0.1) })

    // Total Section
    const totalY = itemY - 60
    page.drawLine({ start: { x: 40, y: totalY + 20 }, end: { x: width - 40, y: totalY + 20 }, thickness: 1, color: rgb(0.9, 0.9, 0.9) })

    page.drawText('TOTAL', { x: 380, y: totalY, size: 12, font: boldFont, color: rgb(0, 0, 0) })
    page.drawText(price, { x: 480, y: totalY, size: 12, font: boldFont, color: rgb(0, 0, 0) })

    // Footer
    page.drawText('Thank you for your purchase!', { x: 50, y: 100, size: 10, font: font, color: rgb(0.6, 0.6, 0.6) })
    page.drawText('This is a computer-generated invoice.', { x: 50, y: 85, size: 8, font: font, color: rgb(0.7, 0.7, 0.7) })

    return await pdfDoc.save()
}

// Helper: Generate Tickets PDF
async function generateTicketsPdf(data: EmailRequest): Promise<Uint8Array> {
    console.log('🎟️ [Step] Generating Tickets PDF...')
    const pdfDoc = await PDFDocument.create()
    const font = await pdfDoc.embedFont(StandardFonts.Helvetica)
    const boldFont = await pdfDoc.embedFont(StandardFonts.HelveticaBold)

    const formattedDate = formatEventDate(data.event_date)

    for (const ticket of data.tickets) {
        const page = pdfDoc.addPage([400, 700]) // Mobile-friendly size
        const { width, height } = page.getSize()

        // Gradient-ish Header (Solid dark)
        page.drawRectangle({ x: 0, y: height - 120, width: width, height: 120, color: rgb(0.1, 0.1, 0.2) })

        // Event Title (White)
        // Simple text wrapping logic for title
        let titleFontSize = 18
        if (data.event_title.length > 25) titleFontSize = 14

        page.drawText(data.event_title.toUpperCase(), {
            x: 30, y: height - 50, size: titleFontSize, font: boldFont, color: rgb(1, 1, 1), maxWidth: 340
        })

        page.drawText('ADMIT ONE', { x: 30, y: height - 90, size: 10, font: font, color: rgb(0.8, 0.8, 0.8) })

        // Body Container
        // Details
        let currentY = height - 160
        const labelColor = rgb(0.6, 0.6, 0.6)
        const textColor = rgb(0.1, 0.1, 0.1)

        // Date
        page.drawText('DATE & TIME', { x: 30, y: currentY, size: 8, font: boldFont, color: labelColor })
        page.drawText(formattedDate, { x: 30, y: currentY - 15, size: 12, font: font, color: textColor })

        currentY -= 50

        // Venue
        page.drawText('LOCATION', { x: 30, y: currentY, size: 8, font: boldFont, color: labelColor })
        // Basic wrap for venue if needed
        page.drawText(data.event_venue, { x: 30, y: currentY - 15, size: 12, font: font, color: textColor, maxWidth: 340 })

        currentY -= 50

        // Holder
        page.drawText('TICKET HOLDER', { x: 30, y: currentY, size: 8, font: boldFont, color: labelColor })
        page.drawText(data.name || data.email, { x: 30, y: currentY - 15, size: 12, font: font, color: textColor })

        // QR Code Section (Centered Box)
        const boxY = 160
        const boxSize = 220
        const boxX = (width - boxSize) / 2

        // Dashed Line (simulated with small dots)
        for (let i = 0; i < width; i += 10) {
            page.drawText('-', { x: i, y: boxY + boxSize + 40, size: 10, font: font, color: rgb(0.8, 0.8, 0.8) })
        }

        // Border for QR
        page.drawRectangle({ x: boxX - 10, y: boxY - 10, width: boxSize + 20, height: boxSize + 20, borderColor: rgb(0.9, 0.9, 0.9), borderWidth: 2, color: rgb(1, 1, 1) })

        // Fetch QR Code Image
        try {
            const qrUrl = `https://api.qrserver.com/v1/create-qr-code/?size=400x400&data=${encodeURIComponent(ticket.qr_code)}`
            console.log(`   [QR] Fetching: ${qrUrl}`)
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
            page.drawText('QR Load Error', { x: 150, y: 300, size: 12, font: boldFont, color: rgb(1, 0, 0) })
        }

        // Footnote
        page.drawText(`#${ticket.ticket_number}`, { x: boxX, y: boxY - 30, size: 14, font: font, color: rgb(0.4, 0.4, 0.4) })
        page.drawText('Scan at entrance', { x: width / 2 - 40, y: boxY - 50, size: 10, font: font, color: rgb(0.7, 0.7, 0.7) })
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

        // 3. Send Email (Raw Fetch)
        console.log('🚀 [Send] Sending via Resend API (Raw Fetch)...')

        if (!RESEND_API_KEY) {
            throw new Error("Missing RESEND_API_KEY")
        }

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

        const responseData = await resendRes.json()

        if (!resendRes.ok) {
            console.error('❌ [Resend Error]', responseData)
            return new Response(JSON.stringify({ error: responseData }), {
                headers: { ...corsHeaders, 'Content-Type': 'application/json' },
                status: resendRes.status,
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
