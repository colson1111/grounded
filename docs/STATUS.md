# Grounded App — Status

Personal iPhone focus app using Apple's Screen Time APIs (Family Controls + ManagedSettings) with a Device Activity schedule extension.

## Architecture

| Target | Role |
|---|---|
| **Grounded** (main app) | UI, onboarding, profile management, Screen Time authorization, shield application, schedule registration |
| **GroundedScheduleExtension** | `DeviceActivityMonitor` — applies/clears shields when scheduled windows start and end |

Shared state: App Group `group.com.craig.grounded` as JSON files (`activeProfile.json`, `customProfiles.json`, `suppressedScheduleWindows.json`, etc.).

## Main Screen

| Area | Behavior |
|---|---|
| **Settings** (gear) | Manage Profiles · **Schedule** · Master Unlock QR |
| **Status card** | BLOCKING / UNLOCKED, active profile name |
| **Unlock requirements** | Anchor objects + Master Unlock QR hint when blocking |
| **Profile list** | Tap to start (unlocked) or open camera to switch (while blocking) |
| **Use Camera** | Anchor or QR unlock |
| **Unlock Everything** | Emergency kill switch |

## What's Working

### Profiles & blocking
- Work/Sleep seeded on first launch; fully editable and deletable like any profile
- Custom profiles: app picker, web domains, anchors, schedules
- Screen Time shields for apps (tokens/categories) and web domains
- One profile active at a time

### Friction model
- **Start** — one tap on main screen, or schedule
- **Stop / switch** — anchor scan required (camera); profile switch opens camera with target profile
- **Unlock Everything** — emergency bypass (intentionally still available)
- Master Unlock QR via Settings → print → scan in camera QR mode

### Schedules
- Per-profile time windows (local time, min 15 min, same-day only — no midnight rollover)
- **Default end** — 1 hour after start; auto-adjusts when start changes in editor
- **Unified scheduler** — Settings → Schedule: all windows, overlap warnings, add/edit/delete
- **Activation source tracking** — manual vs schedule; schedule end respects manual override
- **Window suppression** — manually turning off during a window stays off until window ends
- **Foreground fallback** — 30s poll when extension callbacks are unreliable
- Screen Time permission requested when saving schedules and on onboarding

### Vision / anchors
- Centralized `VisionLabelCatalog.isExcluded()` — junk labels filtered everywhere (scan, capture, browser, storage)
- Camera capture ranked list; curated label browser

### UX
- Profile editor: name field immediate; heavy sections load asynchronously
- **Onboarding** — first launch: welcome, start/unlock model, Screen Time permission (`GroundedApp.swift`)

## Partially Working / Known Gaps

- **Device Activity reliability** — Apple extension callbacks are flaky; foreground poll is a backup, not a guarantee when app is never opened
- **Unlock Everything** — still one tap; could add confirmation or bury in Settings
- **App blocking transparency** — Apple hides app names outside `FamilyActivityPicker`
- **Family Controls entitlement** — required for App Store; sideload OK for dev

## Removed / Abandoned

- VPN / Network Extension approach
- Camera-based profile **activation**; `triggerObjects` removed
- Per-profile QR codes; Master Unlock only
- Hardcoded preset-only Work/Sleep (now stored profiles)
- `UserDefaults` App Group storage

## To-Do

### Dogfood / correctness
- [ ] Force-quit + reboot schedule tests documented in QA checklist
- [ ] Schedule auto-start local notification (nice to have)

### Friction polish
- [ ] Harden Unlock Everything (confirm dialog or Settings-only)
- [ ] Replay onboarding from Settings (optional)

### Stats & motivation
- [ ] Weekly summary — local time-in-profile stats

### App Store / release
- [ ] Family Controls distribution entitlement
- [ ] Remove debug `print()` for production
- [ ] Privacy policy, App Privacy labels
- [ ] StoreKit 2 yearly subscription
- [ ] TestFlight

### Nice to have
- [ ] Per-profile Vision confidence threshold
- [ ] Settings → App Group health indicator
- [ ] Discovery mode for unknown domains

## Agent handoff

See [`docs/AGENT_HANDOFF.md`](AGENT_HANDOFF.md) for phase notes and file map for future sessions.
