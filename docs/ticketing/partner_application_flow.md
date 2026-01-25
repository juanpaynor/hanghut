# HangHut Partner Application Flow - Design Document

## 🎯 Design Goals

**Beat HelixPay on:**
- ⚡ **Speed**: 1 hour vs 1-3 days
- 📱 **Mobile-first**: Apply via app, not just web
- 🚀 **Accessibility**: Lower barrier for small organizers
- 🔄 **Progressive**: Start small, upgrade later

---

## 🏗️ Architecture: 2-Tier System

```
┌──────────────────────────────────────────────────┐
│              TIER 1: QUICK START                 │
│  Perfect for: First-time organizers, small events│
├──────────────────────────────────────────────────┤
│ Approval: Auto (1hr) | Fee: 15% | Limit: ₱20k   │
└──────────────────────────────────────────────────┘
                      ↓
              User runs events
              Builds reputation
                      ↓
┌──────────────────────────────────────────────────┐
│            TIER 2: VERIFIED PARTNER              │
│  Perfect for: Recurring organizers, larger events│
├──────────────────────────────────────────────────┤
│ Approval: Manual (1-2 days) | Fee: 10% | Unlimited│
└──────────────────────────────────────────────────┘
```

---

## 📱 Application Flow: Tier 1 (Quick Start)

### Screen 1: Welcome
```
┌─────────────────────────────────────────┐
│  🎟️ Become an Event Partner             │
├─────────────────────────────────────────┤
│                                         │
│  Start hosting events on HangHut!       │
│                                         │
│  ✓ Create your first event in minutes  │
│  ✓ Accept payments via GCash, cards    │
│  ✓ Track sales & check-ins             │
│                                         │
│  Quick Start (Approved in 1 hour)      │
│  → Up to ₱20k/month                     │
│  → 15% platform fee                     │
│                                         │
│  ┌────────────────────────────┐         │
│  │   Get Started              │         │
│  └────────────────────────────┘         │
│                                         │
│  Already verified? [Upgrade to Tier 2] │
└─────────────────────────────────────────┘
```

### Screen 2: Personal Info
```
┌─────────────────────────────────────────┐
│  ← Step 1 of 4: Personal Information   │
├─────────────────────────────────────────┤
│                                         │
│  Full Name *                            │
│  ┌───────────────────────────────────┐  │
│  │ Juan Dela Cruz                    │  │
│  └───────────────────────────────────┘  │
│                                         │
│  Email *                                │
│  ┌───────────────────────────────────┐  │
│  │ juan@example.com         [Verify] │  │
│  └───────────────────────────────────┘  │
│  ✓ Verified                             │
│                                         │
│  Phone Number *                         │
│  ┌───────────────────────────────────┐  │
│  │ +63 917 123 4567         [Verify] │  │
│  └───────────────────────────────────┘  │
│  ✓ Verified via SMS                     │
│                                         │
│  ┌────────────────────────────┐         │
│  │   Next                     │         │
│  └────────────────────────────┘         │
└─────────────────────────────────────────┘
```

**Validation:**
- Email: OTP sent, 6-digit code, 5 min expiry
- Phone: SMS OTP, 6-digit code, 5 min expiry
- Both must be verified to proceed

### Screen 3: Business Details
```
┌─────────────────────────────────────────┐
│  ← Step 2 of 4: Business Info          │
├─────────────────────────────────────────┤
│                                         │
│  Business/Brand Name *                  │
│  ┌───────────────────────────────────┐  │
│  │ SoundWave Events                  │  │
│  └───────────────────────────────────┘  │
│  This appears on your event listings    │
│                                         │
│  Business Type *                        │
│  ○ Individual (Freelancer)              │
│  ● Sole Proprietorship                  │
│  ○ Corporation                          │
│  ○ Partnership                          │
│                                         │
│  Typical Event Type *                   │
│  ┌───────────────────────────────────┐  │
│  │ Select...                     ▼   │  │
│  └───────────────────────────────────┘  │
│  • Concerts & Music                     │
│  • Workshops & Classes                  │
│  • Conferences & Seminars               │
│  • Sports & Fitness                     │
│  • Social & Networking                  │
│  • Other                                │
│                                         │
│  Website/Social Media (Optional)        │
│  ┌───────────────────────────────────┐  │
│  │ facebook.com/soundwave            │  │
│  └───────────────────────────────────┘  │
│                                         │
│  ┌────────────────────────────┐         │
│  │   Next                     │         │
│  └────────────────────────────┘         │
└─────────────────────────────────────────┘
```

### Screen 4: ID Verification
```
┌─────────────────────────────────────────┐
│  ← Step 3 of 4: ID Verification        │
├─────────────────────────────────────────┤
│                                         │
│  Upload 1 Valid Government ID           │
│                                         │
│  Accepted IDs:                          │
│  • Driver's License                     │
│  • Passport                             │
│  • Postal ID                            │
│  • Voter's ID                           │
│  • PhilHealth ID                        │
│  • SSS/GSIS ID                          │
│                                         │
│  ┌─────────────────────────────────┐    │
│  │                                 │    │
│  │      📷 Take Photo              │    │
│  │         or                      │    │
│  │      📁 Upload from Gallery     │    │
│  │                                 │    │
│  └─────────────────────────────────┘    │
│                                         │
│  [Preview: Driver's License front]      │
│  ✓ Front uploaded                       │
│                                         │
│  ┌─────────────────────────────────┐    │
│  │  Add back of ID (if applicable) │    │
│  └─────────────────────────────────┘    │
│                                         │
│  [Preview: Driver's License back]       │
│  ✓ Back uploaded                        │
│                                         │
│  ┌────────────────────────────┐         │
│  │   Next                     │         │
│  └────────────────────────────┘         │
└─────────────────────────────────────────┘
```

**Features:**
- Native camera integration
- Auto-crop ID card
- Basic OCR to extract name (verify matches input)
- Image quality check (readable, not blurry)

### Screen 5: Selfie Verification (Liveness Check)
```
┌─────────────────────────────────────────┐
│  ← Step 3.5 of 4: Verify It's You      │
├─────────────────────────────────────────┤
│                                         │
│  Take a selfie holding your ID          │
│  This helps prevent fraud               │
│                                         │
│  ┌─────────────────────────────────┐    │
│  │                                 │    │
│  │         📷 Camera View          │    │
│  │                                 │    │
│  │    [ Oval face outline ]        │    │
│  │                                 │    │
│  │  Position your face & ID        │    │
│  │  within the guide               │    │
│  │                                 │    │
│  └─────────────────────────────────┘    │
│                                         │
│  Tips:                                  │
│  • Hold ID next to your face            │
│  • Make sure text is readable           │
│  • Good lighting                        │
│  • Remove sunglasses/mask               │
│                                         │
│  ┌────────────────────────────┐         │
│  │   Take Photo               │         │
│  └────────────────────────────┘         │
└─────────────────────────────────────────┘
```

**Auto-checks:**
- Face detected ✓
- ID card visible ✓
- Not a screenshot ✓
- Adequate lighting ✓

### Screen 6: Review & Submit
```
┌─────────────────────────────────────────┐
│  ← Step 4 of 4: Review & Submit        │
├─────────────────────────────────────────┤
│                                         │
│  📋 Application Summary                 │
│                                         │
│  Personal Info:                         │
│  • Juan Dela Cruz                       │
│  • juan@example.com ✓                   │
│  • +63 917 123 4567 ✓                   │
│                                         │
│  Business Info:                         │
│  • SoundWave Events                     │
│  • Sole Proprietorship                  │
│  • Concerts & Music                     │
│                                         │
│  Verification:                          │
│  • Driver's License uploaded ✓          │
│  • Selfie with ID verified ✓            │
│                                         │
│  ── Terms & Conditions ──               │
│                                         │
│  ☐ I agree to HangHut's Partner Terms   │
│    [View Terms]                         │
│                                         │
│  ☐ I agree to 15% platform fee for      │
│    Tier 1 (Quick Start) access          │
│                                         │
│  ☐ I understand the ₱20,000/month       │
│    sales limit for Tier 1               │
│                                         │
│  ┌────────────────────────────┐         │
│  │   Submit Application       │         │
│  └────────────────────────────┘         │
│                                         │
│  [Edit] any section above               │
└─────────────────────────────────────────┘
```

### Screen 7: Processing
```
┌─────────────────────────────────────────┐
│  🎉 Application Submitted!              │
├─────────────────────────────────────────┤
│                                         │
│  ⏳ Review in Progress                  │
│                                         │
│  Your application is being reviewed     │
│  automatically. This usually takes      │
│  less than 1 hour.                      │
│                                         │
│  ┌─────────────────────────────────┐    │
│  │ ⚙️  Verifying email           ✓ │    │
│  │ ⚙️  Verifying phone           ✓ │    │
│  │ ⚙️  Checking ID validity      ⏳│    │
│  │ ⚙️  Processing application    ⏳│    │
│  └─────────────────────────────────┘    │
│                                         │
│  We'll notify you when approved!        │
│                                         │
│  ✉️  Email: juan@example.com            │
│  📱 SMS: +63 917 123 4567               │
│  🔔 Push notification                   │
│                                         │
│  ┌────────────────────────────┐         │
│  │   Back to Home             │         │
│  └────────────────────────────┘         │
│                                         │
│  [Track Application Status]             │
└─────────────────────────────────────────┘
```

### Screen 8: Approved! (1 hour later)
```
┌─────────────────────────────────────────┐
│  🎊 Welcome to HangHut Partners!        │
├─────────────────────────────────────────┤
│                                         │
│  ✓ Application Approved                 │
│  Tier 1: Quick Start Partner            │
│                                         │
│  Your Benefits:                         │
│  • Create up to 2 events/month          │
│  • Sell up to ₱20,000 total             │
│  • 15% platform fee                     │
│  • Payment via GCash, cards, banks      │
│                                         │
│  ⚠️ Before you can receive payouts:     │
│  → Add your bank account details        │
│                                         │
│  ┌────────────────────────────┐         │
│  │   Add Bank Account         │         │
│  └────────────────────────────┘         │
│                                         │
│  ┌────────────────────────────┐         │
│  │   Skip for Now             │         │
│  └────────────────────────────┘         │
│                                         │
│  ┌────────────────────────────┐         │
│  │   Create First Event  →    │         │
│  └────────────────────────────┘         │
│                                         │
│  Want higher limits?                    │
│  [Upgrade to Tier 2] for unlimited      │
└─────────────────────────────────────────┘
```

---

## 🏦 Bank Account Setup (Optional Initially)

### Can Be Done:
1. **Immediately** after approval (recommended)
2. **Before first payout** only (minimum requirement)
3. **Anytime** in partner dashboard

```
┌─────────────────────────────────────────┐
│  💳 Add Bank Account                    │
├─────────────────────────────────────────┤
│                                         │
│  Bank Name *                            │
│  ┌───────────────────────────────────┐  │
│  │ Bank of the Philippine Islands ▼  │  │
│  └───────────────────────────────────┘  │
│                                         │
│  Account Number *                       │
│  ┌───────────────────────────────────┐  │
│  │ 1234 5678 9012 3456               │  │
│  └───────────────────────────────────┘  │
│                                         │
│  Account Name *                         │
│  ┌───────────────────────────────────┐  │
│  │ JUAN DELA CRUZ                    │  │
│  └───────────────────────────────────┘  │
│  Must match your registered name        │
│                                         │
│  ℹ️  This is where we'll send your      │
│     event earnings after each payout    │
│                                         │
│  ┌────────────────────────────┐         │
│  │   Save & Continue          │         │
│  └────────────────────────────┘         │
└─────────────────────────────────────────┘
```

---

## 🚀 Tier 2 Upgrade Flow

### When to Show Upgrade Prompt:

**Auto-suggest when:**
- User hits ₱15k sales (75% of limit)
- User creates 2+ events successfully
- User requests 3rd event in a month

### Upgrade Screen:
```
┌─────────────────────────────────────────┐
│  ⬆️ Upgrade to Verified Partner         │
├─────────────────────────────────────────┤
│                                         │
│  You're ready for the next level!       │
│                                         │
│  Tier 1 vs Tier 2                       │
│  ┌─────────────────────────────────┐    │
│  │        Current  →  Verified     │    │
│  ├─────────────────────────────────┤    │
│  │ Events:   2/mo  →  Unlimited    │    │
│  │ Sales:    ₱20k  →  Unlimited    │    │
│  │ Fee:      15%   →  10%          │    │
│  │ Badge:    None  →  ✓ Verified   │    │
│  │ Support:  Email →  Priority     │    │
│  └─────────────────────────────────┘    │
│                                         │
│  Additional Requirements:               │
│  • Business registration (DTI/SEC)      │
│  • Proof of address                     │
│  • 2-3 day manual review                │
│                                         │
│  ┌────────────────────────────┐         │
│  │   Start Upgrade Process    │         │
│  └────────────────────────────┘         │
│                                         │
│  [Maybe Later]                          │
└─────────────────────────────────────────┘
```

### Tier 2 Application (Additional Steps):
```
Step 1: Business Registration
  → Upload DTI/SEC certificate
  → Must show business name matches

Step 2: Proof of Address
  → Utility bill (3 months old)
  → Or barangay clearance
  → Or lease contract

Step 3: Review & Submit
  → Manual review by admin (1-2 days)
  → Email notification when approved
```

---

## 🤖 Auto-Approval Logic (Tier 1)

### Automated Checks:

```python
def auto_approve_tier_1(application):
    checks = {
        'email_verified': application.email_verified,
        'phone_verified': application.phone_verified,
        'id_uploaded': application.id_front_url is not None,
        'selfie_uploaded': application.selfie_url is not None,
        'terms_accepted': application.terms_accepted,
        'not_blacklisted': not is_blacklisted(application.email, application.phone),
        'id_readable': ocr_check(application.id_front_url),
        'face_match': basic_face_match(application.selfie_url, application.id_front_url)
    }
    
    if all(checks.values()):
        return 'APPROVED'
    else:
        return 'PENDING_MANUAL_REVIEW'
```

### Manual Review Triggers:

**Send to human review if:**
- ID OCR fails (blurry, damaged)
- Face match confidence < 70%
- Email/phone on watchlist
- Suspicious patterns (mass applications)
- User requests manual review

---

## 📊 Partner Dashboard (Post-Approval)

### Navigation:
```
┌─────────────────────────────────────────┐
│  SoundWave Events  ✓ Verified           │
│  Tier 1 | 15% fee | ₱5,320 / ₱20,000    │
├─────────────────────────────────────────┤
│                                         │
│  [Dashboard] [Events] [Payouts] [Settings]
│                                         │
│  Quick Stats:                           │
│  • Active Events: 1                     │
│  • Total Tickets Sold: 24               │
│  • This Month Sales: ₱5,320             │
│  • Pending Payout: ₱4,522               │
│                                         │
│  ┌────────────────────────────┐         │
│  │  + Create New Event        │         │
│  └────────────────────────────┘         │
│                                         │
│  Your Events:                           │
│  ─────────────────────────────          │
│  🎵 Summer Music Fest                   │
│  Jun 15 • 24/50 tickets sold            │
│  ₱12,000 revenue                        │
│  [Edit] [View] [Analytics]              │
│  ─────────────────────────────          │
│                                         │
│  ⬆️ [Upgrade to Tier 2] for unlimited   │
└─────────────────────────────────────────┘
```

---

## 🔔 Notifications

### Email Notifications:
1. **Application submitted** - Immediate
2. **Application approved** - Within 1 hour
3. **Bank account reminder** - If not added after 7 days
4. **Sales approaching limit** - At 75%, 90%, 100%
5. **Payout processed** - When money sent

### Push Notifications:
1. **Approved!** - Partner status granted
2. **Ticket sold** - Real-time sales alert
3. **Payout ready** - Can request withdrawal
4. **Event starting soon** - 24h, 1h before

### SMS Notifications:
1. **Verification code** - During signup
2. **Approval** - You're now a partner!
3. **High-value sale** - Event sold out

---

## 🛡️ Fraud Prevention

### Red Flags:
- Same phone/email for multiple accounts
- Stock/fake ID photos (reverse image search)
- Fake selfies (screenshot detection)
- VPN/proxy usage during signup
- Mass applications from same IP
- Suspiciously similar business names

### Mitigation:
- Email domain validation (reject temp emails)
- Phone number validation (active SIM check)
- ID OCR + manual spot checks
- Face liveness detection
- Rate limiting (max 3 applications/IP/day)
- Watchlist of known scammers

---

## 📱 Mobile vs Web Implementation

### Mobile App (Primary):
✅ Full application flow  
✅ Camera integration for ID/selfie  
✅ Push notifications  
✅ Real-time approval status  
✅ Partner dashboard  
✅ Create events  

### Web Dashboard (Secondary):
✅ View application status  
✅ Partner dashboard (full featured)  
✅ Analytics & reports  
✅ Payout management  
🟡 Can apply (but optimized for desktop)  

---

## ⏱️ Timeline Comparison

| Step | HelixPay | HangHut Tier 1 | HangHut Tier 2 |
|------|----------|----------------|----------------|
| **Fill form** | 15 min | 5 min | 10 min |
| **Upload docs** | 10 min | 2 min (camera) | 5 min (scan) |
| **Review time** | 1-3 days | <1 hour (auto) | 1-2 days |
| **Total** | **1-3 days** | **1 hour** ⚡ | **1-2 days** |

---

## 🎯 Success Metrics

**Track:**
- Time to approval (target: <30 min avg)
- Application completion rate (target: >80%)
- Auto-approval rate (target: >90%)
- Tier 1 → Tier 2 upgrade rate (target: >30%)
- Partner satisfaction (NPS target: >50)

---

**Ready to build!** This flow is designed to be:
- ⚡ **Faster** than HelixPay
- 📱 **Mobile-first** unlike competitors
- 🚀 **Low-friction** for small organizers
- 🔐 **Secure** with automated fraud checks
- 📈 **Scalable** with clear tier progression
