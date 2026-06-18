# Grounded

An iPhone app that makes it easy to start a focus session and genuinely hard to stop one.

## How it works

**Starting is easy** — tap a profile or let a schedule kick in automatically.

**Stopping requires effort** — you must either scan a physical anchor object with the camera or use a printed QR code. No tap-to-quit.

## Features

- **Blocking profiles** — block apps and websites via Screen Time (no VPN, no root)
- **Schedules** — set time windows per profile; blocking starts and stops automatically
- **Anchor unlock** — point the camera at a real-world object (e.g. your gym bag, a plant) to unlock
- **QR unlock** — print a master QR code and store it somewhere inconvenient
- **Overlap detection** — warns you when two scheduled windows conflict
- **Emergency unlock** — always available; never bricks the phone
- **Starter profiles** — Work and Sleep profiles seeded on first launch, fully editable

## User flow

```
First launch → Onboarding (explains friction model + requests Screen Time permission)

Main screen
├── Status card (BLOCKING / UNLOCKED + active profile name)
├── Profile list (tap to activate)
├── Use Camera → scan anchor object or QR code to unlock
├── Unlock Everything (emergency)
└── Settings
    ├── Manage Profiles (create, edit, delete)
    ├── Schedule (all windows across profiles, conflict warnings)
    └── Master Unlock QR (print this)
```

## Requirements

- iOS 17+
- Xcode 15+
- Apple developer account (free works for personal use; re-sign every 7 days)
- Family Controls entitlement (works for personal sideloading; requires Apple approval for App Store)

## Project structure

```
Grounded/                        ← main app target
GroundedScheduleExtension/       ← Device Activity monitor extension
docs/                            ← setup, architecture, status notes
```

See [`docs/SETUP.md`](docs/SETUP.md) for Xcode configuration, capabilities, and deployment instructions.

## Building

1. Clone the repo
2. Open `Grounded.xcodeproj`
3. Set your team in Signing & Capabilities for both targets
4. Configure App Groups (`group.com.craig.grounded`) on both targets — see [`docs/SETUP.md`](docs/SETUP.md)
5. Select your device and run the **Grounded** scheme

## Tech

- **Screen Time API** — `FamilyControls`, `ManagedSettings`, `DeviceActivity`
- **Vision** — on-device object classification for anchor unlock
- **AVFoundation** — camera capture and QR scanning
- **Persistence** — JSON files in a shared App Group container
