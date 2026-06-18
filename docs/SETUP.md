# Grounded — Xcode Setup

## Project Structure

```
grounded/
├── Grounded/                              ← main app target
│   ├── GroundedApp.swift                  ← @main entry, onboarding gate
│   ├── OnboardingView.swift               ← first-launch walkthrough
│   ├── ContentView.swift                  ← main screen (profiles, Use Camera, unlock)
│   ├── SettingsView.swift                 ← Manage Profiles, Schedule, Master Unlock QR
│   ├── UnifiedScheduleView.swift          ← all schedule windows across profiles
│   ├── CameraUnlockView.swift             ← object + QR unlock camera flow
│   ├── BlockingManager.swift              ← Screen Time shields + schedule registration
│   ├── BlockProfile.swift                 ← profile model + file storage (ProfileStore)
│   ├── ProfileListView.swift              ← Settings: manage profiles (edit only)
│   ├── ProfileEditorView.swift            ← create/edit custom profiles
│   ├── ProfileDetailView.swift            ← read-only built-in profile detail
│   ├── KnownApps.swift                    ← domain categories for web blocking
│   ├── VisionLabels.swift                 ← curated Vision taxonomy label browser
│   ├── VisionLabelCatalog.swift           ← label normalization, matching, async preload
│   ├── AnchorLabelCaptureView.swift       ← camera capture → pick detected label
│   ├── ObjectRecognitionManager.swift
│   ├── ObjectRecognitionView.swift
│   ├── QRScannerView.swift
│   ├── QRGeneratorView.swift                ← QRCodeSectionView (Master Unlock only)
│   └── grounded.entitlements
├── GroundedScheduleExtension/             ← Device Activity monitor extension
│   ├── ScheduleMonitor.swift
│   ├── Info.plist
│   └── GroundedScheduleExtension.entitlements
└── docs/
    ├── STATUS.md
    ├── SETUP.md
    ├── PROJECT_OVERVIEW.md
    └── AGENT_HANDOFF.md
```

Run scheme: **Grounded** (builds app + embeds schedule extension).

## Bundle IDs

| Target | Bundle ID |
|---|---|
| Grounded | `com.craig.grounded` |
| GroundedScheduleExtension | `com.craig.grounded.GroundedScheduleExtension` |

App Group (both targets): `group.com.craig.grounded`

## Capabilities Required

| Capability | Target |
|---|---|
| Family Controls | Grounded + GroundedScheduleExtension |
| App Groups (`group.com.craig.grounded`) | Grounded + GroundedScheduleExtension |

Family Controls requires Apple's entitlement approval for App Store distribution. Personal sideloading via Xcode works for development.

### App Group setup (developer.apple.com)

1. Enable **App Groups** on both App IDs; add `group.com.craig.grounded`
2. Regenerate provisioning profiles for both targets
3. Xcode → Settings → Accounts → Download Manual Profiles
4. Both targets → Signing & Capabilities → App Groups (no warnings)
5. Delete app from device, clean build (⇧⌘K), reinstall

If App Group is unavailable, profiles fall back to app-local Application Support (see console log on launch).

## Storage

Profiles are stored as JSON files in the App Group container:

| File | Contents |
|---|---|
| `activeProfile.json` | `ActiveProfileState` (profile + activation source) |
| `customProfiles.json` | All stored profiles (Work, Sleep, custom) |
| `suppressedScheduleWindows.json` | Schedule windows user dismissed for today |
| `scheduleActivityNames-{id}.json` | Registered DeviceActivity names per profile |
| `deletedStarterIDs.json` | Work/Sleep IDs user deleted (won't re-seed) |

Falls back to app-local Application Support if App Group is unavailable. One-time migration copies legacy `UserDefaults` data on first load.

## Adding the Schedule Extension (from scratch)

1. **Main app** — iOS App, SwiftUI, bundle ID `com.craig.grounded`
2. **Add Device Activity Monitor Extension**: File → New → Target → Device Activity Monitor Extension
   - Product Name: `GroundedScheduleExtension`
   - Principal Class: `ScheduleMonitor`
3. **App Groups + Family Controls** on both targets
4. Build Phases → **Embed Foundation Extensions** → Embed & Sign (`CodeSignOnCopy`)

## Deploying to Your iPhone

- Connect iPhone → select device → ⌘R with **Grounded** scheme
- **Screen Time permission** appears when you tap a profile to start blocking (first time only)
- Free developer account: re-run from Xcode every 7 days
- Paid account: 1-year signing

## How Blocking Works

- **Apps** — `FamilyActivityPicker` → `ManagedSettingsStore.shield` (individual app tokens + category tokens)
- **Web domains** — `webContent.blockedByFilter` by domain string (known app domains + custom domains)
- **Schedules** — `DeviceActivityCenter` in main app; `ScheduleMonitor` extension reads profile files and applies shields

### App blocking vs web domain blocking

These are independent:

| Mechanism | What it blocks |
|---|---|
| **Block Specific Apps** (Screen Time) | App icons on the home screen |
| **Block Web Domains** | Websites in Safari by domain name |

To block almost everything but allow an exception (e.g. Google Maps): open **Edit Blocked Apps**, leave all apps/categories checked, and uncheck only the exception. Apple hides app names outside the picker; the individual-app count may be much lower than the number of apps actually blocked when categories are selected.

See [`docs/STATUS.md`](STATUS.md) for feature status and to-do.

## Start & Unlock

| Action | How |
|---|---|
| **Start blocking** | Tap profile on main screen, or scheduled window |
| **Unlock (friction)** | Use Camera → Object (anchor) or QR Code (Master Unlock) |
| **Unlock (emergency)** | Unlock Everything |
| **Configure profiles** | Settings → Manage Profiles (edit only; no activate) |
| **Print Master Unlock QR** | Settings → Master Unlock QR |

QR URL format: `grounded://profile/off` — Master Unlock only. No per-profile QR codes.

## Profile Editor

Custom profiles support:

- **Profile name**
- **Block Specific Apps** — Screen Time picker; summary shows categories, individual apps, and Safari sites
- **Block Web Domains** — preset categories, block-all toggle, custom domains
- **Schedule** — timeline editor with weekday/time windows (min 15 min)
- **Anchor Settings** — add labels one at a time:
  - **Detect with Camera** — capture a frame, pick from ranked Vision detections
  - **Browse Vision Labels** — curated Apple taxonomy identifiers
  - Swipe to remove; no manual freeform entry

Sections are collapsed by default on new profiles for faster load. Vision taxonomy preloads in the background.

## Built-in Profiles

| Profile | Blocks |
|---|---|
| Work | Social media, YouTube, Reddit, Netflix |
| Sleep | Work domains + news sites |
| Off | Nothing (unlocked / Master Unlock target) |

Presets in `BlockProfile.swift` → `presets`. Custom profiles created in Settings → Manage Profiles (+).
