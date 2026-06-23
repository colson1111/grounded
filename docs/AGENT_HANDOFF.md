# Agent Handoff — Grounded

Quick context for new agent sessions. Read this + `STATUS.md` before coding.

## Entry point

- **`Grounded/GroundedApp.swift`** — `@main`; shows `OnboardingView` until `hasCompletedOnboarding`, then `ContentView`
- **`Grounded/BlockingManager.swift`** — profiles, shields, schedules, activation state
- **`Grounded/BlockProfile.swift`** — models, `ProfileStore`, schedule suppression keys

## Key files by feature

| Feature | Files |
|---------|--------|
| Main UI | `ContentView.swift` |
| Settings | `SettingsView.swift`, `ProfileListView.swift`, `ProfileEditorView.swift` |
| Unified scheduler | `UnifiedScheduleView.swift`, `ScheduleBlock` helpers in `BlockProfile.swift` |
| Schedule extension | `GroundedScheduleExtension/ScheduleMonitor.swift` |
| Onboarding | `OnboardingView.swift`, `GroundedApp.swift` |
| Anchor / Vision | `VisionLabelCatalog.swift`, `ObjectRecognitionManager.swift`, `AnchorLabelCaptureView.swift` |
| Unlock camera | `CameraUnlockView.swift`, `ObjectRecognitionView.swift` |

## Schedule system (important)

- `ActiveProfileState` in `activeProfile.json`: `activationSource` = `none` \| `manual` \| `schedule`
- `suppressedScheduleWindows.json`: user dismissed during a window → no re-activate until window ends
- `evaluateScheduledActivation()` in `BlockingManager` — 30s foreground fallback
- `ScheduleBlock.suggestedEnd(afterStart:)` — default end = start + 1hr, capped at 23:59

## Schedule-delete bypass fix (Jun 2026)

**Problem:** Deleting a schedule block mid-window deactivated the profile (bypassing anchor/QR unlock).

**Root cause:** `saveProfile` → `syncSchedule` → `evaluateScheduledActivation`. With the block gone, `isCurrentlyInScheduledWindow` returned false → shields cleared.

**Fix (in `saveProfile`):** Capture `wasScheduleLocked` before save. In the sync block, if the profile was schedule-locked and the updated profile is no longer in a scheduled window, convert `activationSource` from `.schedule` to `.manual`. The watcher's early-return guard (`activationSource == .manual && isActive → return`) prevents any subsequent auto-clear. User must still use anchor/QR since there is no deactivate button in the UI.

## Conflict detection UI (Jun 2026)

- `ScheduleWindowIndex.overlaps()` returns pairs of entries whose weekday sets + time ranges overlap
- `conflictingEntryIDs` — Set of both entries in each conflicting pair
- Both entries show a red ⚠ badge and red row background in the schedule list
- Conflict section shows red banner with both profile names (no Active/Skipped distinction — both try to activate at their start times, causing undefined switching behavior)
- Footer: "Both windows will try to activate at their start times…"

## Completed phases (Jun 2026)

1. Schedule correctness + manual override + window suppression
2. Work/Sleep as stored profiles
3. Anchor required to switch profiles
4. Vision label exclusions centralized in `VisionLabelCatalog.isExcluded()`
5. Profile editor lazy load + deferred keyboard focus
6. Schedule default end time fix
7. Unified scheduler page
8. Onboarding flow
9. Schedule conflict UI (red banner + badges on both conflicting entries)
10. Schedule-delete bypass fix
11. Onboarding expanded: master QR page + profile tour page; copy pass (no em dashes, naturalised text)
12. Phase B — Schedule notifications: local `UNUserNotificationCenter` notification on schedule activation, posted from both `BlockingManager` and `ScheduleMonitor`
13. Phase C — Statistics & weekly summary (see below)

## Phase C details (Jun 2026)

### New files
- `Grounded/TransitionLogger.swift` — `TransitionEvent`, `TransitionLogger`, `SessionRecord`, `WeeklySummary`
- `Grounded/WeeklySummaryCard.swift` — Sunday popup card + `WeeklySummaryCardContainer` (`@Observable`)

### Data model
- `ProfileCategory` enum on `BlockProfile`: `.focus`, `.family`, `.rest`, `.personal`
  - Each has `groundingContext(minutes:)` — grounding metaphor (deep work sessions, bedtime stories, full nights sleep, hour-long walks)
- `TransitionEvent` appended to `profileTransitions.json` in app group container on every activate/deactivate
- Both `BlockingManager` and `ScheduleMonitor` log events (extension uses inline `TransitionLog` — can't import main module)

### UI
- `WeeklySummaryCard` in `ContentView` — shows Sundays only, dismissed once/week via `@AppStorage("lastDismissedSummaryWeek")`; loads Mon–Sun of previous week
- Settings → Statistics — all-time per-profile totals + full session list (activate→deactivate pairs)
- Profile editor — "Profile Type" picker added (`@State private var category: ProfileCategory`)
- `ContentView` layout fix — status card moved inside `ScrollView`; `.navigationBarTitleDisplayMode(.inline)` prevents title from scrolling independently

### Deferred todo
- Profile category should suggest default blocked apps when selected in editor (noted during design, not yet built)

## Phase D — App Store prep (Jun 2026)

### Completed
- Stripped all `print()` calls from `BlockingManager.swift` and `ProfileEditorView.swift`
- `docs/APP_STORE_LISTING.md` — name, price ($2.99 one-time), short + long descriptions
- `docs/PRIVACY_POLICY.md` — no data collection, camera on-device only, no third-party SDKs
- `docs/TESTFLIGHT_CHECKLIST.md` — full archive → TestFlight → App Store submission checklist

### Pricing decision
- Launch at $2.99 one-time
- Early buyers grandfathered as "Founding Members" if subscription model added later

### Still required before submission
- [ ] Host privacy policy publicly (enable GitHub Pages on this repo → `/docs` folder)
- [ ] Screenshots: 6.5" (iPhone 14 Pro Max) and 5.5" (iPhone 8 Plus) simulators
- [ ] App Store Connect: create app listing, fill metadata from `APP_STORE_LISTING.md`
- [ ] Archive + upload build from Xcode (see `TESTFLIGHT_CHECKLIST.md`)
- [ ] Beta test via TestFlight before public release

## Suggested next work
- Capture screenshots and set up App Store Connect listing
- Enable GitHub Pages for privacy policy hosting
- TestFlight internal testing
- Deferred feature: profile category → suggest default blocked apps in editor

## Onboarding page order (Jun 2026)

0. Welcome to Grounded
1. Be Here Now
2. Gentle Boundaries
3. Almost There (Screen Time permission)
4. Your Backup Key (master QR — `QRCodeSectionView(profile: .off)`)
5. Creating a Profile (static tour of profile editor sections)
→ Get Started

## QR system notes

- One master unlock QR, not per-profile. Payload: `grounded://profile/<BlockProfile.off.id>`
- `BlockProfile.off` is a fixed sentinel with a stable ID — same QR every install
- Scanner in `CameraUnlockView.swift:68` checks prefix and deactivates active profile
- `MasterUnlockQRView` in `SettingsView.swift:51` renders the same QR in Settings

## Testing checklist

- [x] Schedule fires at correct time
- [x] Manual deactivate mid-window stays off (suppression)
- [x] Deleting a schedule block mid-window does NOT deactivate (stays locked, requires anchor/QR)
- [x] Two overlapping windows show red conflict UI on both entries
- [x] Onboarding replay works from Settings
- [x] Schedule activation triggers local notification
- [x] Statistics page shows per-profile totals + session list
- [x] Weekly summary card appears on Sundays, dismisses once/week
- [ ] Object recognition anchor unlock — needs real-world testing
- [x] QR code generate + scan flow
- [x] Onboarding shows once; Get Started → main screen
- [ ] Switch profile requires anchor
- [ ] New profile: name field usable while options load

## Do not regress

- Never require anchor to **start** a profile from unlocked state
- Never brick the phone — iOS Settings always work as escape hatch
- Schedules must not cross midnight in UI defaults
- Deleting a schedule block mid-window must NOT unlock the app
