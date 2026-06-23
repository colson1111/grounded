# TestFlight & App Store Submission Checklist

## Before You Archive

- [ ] Bundle ID matches provisioning profile: `com.craig.grounded`
- [ ] Version number set (e.g. `1.0.0`) and build number incremented in Xcode → Target → General
- [ ] Deployment target set appropriately (recommend iOS 17+)
- [ ] All `print()` calls removed ✅
- [ ] App icon present in all required sizes ✅
- [ ] No hardcoded test data or debug flags
- [ ] Family Controls entitlement in `grounded.entitlements` ✅
- [ ] App Group capability on both targets (main app + GroundedScheduleExtension)
- [ ] Signing set to "Automatically manage signing" with your Apple Developer team selected

## Archive & Upload

1. In Xcode: select **Any iOS Device (arm64)** as the build destination
2. **Product → Archive**
3. When the Organizer opens, select the archive → **Distribute App**
4. Choose **TestFlight & App Store** → Next
5. Leave defaults (Upload symbols, Manage version + build number) → Next
6. Review entitlements — confirm `com.apple.developer.family-controls` is listed
7. **Upload** — wait for processing (usually 5–15 min)

## App Store Connect Setup

1. Go to [appstoreconnect.apple.com](https://appstoreconnect.apple.com)
2. **My Apps → +** → New App
   - Platform: iOS
   - Name: Grounded
   - Bundle ID: com.craig.grounded
   - SKU: grounded-ios (any unique string)
3. Fill in **App Information**
   - Category: Productivity (primary), Health & Fitness (secondary)
   - Privacy Policy URL: (host `PRIVACY_POLICY.md` publicly first — GitHub Pages recommended)
4. Fill in **Pricing & Availability**
   - Price: $2.99 (Tier 3)
5. Fill in **App Store listing** (use `docs/APP_STORE_LISTING.md`)
   - Short description
   - Long description
   - Keywords (suggestions: focus, screen time, distraction, blocker, mindfulness, productivity, family)
6. Upload **Screenshots** (required sizes)
   - 6.5" — iPhone 14 Pro Max or 15 Pro Max simulator
   - 5.5" — iPhone 8 Plus simulator
   - Recommended screens: home, active/blocking state, schedule view, onboarding

## TestFlight Internal Testing

1. In App Store Connect → TestFlight tab
2. Select your uploaded build (once processing is complete)
3. **Add Internal Testers** (up to 100, must be added to your team in Users & Access)
4. Or use **Internal Group** → add testers by email
5. They'll receive an email invite and install via the TestFlight app

## TestFlight External Testing (optional, before public release)

1. Create an **External Group**
2. Add up to 10,000 testers by email or public link
3. Submit for **Beta App Review** (usually 1–2 days)
4. Note: external testing requires beta review — Apple will check for crashes and basic functionality

## App Store Submission

1. In App Store Connect → your app → **+ Version** (e.g. 1.0)
2. Select the TestFlight build to submit
3. Answer export compliance questions (likely: No encryption beyond standard iOS)
4. Answer content rights and advertising identifier questions
5. Set release: **Manual** (so you control when it goes live after approval)
6. **Submit for Review**
7. Review typically takes 1–3 days for a new app

## Post-Approval

- [ ] Confirm release manually in App Store Connect
- [ ] Screenshot the "Ready for Sale" status
- [ ] Monitor reviews and crash reports in Xcode → Organizer → Crashes
