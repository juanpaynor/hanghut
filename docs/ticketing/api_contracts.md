# HangHut Event Ticketing - API Contract Documentation

## 📋 Overview

This document defines the API contracts between **Mobile App** and **Backend (Web Team)**.

**Principles:**
- RESTful where possible
- Supabase RPC functions for complex logic
- Supabase Edge Functions for external integrations (Xendit)
- All timestamps in ISO 8601 format
- All UUIDs as strings
- Consistent error format

---

## 🔐 Authentication

All requests (except public event browsing) require authentication via Supabase JWT.

**Headers:**
```
Authorization: Bearer <supabase_jwt_token>
```

---

## 📍 1. Event Discovery & Browsing

### GET Events in Viewport

**Purpose:** Fetch events visible in current map area  
**Method:** Supabase RPC  
**Owner:** Backend (Web Team builds RPC)  
**Consumer:** Mobile App

**Request:**
```typescript
supabase.rpc('get_events_in_viewport', {
  min_lat: number,
  max_lat: number,
  min_lng: number,
  max_lng: number,
  event_type?: string,  // 'concert' | 'workshop' | etc.
  start_after?: string, // ISO timestamp, only future events
  limit?: number        // default: 50
})
```

**Response:**
```typescript
{
  data: [
    {
      id: string,              // UUID
      title: string,
      description: string,
      latitude: number,
      longitude: number,
      venue_name: string,
      address: string,
      start_datetime: string,  // ISO 8601
      end_datetime: string | null,
      event_type: 'concert' | 'workshop' | ...,
      ticket_price: number,    // Decimal, in PHP
      capacity: number,
      tickets_sold: number,
      cover_image_url: string | null,
      status: 'active' | 'sold_out',
      
      // Organizer info
      organizer: {
        id: string,
        business_name: string,
        verified: boolean
      },
      
      // Computed fields
      tickets_available: number,  // capacity - tickets_sold
      is_sold_out: boolean,
      
      created_at: string
    }
  ],
  error: null
}
```

**Error Cases:**
```typescript
{
  data: null,
  error: {
    message: "Invalid viewport coordinates",
    code: "INVALID_VIEWPORT"
  }
}
```

---

### GET Event Details

**Purpose:** Get full details of a specific event  
**Method:** Supabase Query  
**Owner:** Direct DB query (Mobile handles)  
**Consumer:** Mobile App

**Request:**
```typescript
supabase
  .from('events')
  .select(`
    *,
    organizer:partners(
      id,
      business_name,
      verified
    )
  `)
  .eq('id', eventId)
  .single()
```

**Response:**
```typescript
{
  data: {
    // Same as above + additional fields
    images: string[],  // Array of image URLs
    min_tickets_per_purchase: number,
    max_tickets_per_purchase: number
  },
  error: null
}
```

---

## 🎫 2. Ticket Purchase Flow

### POST Create Purchase Intent

**Purpose:** Reserve tickets and create payment  
**Method:** Supabase Edge Function  
**Owner:** Backend (Web Team)  
**Consumer:** Mobile App

**Endpoint:**
```
POST /functions/v1/create-purchase-intent
```

**Request Headers:**
```
Authorization: Bearer <jwt>
Content-Type: application/json
```

**Request Body:**
```typescript
{
  event_id: string,    // UUID
  quantity: number,    // 1-10
  user_id: string      // UUID (from auth)
}
```

**Response (Success):**
```typescript
{
  success: true,
  data: {
    intent_id: string,           // UUID
    subtotal: number,            // ticket_price × quantity
    platform_fee: number,        // subtotal × fee_percentage
    total_amount: number,        // subtotal + platform_fee + processing_fee
    
    // Xendit payment details
    xendit_invoice_id: string,
    payment_url: string,         // Redirect user here
    expires_at: string,          // ISO timestamp, 15min from now
    
    // Reservation
    tickets_reserved: number,
    event: {
      title: string,
      start_datetime: string
    }
  }
}
```

**Response (Error):**
```typescript
{
  success: false,
  error: {
    code: "SOLD_OUT" | "INSUFFICIENT_CAPACITY" | "INVALID_QUANTITY" | "EVENT_NOT_FOUND",
    message: string
  }
}
```

**Error Codes:**
- `SOLD_OUT`: Event is fully sold out
- `INSUFFICIENT_CAPACITY`: Not enough tickets for quantity
- `INVALID_QUANTITY`: Quantity exceeds max per purchase
- `EVENT_NOT_FOUND`: Event ID doesn't exist
- `UNAUTHORIZED`: Not logged in

**Business Logic (Backend handles):**
1. Verify event exists and is active
2. Check capacity (atomic lock)
3. Calculate fees based on partner pricing
4. Create purchase_intent record
5. Reserve tickets (increment tickets_sold)
6. Call Xendit API to create invoice
7. Return payment URL

---

### Webhook: Payment Confirmation

**Purpose:** Xendit notifies backend of payment status  
**Method:** Supabase Edge Function (Webhook)  
**Owner:** Backend (Web Team)  
**Consumer:** Xendit

**Endpoint:**
```
POST /functions/v1/xendit-webhook
```

**Request (from Xendit):**
```typescript
{
  event: "invoice.paid" | "invoice.expired" | "invoice.failed",
  external_id: string,  // Our purchase_intent_id
  invoice_id: string,
  status: "PAID" | "EXPIRED" | "FAILED",
  amount: number,
  paid_at: string,
  // ... other Xendit fields
}
```

**Backend Actions:**
```typescript
if (event === "invoice.paid") {
  1. Verify webhook signature
  2. Find purchase_intent by external_id
  3. Mark intent as 'completed'
  4. Generate tickets (1 per quantity)
  5. Create QR codes
  6. Record transaction
  7. Send confirmation email/push
}

if (event === "invoice.expired" || event === "invoice.failed") {
  1. Mark intent as 'failed' or 'expired'
  2. Release reserved capacity
  3. Send failure notification
}
```

**Mobile doesn't call this!** Backend handles automatically.

---

## 🎟️ 3. User Tickets

### GET My Tickets

**Purpose:** Fetch all user's purchased tickets  
**Method:** Supabase Query  
**Owner:** Mobile (direct DB query)  
**Consumer:** Mobile App

**Request:**
```typescript
supabase
  .from('tickets')
  .select(`
    *,
    event:events(
      id,
      title,
      venue_name,
      start_datetime,
      cover_image_url
    )
  `)
  .eq('user_id', userId)
  .order('created_at', { ascending: false })
```

**Response:**
```typescript
{
  data: [
    {
      id: string,
      ticket_number: string,         // e.g., "TK-ABC12345"
      qr_code: string,               // QR data string
      status: 'valid' | 'used' | 'cancelled',
      checked_in_at: string | null,
      
      event: {
        id: string,
        title: string,
        venue_name: string,
        start_datetime: string,
        cover_image_url: string | null
      },
      
      created_at: string
    }
  ],
  error: null
}
```

---

### POST Validate Ticket (QR Scanner)

**Purpose:** Validate and mark ticket as used  
**Method:** Supabase RPC  
**Owner:** Backend (Web Team builds RPC)  
**Consumer:** Mobile App (organizer scanner)

**Request:**
```typescript
supabase.rpc('validate_ticket', {
  qr_code: string,      // Scanned QR data
  event_id: string,     // Must match ticket's event
  scanner_user_id: string  // Who's scanning
})
```

**Response (Success):**
```typescript
{
  data: {
    valid: true,
    ticket_id: string,
    ticket_number: string,
    
    // Attendee info
    attendee: {
      name: string,
      email: string
    },
    
    // Event info (verify correct event)
    event: {
      id: string,
      title: string
    },
    
    checked_in_at: string,  // Now
    already_used: boolean    // Was it already scanned?
  },
  error: null
}
```

**Response (Invalid):**
```typescript
{
  data: {
    valid: false,
    reason: "ALREADY_USED" | "WRONG_EVENT" | "CANCELLED" | "NOT_FOUND"
  },
  error: null
}
```

**Backend Logic:**
1. Find ticket by QR code
2. Verify ticket is 'valid' status
3. Verify ticket.event_id matches request event_id
4. Check not already checked_in
5. Mark as used (checked_in_at = NOW())
6. Return attendee info

---

## 👤 4. Partner Application

### POST Submit Partner Application

**Purpose:** User applies to become event organizer  
**Method:** Supabase Edge Function  
**Owner:** Backend (Web Team)  
**Consumer:** Mobile App

**Endpoint:**
```
POST /functions/v1/apply-partner
```

**Request Body:**
```typescript
{
  // Personal info
  full_name: string,
  email: string,        // Already verified
  phone: string,        // Already verified
  
  // Business info
  business_name: string,
  business_type: 'individual' | 'sole_proprietorship' | 'corporation' | 'partnership',
  event_type: 'concert' | 'workshop' | ...,
  social_media_url?: string,
  
  // Verification
  id_front_url: string,   // Uploaded to Supabase Storage
  id_back_url?: string,
  selfie_url: string,
  
  // Terms
  terms_accepted: boolean
}
```

**Response (Success):**
```typescript
{
  success: true,
  data: {
    partner_id: string,
    status: 'pending' | 'approved',  // Auto-approved if passes checks
    tier: 1,
    approved_at: string | null,
    message: string  // e.g., "Approved! You can create events now."
  }
}
```

**Response (Manual Review):**
```typescript
{
  success: true,
  data: {
    partner_id: string,
    status: 'pending',
    tier: null,
    message: "Application received. We'll review within 24 hours."
  }
}
```

**Backend Logic:**
1. Create partner record
2. Run auto-approval checks:
   - Email/phone not blacklisted
   - ID OCR readable (optional)
   - No duplicate applications
3. If passes → approve as Tier 1
4. If flagged → mark for manual review
5. Send notification

---

### GET Partner Status

**Purpose:** Check application/partner status  
**Method:** Supabase Query  
**Owner:** Mobile (direct query)  
**Consumer:** Mobile App

**Request:**
```typescript
supabase
  .from('partners')
  .select('*')
  .eq('user_id', userId)
  .single()
```

**Response:**
```typescript
{
  data: {
    id: string,
    status: 'pending' | 'approved' | 'rejected' | 'suspended',
    pricing_model: 'standard' | 'custom',
    custom_percentage: number | null,
    verified: boolean,
    created_at: string,
    approved_at: string | null
  } | null,  // null if never applied
  error: null
}
```

---

## 📊 5. Partner Dashboard (Mobile)

### GET My Events

**Purpose:** Fetch partner's created events  
**Method:** Supabase Query  
**Owner:** Mobile  
**Consumer:** Mobile App

**Request:**
```typescript
const partner = await getPartnerProfile(userId);

supabase
  .from('events')
  .select('*')
  .eq('organizer_id', partner.id)
  .order('start_datetime', { ascending: false })
```

**Response:**
```typescript
{
  data: [
    {
      id: string,
      title: string,
      start_datetime: string,
      capacity: number,
      tickets_sold: number,
      ticket_price: number,
      status: 'active' | 'sold_out' | 'completed',
      cover_image_url: string | null
    }
  ],
  error: null
}
```

---

### GET Event Sales Summary

**Purpose:** Get sales/analytics for specific event  
**Method:** Materialized View Query  
**Owner:** Mobile (direct query)  
**Consumer:** Mobile App

**Request:**
```typescript
supabase
  .from('event_sales_summary')
  .select('*')
  .eq('event_id', eventId)
  .single()
```

**Response:**
```typescript
{
  data: {
    event_id: string,
    title: string,
    total_tickets_issued: number,
    tickets_used: number,           // Checked in
    total_revenue: number,          // Gross
    platform_revenue: number,       // HangHut's cut
    organizer_revenue: number       // Partner's cut
  },
  error: null
}
```

---

## 💰 6. Payouts

### POST Request Payout

**Purpose:** Partner requests to withdraw earnings  
**Method:** Supabase Edge Function  
**Owner:** Backend (Web Team)  
**Consumer:** Mobile App

**Endpoint:**
```
POST /functions/v1/request-payout
```

**Request Body:**
```typescript
{
  partner_id: string,
  event_id?: string,    // Optional: payout for specific event
  amount?: number       // Optional: partial payout
}
```

**Response:**
```typescript
{
  success: true,
  data: {
    payout_id: string,
    amount: number,
    status: 'pending_request',
    requested_at: string,
    estimated_completion: string  // 2-3 business days
  }
}
```

**Backend Logic:**
1. Calculate available balance
2. Verify bank account on file
3. Create payout record
4. Notify admin for approval (manual in MVP)

---

## 🔧 7. Maintenance & Utilities

### RPC: Release Expired Reservations

**Purpose:** Cron job to clean up expired purchase intents  
**Method:** Supabase RPC (called by pg_cron)  
**Owner:** Backend  
**Consumer:** System (automated)

**Call:**
```sql
SELECT release_expired_reservations();
```

**Returns:** Integer (count of released reservations)

---

### RPC: Refresh Analytics

**Purpose:** Update materialized views  
**Method:** Supabase RPC (called by pg_cron)  
**Owner:** Backend  
**Consumer:** System (automated)

**Call:**
```sql
SELECT refresh_analytics_views();
```

---

## 🚨 Error Response Format

**All endpoints use consistent error format:**

```typescript
{
  success: false,
  error: {
    code: string,      // Machine-readable code
    message: string,   // Human-readable message
    details?: any      // Optional additional context
  }
}
```

**Common Error Codes:**
- `UNAUTHORIZED`: Not logged in
- `FORBIDDEN`: Logged in but not allowed
- `NOT_FOUND`: Resource doesn't exist
- `VALIDATION_ERROR`: Invalid input
- `SOLD_OUT`: Event capacity reached
- `PAYMENT_FAILED`: Payment processing error
- `SERVER_ERROR`: Unexpected error

---

## 📱 Mobile → Backend Responsibilities

### Mobile Team Builds:
✅ Direct Supabase queries (events, tickets)  
✅ UI for all flows  
✅ QR code generation/scanning UI  
✅ Image upload to Supabase Storage  
✅ State management  

### Web Team Builds:
✅ Edge Functions (payments, webhooks)  
✅ RPC Functions (complex logic)  
✅ Admin panels  
✅ Organizer dashboards  
✅ Cron jobs  

---

## 🔗 Dependencies

**Mobile needs from Web:**
1. `create-purchase-intent` Edge Function (Week 3-4)
2. `xendit-webhook` Edge Function (Week 3-4)
3. `get_events_in_viewport` RPC (Week 3)
4. `validate_ticket` RPC (Week 5)
5. `apply-partner` Edge Function (Week 3)

**Web needs from Mobile:**
- Database schema agreement ✅
- Image upload format (Supabase Storage paths)
- Error handling expectations

---

## 🧪 Testing Plan

### Sandbox Testing:
- **Xendit Test Cards:** Use `4000000000000002`
- **Test Event IDs:** Create test events in staging DB
- **Test Users:** Separate test accounts for buyers/organizers

### API Testing Tools:
- **Postman Collection:** Web team provides
- **Supabase Studio:** Test RPC functions directly
- **Mobile:** Unit tests for API calls

---

**This contract is the source of truth for both teams!** 🤝
