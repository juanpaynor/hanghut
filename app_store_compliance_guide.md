# App Store Distribution Compliance Guide

## 🎯 Current Compliance Status

### ✅ What We Have (Compliant)
- **Age Restriction (18+)**: Strictly enforced in registration
- **User Reporting System**: Built-in moderation tools
- **Privacy-First Design**: No location tracking without permission
- **Secure Authentication**: Supabase Auth with PKCE flow
- **Terms & Privacy Policy**: Links in signup flow

### ⚠️ What We Need (Before Submission)

#### **Critical Blockers**
1. **Privacy Policy & Terms of Service** - Currently placeholder URLs
2. **App Store Assets** - Screenshots, App Preview videos, Icons
3. **Content Moderation** - Admin dashboard must be functional
4. **Location Permissions** - Need proper Info.plist descriptions

---

## 📱 Distribution Phases Explained

### Phase 1: Internal Testing (NOW)
**What it is:** Testing on your own devices via Xcode/Android Studio.
- ✅ **Status:** You're here now
- **Devices:** Unlimited for iOS (with dev account), any Android device
- **Distribution:** Direct cable connection or Firebase App Distribution

### Phase 2: Closed Beta (TestFlight / Internal Testing)
**What it is:** Invite-only testing with real users (up to 10,000 on iOS, unlimited on Android).
- **iOS (TestFlight):**
  - Requires Apple Developer Account ($99/year)
  - Upload to App Store Connect
  - Invite testers via email
  - No App Review required for internal testing
- **Android (Internal Testing):**
  - Requires Google Play Console account ($25 one-time)
  - Upload to Play Console
  - Add testers via email or Google Group
  - No review required

### Phase 3: Public Beta (Optional)
**What it is:** Open to anyone with the link.
- **iOS:** TestFlight Public Link (still requires Apple review)
- **Android:** Open Testing track (requires Play Store review)

### Phase 4: Production Release
**What it is:** Live on App Store / Play Store for everyone.
- Full app review process (both platforms)
- Requires all compliance items below

---

## 🍎 Apple App Store Requirements

### Account Setup
- [ ] **Apple Developer Account** ($99/year) - [developer.apple.com](https://developer.apple.com)
- [ ] **App Store Connect** access configured
- [ ] **Bundle ID** registered (e.g., `com.hanghut.bitemates`)

### Technical Requirements
- [ ] **Minimum iOS Version:** Set in `ios/Podfile` (currently iOS 13+)
- [ ] **App Icons:** All required sizes (1024x1024 for store, plus device sizes)
- [ ] **Launch Screen:** Configured (you have splash screen ✅)
- [ ] **Info.plist Permissions:**
  ```xml
  <key>NSLocationWhenInUseUsageDescription</key>
  <string>We need your location to show nearby dining tables and events.</string>
  
  <key>NSPhotoLibraryUsageDescription</key>
  <string>We need access to your photos to upload profile pictures.</string>
  
  <key>NSCameraUsageDescription</key>
  <string>We need camera access to take profile photos.</string>
  ```

### Content & Policy
- [ ] **Age Rating:** 17+ (Social Networking + User-Generated Content)
- [ ] **Privacy Policy URL:** Must be live and accessible
- [ ] **Terms of Service URL:** Must be live and accessible
- [ ] **App Review Information:**
  - Demo account credentials for reviewers
  - Explanation of 18+ enforcement
  - Moderation system documentation

### App Review Guidelines Compliance
**Key Areas for Social Apps:**
- ✅ **4.3 Spam:** Your app is unique (location-based dining meetups)
- ⚠️ **5.1.1 Data Collection:** Privacy Policy required
- ✅ **5.1.2 Data Use:** You're not selling user data
- ⚠️ **5.2.3 User-Generated Content:** Reporting system required (✅ Built)
- ✅ **5.3 Gaming/Gambling:** Not applicable

---

## 🤖 Google Play Store Requirements

### Account Setup
- [ ] **Google Play Console** ($25 one-time) - [play.google.com/console](https://play.google.com/console)
- [ ] **App Signing** configured (Google manages keys)
- [ ] **Application ID** set (e.g., `com.hanghut.bitemates`)

### Technical Requirements
- [ ] **Minimum SDK:** Set in `android/app/build.gradle` (currently API 21+)
- [ ] **Target SDK:** Must be latest or latest-1 (currently 34)
- [ ] **App Icon:** Adaptive icon + legacy icon
- [ ] **Permissions in AndroidManifest.xml:**
  ```xml
  <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
  <uses-permission android:name="android.permission.CAMERA" />
  <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" />
  ```

### Content & Policy
- [ ] **Content Rating Questionnaire:** Complete IARC form (likely "Mature 17+")
- [ ] **Privacy Policy URL:** Required for apps with user accounts
- [ ] **Data Safety Form:** Declare what data you collect
  - Location (Approximate & Precise)
  - Personal Info (Name, Email, Photos)
  - User-Generated Content

### Play Store Policies Compliance
- ✅ **User-Generated Content:** Moderation system required (✅ Built)
- ✅ **Restricted Content:** 18+ enforcement (✅ Built)
- ⚠️ **Data Deletion:** Users must be able to delete their account
- ✅ **Deceptive Behavior:** App does what it says

---

## 🚀 Pre-Launch Checklist

### Legal Documents (URGENT)
- [ ] Create **Privacy Policy** (use generator like [termly.io](https://termly.io))
- [ ] Create **Terms of Service**
- [ ] Host on public URL (e.g., `hanghut.com/privacy`, `hanghut.com/terms`)
- [ ] Update URLs in `lib/core/constants/app_constants.dart`

### App Store Assets
- [ ] **App Icon** (1024x1024 PNG, no transparency)
- [ ] **Screenshots** (iPhone 6.7", 6.5", 5.5" + iPad Pro 12.9")
- [ ] **App Preview Video** (15-30 seconds, optional but recommended)
- [ ] **App Description** (marketing copy)
- [ ] **Keywords** (iOS: 100 chars, Android: unlimited)

### Backend Readiness
- [ ] **Admin Dashboard** functional (for content moderation)
- [ ] **Supabase RLS Policies** tested and secure
- [ ] **Rate Limiting** on API endpoints (prevent abuse)
- [ ] **Backup Strategy** for database

### Testing
- [ ] **TestFlight Beta** (iOS) - 2-4 weeks with real users
- [ ] **Internal Testing** (Android) - 1-2 weeks
- [ ] **Crash Reporting** integrated (Firebase Crashlytics recommended)
- [ ] **Analytics** set up (to track user behavior post-launch)

---

## ⏱️ Timeline Estimate

| Phase | Duration | Notes |
|-------|----------|-------|
| **Legal Docs** | 1-2 days | Use templates, customize for your app |
| **App Store Assets** | 3-5 days | Screenshots, icons, descriptions |
| **TestFlight Setup** | 1 day | Upload build, invite testers |
| **Beta Testing** | 2-4 weeks | Fix bugs, gather feedback |
| **App Review (iOS)** | 1-3 days | Usually 24-48 hours |
| **App Review (Android)** | 1-7 days | Can be faster |
| **Total to Launch** | **4-6 weeks** | From today |

---

## 🔴 Critical Action Items (Do These First)

1. **Register Developer Accounts**
   - Apple: $99/year
   - Google: $25 one-time

2. **Create Legal Documents**
   - Privacy Policy
   - Terms of Service
   - Host them publicly

3. **Add Missing Permissions**
   - Update `Info.plist` (iOS)
   - Update `AndroidManifest.xml` (Android)

4. **Build Admin Dashboard**
   - Phase 1 from `admin_crm_plan.md` (Security + Reports)

5. **Generate App Store Assets**
   - Take screenshots on simulator/device
   - Design app icon (if not done)

---

## 💡 Recommendations

### For Faster Approval
- **Provide Demo Account:** Create a test user for reviewers
- **Explain 18+ Enforcement:** In App Review Notes, explain your age verification
- **Show Moderation:** Demonstrate the reporting system works

### For Better Launch
- **Soft Launch:** Release in one country first (e.g., Philippines)
- **Monitor Closely:** First 48 hours are critical for crash reports
- **Update Quickly:** If reviewers request changes, respond within 24 hours

### Post-Launch
- **Weekly Updates:** Fix bugs, add features based on feedback
- **Community Management:** Respond to reviews (both stores allow replies)
- **Marketing:** App Store Optimization (ASO) - keywords, screenshots, A/B testing
