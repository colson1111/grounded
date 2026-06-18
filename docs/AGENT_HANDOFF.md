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

## Suggested next phases

### Phase A — Friction polish
- Confirmation before Unlock Everything
- Optional: replay onboarding in Settings

### Phase B — Schedule notifications
- Local notification when schedule activates a profile

### Phase C — Weekly summary
- Track `activeProfile` transitions locally; weekly in-app card

### Phase D — App Store prep
- Strip `print()`, privacy policy, entitlement approval, TestFlight

## Testing checklist

- [x] Schedule fires at correct time
- [x] Manual deactivate mid-window stays off (suppression)
- [x] Deleting a schedule block mid-window does NOT deactivate (stays locked, requires anchor/QR)
- [x] Two overlapping windows show red conflict UI on both entries
- [ ] Object recognition anchor unlock — needs real-world testing
- [ ] QR code generate + scan flow
- [ ] Onboarding shows once; Get Started → main screen
- [ ] Switch profile requires anchor
- [ ] New profile: name field usable while options load

## Do not regress

- Never require anchor to **start** a profile from unlocked state
- Never brick the phone — Unlock Everything + iOS Settings always work
- Schedules must not cross midnight in UI defaults
- Deleting a schedule block mid-window must NOT unlock the app
