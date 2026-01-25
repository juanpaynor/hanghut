# App Team Response to Web Team - Event Creation Clarifications

Great questions! Here are the definitive answers:

---

## ✅ CONFIRMED DECISIONS

### 1. Platform Fee - **ADMIN CONFIGURABLE**

**Answer:** The platform fee is **NOT a fixed percentage**. It's set by admins on a per-partner basis.

**Implementation:**
```typescript
// When showing pricing preview in event creation form:
const { data: partner } = await supabase
  .from('partners')
  .select('commission_rate')
  .eq('id', session.user.id)
  .single();

const platformFee = partner.commission_rate || 0.15; // Default 15% if not set
const organizerPayout = ticketPrice * (1 - platformFee);
```

**UI Display:**
```
Ticket Price: ₱500
Platform Fee (15%): -₱75
You'll receive: ₱425 per ticket
```

**Note:** The commission rate can vary by partner (some VIP partners might have 10%, new partners 15%, etc.). Always fetch from the database, never hardcode.

---

### 2. Multiple Images - **REQUIRED FEATURE**

**Answer:** Yes, implement multiple images. This is industry standard and critical for conversion.

**Database Migration Needed:**
```sql
-- Add images column to events table
ALTER TABLE events 
ADD COLUMN images jsonb DEFAULT '[]'::jsonb;

-- Add comment for documentation
COMMENT ON COLUMN events.images IS 'Array of additional event image URLs (max 5), stored as JSONB';
```

**Implementation:**
- Cover image: Required (existing `cover_image_url` field)
- Additional images: Optional, max 5 (new `images` JSONB array)
- Storage bucket: `event-images` (same as cover)

**Form UX:**
- Show cover image upload prominently
- Show "Add More Images (Optional)" section below
- Allow drag-and-drop reordering
- Max 5 additional images

---

### 3. City & Address - **USE GOOGLE PLACES API**

**Answer:** Use Google Places Autocomplete for location input. Auto-extract city from the structured response.

**Why Google Places:**
- ✅ You're already using it on mobile for table creation
- ✅ Provides structured data (street, city, province, lat/lng)
- ✅ Validates real addresses
- ✅ Consistent user experience across platforms

**Implementation:**
```typescript
// When user selects a place from autocomplete:
const placeDetails = await getPlaceDetails(placeId);

// Auto-fill form fields:
formData.address = placeDetails.formatted_address;  // "123 Main St, Makati, Metro Manila"
formData.city = placeDetails.city;                  // "Makati"
formData.latitude = placeDetails.geometry.location.lat;
formData.longitude = placeDetails.geometry.location.lng;
```

**Database Mapping:**
- `address` → Full formatted address string
- `city` → Extracted city name (for filtering/search)
- `latitude`, `longitude` → For map display

**Fallback:** If Google Places fails, allow manual entry of all fields.

---

### 4. Sales End DateTime - **OPTIONAL FIELD WITH SMART DEFAULT**

**Answer:** Expose as an **optional** field in the form. Default to `start_datetime - 1 hour` if not set.

**Reasoning:** Your use cases are valid. Many organizers need this for:
- Early bird pricing deadlines
- Registration cutoffs for planning
- Venue logistics (final headcount)

**Form Implementation:**
```typescript
// In the form:
<DateTimePicker
  label="Ticket Sales Close (Optional)"
  value={salesEndDatetime}
  placeholder="Defaults to 1 hour before event"
  max={startDatetime}  // Can't be after event starts
  helperText="When should ticket sales stop? Leave empty for default (1 hour before event)."
/>

// On submit:
const salesEnd = formData.salesEndDatetime || 
                 new Date(formData.startDatetime.getTime() - 3600000); // -1 hour
```

**Database:** Use existing `sales_end_datetime` column (already in schema).

---

### 5. Min/Max Tickets Per Purchase - **ADD MIGRATION, HIDE IN FORM FOR MVP**

**Answer:** Add the database columns now, but don't expose in the form yet. Use hardcoded defaults.

**Database Migration:**
```sql
-- Add min/max ticket constraints
ALTER TABLE events 
ADD COLUMN min_tickets_per_purchase integer DEFAULT 1 CHECK (min_tickets_per_purchase >= 1),
ADD COLUMN max_tickets_per_purchase integer DEFAULT 10 CHECK (max_tickets_per_purchase >= min_tickets_per_purchase);

-- Add comments
COMMENT ON COLUMN events.min_tickets_per_purchase IS 'Minimum tickets a user must purchase in one order';
COMMENT ON COLUMN events.max_tickets_per_purchase IS 'Maximum tickets a user can purchase in one order';
```

**MVP Approach:**
- Don't show these fields in the event creation form
- Database defaults: `min = 1`, `max = 10`
- Mobile app enforces these limits during purchase

**Phase 2:**
- Add "Advanced Options" accordion in form
- Expose these fields for organizers who need custom limits

**Why this approach:**
- Database is ready for the feature
- Mobile app can already enforce limits
- Web form stays simple for MVP
- Easy to expose later without migration

---

## 📋 FINAL MVP SCOPE

| Feature | Implementation |
|---------|----------------|
| **Event Types** | Use exact enum: `concert`, `sports`, `workshop`, `food`, `nightlife`, `art` |
| **Platform Fee** | Fetch from `partners.commission_rate`, show in pricing preview |
| **Images** | Cover image (required) + up to 5 additional (optional, JSONB array) |
| **Location** | Google Places API → auto-fill `address`, `city`, `lat`, `lng` |
| **Sales End** | Optional field, defaults to `start_datetime - 1h` |
| **Min/Max Tickets** | DB columns added, hardcoded to 1/10, hidden in form |
| **Status** | `draft` and `active` only (no auto-states for MVP) |

---

## 🗄️ REQUIRED DATABASE MIGRATIONS

I'll create these migrations for you. Run them before deploying the web form:

### Migration 1: Add Multiple Images Support
```sql
-- File: supabase_migrations/add_event_images_support.sql
ALTER TABLE events 
ADD COLUMN IF NOT EXISTS images jsonb DEFAULT '[]'::jsonb;

COMMENT ON COLUMN events.images IS 'Array of additional event image URLs (max 5)';
```

### Migration 2: Add Min/Max Ticket Constraints
```sql
-- File: supabase_migrations/add_ticket_purchase_limits.sql
ALTER TABLE events 
ADD COLUMN IF NOT EXISTS min_tickets_per_purchase integer DEFAULT 1 CHECK (min_tickets_per_purchase >= 1),
ADD COLUMN IF NOT EXISTS max_tickets_per_purchase integer DEFAULT 10 CHECK (max_tickets_per_purchase >= min_tickets_per_purchase);

COMMENT ON COLUMN events.min_tickets_per_purchase IS 'Minimum tickets per purchase';
COMMENT ON COLUMN events.max_tickets_per_purchase IS 'Maximum tickets per purchase';
```

---

## ✅ ACTION ITEMS

**Web Team:**
1. ✅ Update design spec with confirmed decisions above
2. ✅ Implement Google Places API for location (same as mobile)
3. ✅ Add `images` JSONB array upload (max 5)
4. ✅ Fetch `commission_rate` from partner record for pricing preview
5. ✅ Add optional `sales_end_datetime` field with smart default
6. ✅ Wait for migrations to be deployed before testing

**App Team (Me):**
1. ✅ Create and deploy database migrations
2. ✅ Update mobile app to respect `min_tickets_per_purchase` and `max_tickets_per_purchase`
3. ✅ Update mobile app to display multiple images in event modal
4. ✅ Ensure event type enum matches exactly

---

## 📅 REVISED TIMELINE

| Task | Estimate |
|------|----------|
| Database migrations (App Team) | 30 min |
| Update design spec (Web Team) | 30 min |
| Build event creation form | 5 hours |
| Google Places integration | 2 hours |
| Multi-image upload | 2 hours |
| Validation & error handling | 1 hour |
| Testing with real data | 1 hour |
| **Total** | **~1.5 days** |

---

## 🚀 NEXT STEPS

1. I'll create the migrations now
2. You update the design spec
3. We sync on implementation details if needed
4. You build, we test together

Let me know if you need any clarification!

— App Team (Rich)
