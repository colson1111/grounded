# Grounded

An iPhone app that helps maintain focus.

## Concept

**Starting focus (easy):**
- Tap a profile on the main screen
- Or let a **schedule** activate it automatically (Settings → Schedule)

**Stopping / switching (hard):**
- **Primary** — scan an anchor object (Use Camera)
- **Backup** — Master Unlock QR (Settings → print; scan in camera QR mode)
- **Switching profiles while blocking** — also requires anchor scan for the active profile
- **Emergency** — Unlock Everything (always available; never bricks the phone)

## User Flow

```
First launch → Onboarding (friction model + Screen Time permission)

Main screen
├── Settings → Manage Profiles · Schedule · Master Unlock QR
├── Status card (BLOCKING / UNLOCKED)
├── Profile list (tap to start; anchor icon = anchor scan required to switch)
├── Use Camera (unlock / switch)
└── Unlock Everything

Settings → Schedule
├── All time windows across profiles
├── Overlap warnings
└── Add / edit / delete windows
```

## Profiles

- **Work** and **Sleep** are starter profiles (seeded once, then stored like custom profiles)
- Fully editable, schedulable, deletable
- **Off** is the virtual unlocked state (not in the profile list)

## Schedules

- Local device time; minimum 15 minutes; cannot span midnight
- New windows default to **start + 1 hour** for end time
- Only one profile active at a time
- Manually turning off during a window suppresses re-activation until that window ends
- Manually switching profiles cancels the scheduled auto-off for that window

## Technical

- Screen Time: `FamilyActivityPicker`, `ManagedSettingsStore`, `DeviceActivityCenter`
- Extension: `GroundedScheduleExtension` / `ScheduleMonitor`
- Persistence: App Group JSON files
- Vision: Apple built-in classifier for anchor unlock only

See [`docs/STATUS.md`](STATUS.md) and [`docs/SETUP.md`](SETUP.md).
