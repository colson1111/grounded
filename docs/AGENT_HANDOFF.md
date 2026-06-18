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

## Completed phases (Jun 2026)

1. Schedule correctness + manual override + window suppression
2. Work/Sleep as stored profiles
3. Anchor required to switch profiles
4. Vision label exclusions centralized in `VisionLabelCatalog.isExcluded()`
5. Profile editor lazy load + deferred keyboard focus
6. Schedule default end time fix
7. Unified scheduler page
8. Onboarding flow

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

- [ ] New profile: name field usable while options load
- [ ] Schedule: start 11 PM → end defaults 11 PM + 1hr (not 1 AM next day)
- [ ] Settings → Schedule: add/edit/delete; overlap warning shows
- [ ] Onboarding shows once; Get Started → main screen
- [ ] Schedule fires; manual off mid-window stays off; next window still fires
- [ ] Switch profile requires anchor

## Do not regress

- Never require anchor to **start** a profile from unlocked state
- Never brick the phone — Unlock Everything + iOS Settings always work
- Schedules must not cross midnight in UI defaults
