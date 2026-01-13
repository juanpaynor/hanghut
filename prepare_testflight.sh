#!/bin/bash

# TestFlight Build Preparation Script
# Run this before building for TestFlight

set -e  # Exit on error

echo "🚀 Preparing build for TestFlight..."
echo ""

# Step 1: Clean
echo "📦 Step 1/5: Cleaning build artifacts..."
flutter clean
echo "✅ Clean complete"
echo ""

# Step 2: Get dependencies
echo "📦 Step 2/5: Getting dependencies..."
flutter pub get
echo "✅ Dependencies installed"
echo ""

# Step 3: Update iOS pods
echo "📦 Step 3/5: Updating iOS pods..."
cd ios
pod install
cd ..
echo "✅ Pods updated"
echo ""

# Step 4: Build iOS release
echo "📦 Step 4/5: Building iOS release..."
flutter build ios --release
echo "✅ iOS build complete"
echo ""

# Step 5: Open Xcode
echo "📦 Step 5/5: Opening Xcode..."
open ios/Runner.xcworkspace
echo ""
echo "✅ Xcode opened!"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📱 Next Steps in Xcode:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "1. Select 'Any iOS Device (arm64)' as destination"
echo "2. Go to Product → Archive"
echo "3. Wait for archive to complete"
echo "4. Click 'Distribute App' → 'App Store Connect'"
echo "5. Follow the upload wizard"
echo ""
echo "📖 Full guide: testflight_submission_guide.md"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
