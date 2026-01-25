we# Event Creation Form - Design Specification

## Overview
A full-featured event creation form for organizers to create ticketed events on both web and mobile platforms.

---

## Form Sections

### 1. Basic Information
**Fields:**
- **Event Title*** (required)
  - Type: Text input
  - Max length: 100 characters
  - Validation: Required, min 5 characters
  - Placeholder: "e.g., Summer Music Festival 2026"

- **Description** (optional)
  - Type: Textarea
  - Max length: 2000 characters
  - Rich text support (optional, simple markdown)
  - Placeholder: "Tell attendees what to expect..."

- **Event Type*** (required)
  - Type: Dropdown/Select
  - Options: 
    - Music & Concerts
    - Sports & Fitness
    - Food & Drink
    - Arts & Culture
    - Networking & Business
    - Other
  - Default: "Other"

---

### 2. Location & Venue
**Fields:**
- **Venue Name*** (required)
  - Type: Text input
  - Placeholder: "e.g., Sky Garden Bar"

- **Address*** (required)
  - Type: Text input or Address picker
  - Placeholder: "123 Main St, Manila"

- **Location (Map Picker)*** (required)
  - Type: Interactive map
  - User clicks map OR searches address to set location
  - Shows: Pin on map + Coordinates display
  - Automatically fills latitude/longitude
  - Falls back to manual lat/lng input if map unavailable

---

### 3. Date & Time
**Fields:**
- **Start Date & Time*** (required)
  - Type: DateTime picker
  - Format: YYYY-MM-DD HH:mm
  - Validation: Must be in the future
  - Timezone: Auto-detect user timezone or default to Manila (Asia/Manila)

- **End Date & Time** (optional)
  - Type: DateTime picker
  - Validation: Must be after start time if provided
  - Default: Empty (single-time event)

---

### 4. Ticketing & Pricing
**Fields:**
- **Ticket Price*** (required)
  - Type: Number input
  - Min: 0 (free events allowed)
  - Currency: PHP (₱)
  - Validation: >= 0
  - Placeholder: "0 for free events"

- **Total Capacity*** (required)
  - Type: Number input
  - Min: 1
  - Validation: > 0
  - Placeholder: "e.g., 100"

- **Min Tickets Per Purchase** (optional)
  - Type: Number input
  - Default: 1
  - Min: 1
  - Max: capacity
  - Tooltip: "Minimum tickets a user must buy"

- **Max Tickets Per Purchase** (optional)
  - Type: Number input
  - Default: 10
  - Min: 1
  - Max: capacity
  - Tooltip: "Maximum tickets a user can buy in one order"

**Pricing Display:**
- Show platform fee calculation: "Platform Fee: 10% (₱XX.XX)"
- Show organizer payout: "You'll receive: ₱XX.XX per ticket"

---

### 5. Media & Images
**Fields:**
- **Cover Image*** (required)
  - Type: Image upload
  - Accepted: JPG, PNG, WebP
  - Max size: 5MB
  - Recommended dimensions: 1200x630px (16:9)
  - Shows preview after upload
  - Storage: Supabase Storage bucket `event-covers`

- **Additional Images** (optional, max 5)
  - Type: Multiple image upload
  - Same specs as cover image
  - Stored as JSONB array of URLs
  - Storage: Supabase Storage bucket `event-images`

---

### 6. Publish Settings
**Fields:**
- **Status*** (required)
  - Type: Radio buttons or Toggle
  - Options:
    - **Draft**: Save but don't publish (default)
    - **Active**: Publish immediately and make visible to users
  - Note: Draft events can be edited and published later

---

## Form Validation Summary
| Field | Required | Min | Max | Format |
|-------|----------|-----|-----|--------|
| Title | ✅ | 5 chars | 100 chars | Text |
| Description | ❌ | - | 2000 chars | Text |
| Event Type | ✅ | - | - | Enum |
| Venue Name | ✅ | 3 chars | 100 chars | Text |
| Address | ✅ | 5 chars | 200 chars | Text |
| Latitude | ✅ | -90 | 90 | Number |
| Longitude | ✅ | -180 | 180 | Number |
| Start DateTime | ✅ | Future | - | ISO 8601 |
| End DateTime | ❌ | > Start | - | ISO 8601 |
| Ticket Price | ✅ | 0 | - | Number (2 decimals) |
| Capacity | ✅ | 1 | - | Integer |
| Min Tickets | ❌ | 1 | Capacity | Integer |
| Max Tickets | ❌ | 1 | Capacity | Integer |
| Cover Image | ✅ | - | 5MB | Image |
| Additional Images | ❌ | - | 5 images | Images |
| Status | ✅ | - | - | Enum (draft/active) |

---

## UX Flow

### Desktop (Web)
1. **Single-page vertical form** with sections
2. Sections are expandable/collapsible panels OR fixed sections
3. Fixed "Save Draft" and "Publish Event" buttons at the bottom
4. Autosave draft every 30 seconds (optional enhancement)
5. Confirmation modal before publishing

### Mobile (App)
1. **Multi-step wizard** (recommended)
   - Step 1: Basic Info
   - Step 2: Location
   - Step 3: Date & Time
   - Step 4: Ticketing
   - Step 5: Media
   - Step 6: Review & Publish
2. Progress indicator at top (1 of 6, 2 of 6, etc.)
3. "Next" and "Back" buttons
4. "Save Draft" option on every step

---

## Database Mapping

```typescript
interface EventFormData {
  title: string                    // → events.title
  description: string | null       // → events.description
  event_type: string               // → events.event_type
  venue_name: string               // → events.venue_name
  address: string                  // → events.address
  latitude: number                 // → events.latitude
  longitude: number                // → events.longitude
  start_datetime: string           // → events.start_datetime (ISO 8601)
  end_datetime: string | null      // → events.end_datetime (ISO 8601)
  ticket_price: number             // → events.ticket_price
  capacity: number                 // → events.capacity
  min_tickets_per_purchase: number // → events.min_tickets_per_purchase (default: 1)
  max_tickets_per_purchase: number // → events.max_tickets_per_purchase (default: 10)
  cover_image_url: string          // → events.cover_image_url
  images: string[] | null          // → events.images (JSONB array)
  status: 'draft' | 'active'       // → events.status
  organizer_id: string             // → events.organizer_id (auto-filled from session)
}
```

---

## API Endpoints Needed

### Web
- **POST** `/api/events/create` - Create new event
- **POST** `/api/events/upload-image` - Upload event images to storage
- **PATCH** `/api/events/:id` - Update draft event
- **POST** `/api/events/:id/publish` - Publish draft event

### Shared Logic (Server Actions)
- `createEvent(formData)` → Insert into `events` table
- `uploadEventImage(file, eventId)` → Upload to Supabase Storage
- `publishEvent(eventId)` → Update status to 'active'

---

## Success Flow
1. User fills out form
2. Clicks "Publish Event" (or "Save Draft")
3. **Validation runs** - shows errors if any
4. **Images upload** to Supabase Storage
5. **Event record created** in database
6. **Confirmation screen** with options:
   - View Event (public page)
   - Create Another Event
   - Go to My Events

---

## Error Handling
- **Field-level errors**: Show below each field in red
- **Form-level errors**: Show at top of form (e.g., "Failed to upload image")
- **Network errors**: Show retry button
- **Duplicate events**: Warn if similar event (same title + date) exists

---

## Future Enhancements (Phase 2)
- Multi-tier tickets (GA, VIP, etc.)
- Early bird pricing
- Promo codes
- Recurring events
- Co-organizers
- Event categories/tags
- Custom registration questions

---

## Notes for App Team
- **Event Type Enum**: Ensure `event_type` enum values match between web and mobile
- **Timezone Handling**: All datetimes stored in UTC, displayed in user's local timezone
- **Image Storage**: Use same Supabase Storage buckets (`event-covers`, `event-images`)
- **Status Workflow**: 
  - `draft` → editable, not visible to users
  - `active` → published, visible on map and event listings
  - `sold_out` → auto-set when tickets_sold >= capacity
  - `cancelled` → organizer cancelled
  - `completed` → past event (auto-set after end_datetime)
