# TestFlight Submission Guide

## 🎯 Goal
Submit a working build of HangHut to TestFlight for internal testing.

## ✅ Prerequisites Checklist

### Apple Developer Account
- [ ] **Enrolled in Apple Developer Program** ($99/year)
  - Sign up at [developer.apple.com](https://developer.apple.com/programs/)
  - Approval takes 24-48 hours
- [ ] **App Store Connect Access** configured
  - Visit [appstoreconnect.apple.com](https://appstoreconnect.apple.com)

### Xcode & Environment
- [ ] **Xcode installed** (latest stable version recommended)
- [ ] **Signed in to Xcode** with Apple ID
  - Xcode → Settings → Accounts → Add Apple ID
- [ ] **Development certificates** generated
  - Xcode will auto-generate when you select your team

### App Configuration
- [ ] **Bundle Identifier** registered in App Store Connect
  - Format: `com.hanghut.bitemates` (or your choice)
  - Must be unique across App Store
- [ ] **App Icon** ready (1024x1024 PNG, no transparency)
- [ ] **Version & Build Number** set
  - Version: `1.0.0` (marketing version)
  - Build: `1` (increments with each upload)

---

## 📋 Step-by-Step Process

### Step 1: Create App in App Store Connect
1. Go to [App Store Connect](https://appstoreconnect.apple.com)
2. Click **"My Apps"** → **"+"** → **"New App"**
3. Fill in details:
   - **Platform:** iOS
   - **Name:** HangHut (or BiteMates)
   - **Primary Language:** English
   - **Bundle ID:** Select from dropdown (must match Xcode)
   - **SKU:** `hanghut-ios` (internal identifier, can be anything)
   - **User Access:** Full Access

### Step 2: Configure iOS Project in Xcode
Open `/Users/rich/Documents/bitemates/ios/Runner.xcworkspace` in Xcode.

#### A. Signing & Capabilities
1. Select **Runner** target in left sidebar
2. Go to **"Signing & Capabilities"** tab
3. **Automatically manage signing:** ✅ Checked
4. **Team:** Select your Apple Developer team
5. **Bundle Identifier:** Must match App Store Connect (e.g., `com.hanghut.bitemates`)

#### B. General Settings
1. Go to **"General"** tab
2. **Display Name:** HangHut
3. **Version:** 1.0.0
4. **Build:** 1
5. **Deployment Target:** iOS 13.0 (or higher)

#### C. Info.plist Permissions
Ensure these are in `ios/Runner/Info.plist`:
```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>We need your location to show nearby dining tables and events.</string>

<key>NSPhotoLibraryUsageDescription</key>
<string>We need access to your photos to upload profile pictures.</string>

<key>NSCameraUsageDescription</key>
<string>We need camera access to take profile photos.</string>
```

### Step 3: Build Archive
Run these commands from the project root:

```bash
# 1. Clean build folder
flutter clean

# 2. Get dependencies
flutter pub get

# 3. Build iOS release
flutter build ios --release

# 4. Open Xcode workspace
open ios/Runner.xcworkspace
```

In Xcode:
1. Select **"Any iOS Device (arm64)"** as destination (top toolbar)
2. Go to **Product → Archive**
3. Wait for build to complete (5-10 minutes)

### Step 4: Upload to App Store Connect
1. When archive completes, **Organizer** window opens automatically
2. Select your archive → Click **"Distribute App"**
3. Choose **"App Store Connect"** → Next
4. Choose **"Upload"** → Next
5. **Signing:** Automatically manage signing → Next
6. Review summary → **Upload**
7. Wait for upload (can take 10-30 minutes depending on size)

### Step 5: Wait for Processing
1. Go to [App Store Connect](https://appstoreconnect.apple.com)
2. **My Apps → HangHut → TestFlight**
3. Build will show **"Processing"** status
4. Wait 5-30 minutes for Apple to process
5. You'll receive email when ready

### Step 6: Add Internal Testers
1. In TestFlight tab, click **"Internal Testing"**
2. Click **"+"** to create a new group (e.g., "Core Team")
3. Add testers by email
4. Select the build you uploaded
5. Testers receive email with TestFlight link

---

## 🚨 Common Issues & Fixes

### Issue: "No valid signing identity found"
**Fix:** 
- Xcode → Settings → Accounts → Download Manual Profiles
- Or: Uncheck "Automatically manage signing", then re-check it

### Issue: "Bundle identifier is already in use"
**Fix:**
- Change bundle ID in Xcode to something unique
- Update in App Store Connect to match

### Issue: "Missing compliance documentation"
**Fix:**
- In App Store Connect, after upload, answer export compliance questions
- For most apps: "No" to encryption (unless you added custom crypto)

### Issue: Build fails with "Podfile" errors
**Fix:**
```bash
cd ios
pod deintegrate
pod install
cd ..
flutter clean
flutter pub get
```

### Issue: "App icon has transparency"
**Fix:**
- App icon must be 1024x1024 PNG with NO alpha channel
- Use Preview or Photoshop to flatten transparency

---

## 🎉 Success Criteria
- ✅ Build shows in App Store Connect → TestFlight
- ✅ Status changes from "Processing" to "Ready to Test"
- ✅ Testers receive email invitation
- ✅ App installs and launches on tester devices

---

## 📱 Next Steps After TestFlight
1. **Gather Feedback** (1-2 weeks of testing)
2. **Fix Critical Bugs** (crash fixes, major UX issues)
3. **Prepare for Production:**
   - Privacy Policy & Terms (live URLs)
   - App Store screenshots (6.7", 6.5", 5.5" + iPad)
   - App description & keywords
   - Age rating questionnaire
4. **Submit for App Review**

---

## 💡 Pro Tips
- **Increment build number** for each upload (even if version stays 1.0.0)
- **Use descriptive release notes** in TestFlight (helps testers know what changed)
- **Test on real devices** before uploading (simulator ≠ real device)
- **Check Crashlytics** after release to catch issues early
