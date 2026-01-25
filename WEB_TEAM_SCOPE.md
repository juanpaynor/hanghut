# Web Team - Event Ticketing Scope

## 📋 Message for App Team

Hi App Team,

Thanks for deploying the core backend foundation! We've verified that the Edge Functions (`create-purchase-intent` and `xendit-webhook`) are live and working.

**Web Team will now build the following:**

---

## ✅ 1. Admin Panel (HangHut Staff)

**URL:** `/admin/ticketing/*`

**Features:**
- **Partner Management**
  - Approve/reject partner applications
  - View partner profiles and performance
  - Set custom pricing per partner (override default 10%)
  - Suspend/ban partners
  
- **Event Management**
  - View all events across platform
  - Moderate/approve events (if needed)
  - Event analytics and performance
  - Featured events management
  
- **Accounting & Finance**
  - Transaction history and reconciliation
  - Payout approval queue
  - Revenue analytics and reporting
  - Fraud detection dashboard
  - Export financial reports (CSV, PDF)
  
- **Analytics Dashboard**
  - Platform-wide metrics
  - Revenue tracking
  - Top partners and events
  - Payment success rates

---

## ✅ 2. Organizer Dashboard (Event Partners)

**URL:** `/organizer/*`

**Features:**
- **Event Management**
  - Create new events (web version with more options)
  - Edit/cancel events
  - Duplicate events
  - Bulk operations
  
- **Sales & Analytics**
  - Real-time ticket sales tracking
  - Revenue breakdown
  - Attendee demographics
  - Sales trends and forecasting
  
- **Payout Management**
  - View earnings and pending balance
  - Request payouts
  - Payout history
  - Bank account management
  
- **Advanced Features**
  - Promo codes and discounts
  - Multi-tier tickets (GA, VIP, etc.)
  - Custom event pages
  - Email marketing to attendees

**Design:** Different from admin panel - more friendly, partner-focused UI

---

## ✅ 3. Public Event Pages

**URL:** `/events/[event-id]`

**Features:**
- **SEO-Optimized Event Pages**
  - Server-side rendered for search engines
  - Open Graph meta tags for social sharing
  - Schema.org markup for rich snippets
  
- **Event Details**
  - Full event information
  - Location map
  - Organizer profile
  - Ticket availability
  
- **Social Sharing**
  - Share to Facebook, Twitter, Instagram
  - Deep links to mobile app
  - QR code for easy sharing
  
- **Ticket Purchase**
  - Redirect to mobile app (preferred)
  - Or web checkout flow (fallback)

---

## 🔄 Division of Responsibilities

### Mobile Team (You):
- ✅ Partner application flow (in-app)
- ✅ Basic partner dashboard (in-app)
- ✅ Event creation (mobile-first)
- ✅ Event browsing on map
- ✅ Ticket purchase flow
- ✅ QR code viewing/scanning
- ✅ Push notifications

### Web Team (Us):
- ✅ Admin panel (full platform management)
- ✅ Advanced organizer dashboard (desktop features)
- ✅ Public event pages (SEO/sharing)
- ✅ Accounting and financial reporting
- ✅ Analytics and business intelligence

---

## 📅 Timeline

**Week 1-2:** Admin Panel Foundation
- Partner approval queue
- Event management
- Basic accounting dashboard

**Week 3:** Organizer Dashboard
- Event creation (web)
- Sales analytics
- Payout requests

**Week 4:** Public Pages & Polish
- SEO-optimized event pages
- Social sharing
- Testing and refinement

---

## 🤝 Coordination Needed

**From App Team:**
1. Confirm partner application flow is complete in mobile app
2. Share any API endpoints we should be aware of
3. Coordinate on deep linking strategy (web → app)

**From Web Team:**
1. We'll build admin/organizer portals
2. We'll handle public event pages for SEO
3. We'll provide analytics and reporting tools

---

Let us know if you have any questions or need clarification on the scope!

**Web Team**
