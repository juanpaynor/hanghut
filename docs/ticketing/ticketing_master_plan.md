# HangHut Event Ticketing System - Master Plan

## 🎯 Vision

**Add ticketed events to HangHut's existing social hangout platform, differentiated by map-based discovery and community features.**

---

## 🏢 Business Model

### Partnership Model
- Event organizers **apply to partner** with HangHut (not self-serve)
- Application review process (quality control + legal protection)
- Verified partner badges

### Pricing Strategy
- **Default:** 10% platform fee
- **Flexible:** Admin can set custom rates per partner
  - High volume: 5-7%
  - New partners: 0% promotional (first 3 events)
  - Non-profit: 3%
  - Risk/category-based adjustments
- **Payment Gateway:** Xendit (recommended) or Maya Business
  - Supports split payments
  - Escrow capability
  - Auto-disbursements to organizers

### Revenue Split Example
```
Ticket: ₱500
HangHut (10%): ₱50
Xendit (2.9% + ₱15): ₱29.50
Organizer: ₱420.50 (84%)
```

---

## 🎨 User Experience

### Discovery (Mobile App)
**Map-Based (Your Differentiator):**
- Events shown as 🎟️ markers on existing map
- Different visual style vs tables (🍕)
- Filter toggles: [All] [Hangouts] [Events]
- Geofencing notifications for nearby events

**Event Modal:**
```
Summer Music Fest 🎟️
─────────────────────
📍 BGC Amphitheater
📅 June 15 • 7:00 PM
🎫 ₱500 per ticket
👥 452/500 tickets sold
⭐ By: SoundWave Events ✓

[Buy Tickets] [Share]
```

### Purchase Flow
1. User selects event on map
2. Chooses ticket quantity
3. HangHut creates Purchase Intent
4. Redirects to Xendit payment
5. On success → Issues tickets
6. Tickets stored in app (QR codes)

### Social Features (Competitive Advantage)
- "12 friends going" social proof
- Event-specific group chats
- Friend invites
- Post-event photo sharing
- Activity feed integration

---

## 🛠️ Technical Architecture

### Database Schema (Core Tables)
```sql
-- Events
events (
  id, organizer_id, title, location_lat, location_lng,
  datetime, capacity, tickets_sold, ticket_price,
  status, event_type
)

-- Partners (Organizers)
partners (
  id, name, pricing_model, custom_percentage,
  custom_per_ticket, promotional_until, verified
)

-- Purchase Flow
purchase_intents (
  id, user_id, event_id, quantity, status, expires_at
)

tickets (
  id, intent_id, event_id, user_id, qr_code,
  checked_in_at, status
)

-- Payouts
payouts (
  id, event_id, organizer_id, amount, status, paid_at
)
```

### Payment Integration
- **Webhook handler** (server-side for security)
- Idempotency protection
- Capacity locking during purchase
- Automated refund flow

### Map Integration
- **Two layer approach:**
  - Existing: `tables-cluster-source` (casual hangouts)
  - New: `events-cluster-source` (ticketed events)
- Different icons/colors
- Independent clustering
- Shared tap handlers

---

## 🆚 Competitive Positioning

### vs HelixPay (Main Competitor)

| Aspect | HelixPay | HangHut |
|--------|----------|---------|
| **Target** | Large events (500+ people) | Community events (<200 people) |
| **Strength** | Enterprise features, scale | Social discovery, mobile-native |
| **Pricing** | ₱20/ticket (~4%) | 10% (flexible) |
| **Discovery** | List/calendar view | **Map-based** ✨ |
| **Social** | None | **Friend network** ✨ |
| **Platform** | Web-first | **Mobile-first** ✨ |

### Your Moat
1. **Map discovery** (unique in Philippines)
2. **Social features** (HelixPay won't build)
3. **Hybrid casual + paid** (ecosystem lock-in)
4. **Mobile-native** (faster, better UX)

### Market Strategy
- **Don't compete** on large-scale events (500+)
- **Don't build** custom websites or seat selection
- **Do focus** on community, social, mobile

---

## 👥 Team Coordination

### Mobile Team (You)
**Responsibilities:**
- Event browsing on map
- Ticket purchase flow
- My Tickets screen (QR viewing)
- QR scanner for organizers
- Push notifications
- Geofencing

### Web Team
**Responsibilities:**
- Organizer dashboard (event creation, analytics)
- Admin panel (partner approval, pricing, payouts)
- Public event pages (SEO, sharing)
- Payment webhook handler (critical!)
- Payout processing

### Shared (Supabase Backend)
- Database schema
- RPC functions (purchase, validation)
- Auth (same user accounts)
- Storage (event images)
- Realtime (capacity updates)

---

## 📅 Implementation Roadmap

### Phase 1: MVP Foundation (6-8 weeks)

#### **Week 1-2: Planning & Setup** ✅ (CURRENT)
**Mobile Team:**
- [x] Finalize database schema ✅
- [x] Xendit API key setup ✅
- [x] Review HelixPay competitor analysis ✅
- [x] Design partner application flow ✅
- [ ] API contract documentation
- [ ] UI mockups for key screens

**Web Team:**
- [ ] Review database schema
- [ ] Set up Supabase Edge Functions
- [ ] Plan admin panel structure
- [ ] Design organizer dashboard wireframes

**Both Teams:**
- [ ] Kickoff meeting (align on responsibilities)
- [ ] Deploy database schema to staging
- [ ] Set up shared test data

---

#### **Week 3-4: Backend Foundation** (Web Team Leads)

**Web Team (Critical Path):**
- [ ] **Partner Application Backend**
  - [ ] Partner application form (web)
  - [ ] Auto-approval logic (RPC function)
  - [ ] Email/SMS verification integration
  - [ ] Admin review panel (for flagged applications)
  - [ ] Partner status management
  
- [ ] **Event Management Backend**
  - [ ] Event creation form (web dashboard)
  - [ ] Event CRUD RPC functions
  - [ ] Image upload to Supabase Storage
  - [ ] Event approval workflow (optional)

- [ ] **Payment Infrastructure (CRITICAL)**
  - [ ] Xendit webhook endpoint (Edge Function)
  - [ ] Purchase intent creation endpoint
  - [ ] Ticket issuance logic
  - [ ] Webhook signature verification

**Mobile Team (Parallel Work):**
- [ ] **Partner Application UI (Tier 1)**
  - [ ] Welcome screen
  - [ ] Personal info + email/phone OTP
  - [ ] Business details form
  - [ ] ID photo upload (camera integration)
  - [ ] Selfie verification screen
  - [ ] Review & submit screen
  - [ ] Approval status tracking
  
- [ ] **Mock Data Setup**
  - [ ] Create mock events for UI testing
  - [ ] Mock API responses
  - [ ] Test data generators

---

#### **Week 5-6: Mobile Integration** (Mobile Team Leads)

**Mobile Team (Your Main Work):**
- [ ] **Event Discovery**
  - [ ] Add events layer to map (🎟️ markers)
  - [ ] Fetch events in viewport (integrate RPC)
  - [ ] Filter toggles: [All] [Tables] [Events]
  - [ ] Event detail modal
  - [ ] Display ticket price, capacity, organizer

- [ ] **Purchase Flow**
  - [ ] Quantity selector UI
  - [ ] Call create-purchase-intent API
  - [ ] Open Xendit payment URL (WebView/browser)
  - [ ] Handle payment callbacks
  - [ ] Loading states & error handling

- [ ] **My Tickets**
  - [ ] Fetch user's tickets
  - [ ] Display ticket list with event info
  - [ ] Individual ticket view (full-screen QR)
  - [ ] Ticket status indicators

- [ ] **Partner Dashboard (Mobile)**
  - [ ] Partner stats overview
  - [ ] Event management basics
  - [ ] Sales tracking
  - [ ] Link to web dashboard for advanced features

**Web Team (Support):**
- [ ] Finalize APIs for mobile consumption
- [ ] API documentation
- [ ] Test webhook with Xendit sandbox
- [ ] Basic organizer dashboard v1

---

#### **Week 7-8: Testing & Polish**

**Both Teams:**
- [ ] **End-to-End Testing**
  - [ ] Partner application → approval
  - [ ] Event creation → published on map
  - [ ] Browse events → purchase → tickets appear
  - [ ] QR scanner implementation
  - [ ] Check-in flow testing

- [ ] **Edge Cases**
  - [ ] Payment failure handling
  - [ ] Event sold out during purchase
  - [ ] Expired reservation cleanup
  - [ ] Network errors & retries

- [ ] **Pilot Program**
  - [ ] Recruit 3-5 friendly partners
  - [ ] Small test events (20-50 people)
  - [ ] Monitor real transactions
  - [ ] Collect feedback
  - [ ] Bug fixes

**Deliverables:**
- ✅ Partners can apply & get approved
- ✅ Partners can create events
- ✅ Events appear on mobile map
- ✅ Users can buy tickets
- ✅ Tickets have QR codes
- ✅ Basic check-in works

---

### Phase 2: Social Integration (2-3 weeks)

**Mobile Team:**
- [ ] "Friends going" feature
  - [ ] Show friend count on event modal
  - [ ] List of friends attending
  - [ ] Invite friends to event

- [ ] Event group chats
  - [ ] Auto-create chat for attendees
  - [ ] Event-specific channels
  - [ ] Post-event photo sharing

- [ ] Activity feed integration
  - [ ] "John bought tickets to X event"
  - [ ] "Alice is going to Y concert"

- [ ] Shareable links
  - [ ] Deep links to events
  - [ ] Social media previews
  - [ ] Referral tracking

**Web Team:**
- [ ] Social analytics for organizers
  - [ ] Referral sources
  - [ ] Viral coefficient
  - [ ] Friend network effects

---

### Phase 3: Advanced Features (2-3 weeks)

**Mobile Team:**
- [ ] **QR Scanner Enhancements**
  - [ ] Offline mode support
  - [ ] Batch scanning
  - [ ] Real-time validation
  - [ ] Staff access controls

**Web Team:**
- [ ] **Partner Features**
  - [ ] Tier 2 upgrade flow
  - [ ] Custom pricing UI (admin)
  - [ ] Refund processing
  - [ ] Automated payouts (Xendit disbursement)
  - [ ] Advanced analytics dashboard

- [ ] **Admin Tools**
  - [ ] Partner performance monitoring
  - [ ] Fraud detection dashboard
  - [ ] Payout approval queue
  - [ ] Event moderation tools

**Both Teams:**
- [ ] Multi-tier tickets (GA, VIP, etc.)
- [ ] Promo codes & discounts
- [ ] Waitlist for sold-out events
- [ ] Event reminders & notifications

---

### Phase 4: Scale & Optimize (Ongoing)

- [ ] PostGIS for geospatial queries (if needed)
- [ ] CDN for event images
- [ ] Caching strategy (Redis)
- [ ] Load testing (1000+ concurrent purchases)
- [ ] Geographic expansion (Cebu, Davao)
- [ ] Performance monitoring & alerts

---

## 🎫 Feature Scope

### MVP (Must Have)
✅ Event creation (web)  
✅ Map-based browsing (mobile)  
✅ Ticket purchase via Xendit  
✅ QR code generation  
✅ Basic scanner  
✅ Partner approval system  
✅ Manual payout requests  

### Phase 2 (Should Have)
✅ Social features (friends, chat)  
✅ Automated payouts  
✅ Refunds  
✅ Custom pricing per partner  
✅ Analytics  

### Phase 3+ (Nice to Have)
🟡 Seat selection  
🟡 Custom event websites  
🟡 Merchandise sales  
🟡 Ticket transfers  
🟡 Waitlist for sold-out  

### Out of Scope (HelixPay Territory)
❌ On-site payment terminals  
❌ On-site internet  
❌ Large venue management (1000+)  
❌ Complex seat maps  

---

## 🎨 Design Principles

1. **Mobile-first** - primary experience is in-app
2. **Social-first** - emphasize friend connections
3. **Map-centric** - discovery through location
4. **Simple** - don't overcomplicate like HelixPay
5. **Community** - feel accessible, not corporate

---

## 📊 Success Metrics

### Short-term (6 months)
- 100+ events posted
- 50% have <100 attendees (proving niche)
- 30% repeat organizers
- 4.5+ star rating

### Medium-term (12 months)
- 500+ events posted
- 40% tickets sold via social referrals
- 10,000+ active users
- Break-even on operations

### Long-term (24 months)
- Default for community events in Metro Manila
- Geographic expansion (Cebu, Davao)
- Profitable unit economics

---

## 🚨 Critical Decisions Made

✅ **Payment Provider:** Xendit (over Maya)  
✅ **Pricing:** 10% default, admin-flexible  
✅ **Partnership Model:** Application-based (not self-serve)  
✅ **Map Display:** Separate layer from tables  
✅ **Target Market:** <200 person events  
✅ **Team Split:** Web does admin/organizer, mobile does discovery/purchase  

---

## 🔐 Legal/Compliance

- HangHut is **facilitator only**, not event organizer
- Partner agreement required (liability protection)
- Clear refund policy needed
- Data privacy compliance (GDPR/PH DPA)
- Payment processing: Xendit handles PCI DSS

---

## 🎬 Next Steps (This Week)

1. **Sync with web team** - share this plan
2. **Database schema** - finalize together
3. **API contracts** - document endpoints
4. **Design mockups** - mobile screens
5. **Xendit setup** - create sandbox account

---

## 📝 Open Questions

- [ ] Refund policy details (timeframe, process)
- [ ] Payout schedule (immediate, weekly, post-event?)
- [ ] Event approval process (auto vs manual)
- [ ] Minimum ticket price (free events allowed?)
- [ ] International payments (tourists buying tickets?)

---

**Ready to build!** Focus on MVP, iterate based on user feedback, avoid feature creep.
