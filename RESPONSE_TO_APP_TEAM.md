# Response to App Team - Event Creation Design Feedback

Thanks for the thorough review! Here are our responses to each point:

---

## 1. Event Type Categories ✅ WILL ALIGN

**Your Concern:** Our list doesn't match mobile app enum values.

**Our Response:** 
We'll use your exact enum values to ensure consistency:
- `concert`, `sports`, `workshop`, `food`, `nightlife`, `art`

**Action:** Updated the design spec to use these exact values.

**Reasoning:** Cross-platform consistency is critical. Users should see the same categories whether they create events on web or mobile.

---

## 2. Platform Fee ⚠️ NEEDS CLARIFICATION

**Your Concern:** We mentioned 10%, earlier requirements said 15%.

**Our Response:**
We pulled 10% from the database schema default (`partners.pricing_model = 'standard'` with implied 10% commission). However, we see this is configurable per partner.

**Questions for You:**
1. What is the **default platform fee** for new partners?
2. Should the event creation form **show** the platform fee to organizers, or just assume they know?
3. For the pricing preview ("You'll receive ₱X per ticket"), should we:
   - Fetch the partner's actual custom fee from the database, OR
   - Just show a generic "Platform fees apply" message?

**Our Recommendation:** Show the actual calculated fee so organizers know exactly what they'll earn.

---

## 3. Organizer ID Mapping ✅ CONFIRMED CORRECT

**Your Concern:** Ensure only approved partners can create events.

**Our Response:**
Already handled! The `/organizer` layout checks:
```typescript
// Check if user has an approved partner account
const { data: partner } = await supabase
    .from('partners')
    .select('*')
    .eq('user_id', user.id)
    .single()

if (!partner || partner.status !== 'approved') {
    // Show "Partner Access Required" screen
}
```

The `organizer_id` is auto-filled from the session's `partner.id` on the server side, never exposed to the client.

---

## 4. Missing Fields - city & sales_end_datetime

### **city field** ✅ WILL USE GOOGLE PLACES API

**Your Concern:** Schema has `city` but we only mentioned `address`.

**Our Decision:**
We will integrate **Google Places Autocomplete API** for location input. This provides:
- ✅ Auto-complete as user types address
- ✅ Returns structured data: street, city, province, country
- ✅ Automatically provides latitude/longitude coordinates
- ✅ Validates real addresses (prevents typos/fake locations)
- ✅ Consistent with industry standards (Airbnb, Uber, etc.)

**Implementation:**
- Single search box with Google Places integration
- Auto-fills: `address`, `city`, `latitude`, `longitude`
- User can also manually pin location on map as fallback

**Question for App Team:** Are you using Google Places API on mobile, or a different location service? We should use the same provider for consistency.

### **sales_end_datetime** ✅ REQUIRED FEATURE

**Your Concern:** Schema has `sales_end_datetime` but we didn't include it.

**Our Decision:**
This is a **MUST-HAVE** feature, not optional. Here's why:

**Critical Use Cases:**
1. **Early Bird Sales:** "First 100 tickets sold at ₱500, then ₱750"
   - Organizer sets `sales_end_datetime` to 1 week before event
   - After deadline, they create a new "2nd batch" event listing at higher price
   
2. **Registration Deadlines:** Workshops, conferences, tours
   - "Registration closes 48 hours before event for planning purposes"
   - Prevents last-minute sign-ups when organizer needs time to prepare materials

3. **Venue Logistics:** Food events, seated venues
   - "Need final headcount 24 hours in advance for catering"
   - Hard deadline for ticket sales

4. **Prevented Scenarios Without This:**
   - User buys ticket 5 minutes before event starts
   - Organizer already left for venue, can't check them in
   - Poor user experience (wasted money, angry customer)

**Default Behavior:**
- If not set by organizer: defaults to `start_datetime - 1 hour`
- Organizer can customize to any time before `start_datetime`

**Form Implementation:**
- Optional field, with smart default
- Shows warning if set too close to event time
- Validation: Must be before `start_datetime`

---

## 5. Min/Max Tickets Per Purchase

**Your Concern:** Schema doesn't have these columns yet.

**Our Reasoning:**
We included these because they're common requirements for event organizers:
- **Restaurants/Venues:** "Must book at least 2 seats"
- **Bus Tours:** "Max 6 tickets per family"
- **Fraud Prevention:** Prevent scalpers from buying all tickets

**Benefits:**
- Better inventory management
- Prevents abuse (one person buying entire capacity)
- Common request from real event organizers

**Recommendation:**
If you agree this is useful, we can:
1. Create the migration (simple 2-column addition)
2. Default: `min = 1`, `max = 10` (as proposed)
3. Make these fields **optional** in the form (hidden in "Advanced Options" accordion)

**Question:** Should we add this, or skip for MVP?

---

## 6. Additional Images (Multiple Event Photos)

**Your Concern:** Schema only has `cover_image_url`, not `images` JSONB array.

**Our Reasoning:**
Multiple images significantly improve event discoverability and trust:
- Shows venue interior, stage setup, food, etc.
- Users are 3x more likely to buy tickets when they see 3+ images (industry data)
- Competitors (Eventbrite, Meetup) all support 5-10 images

**Trade-offs:**
- ✅ **MVP (Single Image):** Faster to build, simpler storage
- ✅ **Full Feature (5 Images):** Better UX, higher conversion, but requires:
  - 1 migration to add `images` JSONB column
  - Image upload handling (we're already doing this for cover, so marginal effort)

**Our Recommendation:**
Add `images` JSONB column NOW (easy migration), but make it optional in the form. This way:
- MVP: Organizers just upload 1 cover image
- Phase 2: They can add more images via "Edit Event"
- Database is already ready for multi-image support

**Question:** Should we add the `images` column now (with optional upload), or strictly single-image only?

---

## Proposed Phase 1 (MVP) Simplifications ✅ AGREED

Based on your recommendations, here's what we'll do for MVP:

| Feature | MVP Approach | Phase 2 Enhancement |
|---------|--------------|---------------------|
| **Images** | Single cover image required | Up to 5 additional images |
| **Min/Max Tickets** | Hardcoded (1 min, 10 max) | Exposed as optional fields |
| **Sales End** | Auto-set to `start_datetime - 1h` | Optional "Ticket Sales Close" field |
| **City** | Auto-extract from address | Separate city dropdown |
| **Status** | `draft` and `active` only | Add `sold_out`, `completed` auto-states |

**Rationale:** This gives organizers 80% of functionality with 50% of the complexity. We can iterate based on real user feedback.

---

## Action Items for App Team

**Please confirm:**
1. ✅ **Event Type Enum:** We'll use `concert, sports, workshop, food, nightlife, art`
2. ❓ **Platform Fee:** What's the default percentage? (We'll fetch from partner record)
3. ❓ **City Field:** Should we auto-extract from address, or add separate city field?
4. ❓ **Sales End DateTime:** Auto-default OK, or expose as optional field?
5. ❓ **Min/Max Tickets:** Add migration now (hidden in form), or skip entirely?
6. ❓ **Multiple Images:** Add `images` JSONB column now (optional upload), or single-image only?

**Once confirmed, we'll:**
- Update the design spec
- Implement the web form
- Share final implementation for mobile team reference

---

## Timeline Estimate

| Task | Estimate |
|------|----------|
| Update design spec | 30 min |
| Build event creation form | 4 hours |
| Image upload integration | 2 hours |
| Validation & error handling | 1 hour |
| Testing with real data | 1 hour |
| **Total** | **~1 day** |

Let us know your decisions on the open questions, and we'll proceed!

— Web Team
