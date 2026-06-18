import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings
import Observation

@Observable
class BlockingManager {
    static let shared = BlockingManager()

    var isAuthorized = false
    var profiles: [BlockProfile] = []
    var activeState: ActiveProfileState = .off

    private let store = ManagedSettingsStore()
    private var scheduleWatchTask: Task<Void, Never>?

    var activeProfile: BlockProfile { activeState.profile }

    var allProfiles: [BlockProfile] { profiles }

    // MARK: - Setup

    func load() {
        if !ProfileStore.isAppGroupAvailable {
            print("[Grounded] App Group '\(ProfileStore.appGroupID)' is not available. Add App Groups capability to both targets and regenerate provisioning profiles. Using device-local storage until fixed.")
        }
        profiles = ProfileStore.loadProfilesSeedingStartersIfNeeded()
        if let saved = ProfileStore.loadActiveState() {
            activeState = resolvedState(saved)
        }
        refreshAuthorizationStatus()

        Task { @MainActor in
            await registerAllSchedules()
            evaluateScheduledActivation()
            startScheduleWatcher()
        }
    }

    func refreshAuthorizationStatus() {
        isAuthorized = AuthorizationCenter.shared.authorizationStatus == .approved
    }

    /// Screen Time permission is required before DeviceActivityCenter will accept schedules.
    func ensureScheduleAuthorization() async -> Bool {
        refreshAuthorizationStatus()
        if !isAuthorized {
            await requestAuthorization()
        }
        return isAuthorized
    }

    func registerAllSchedules() async {
        guard profiles.contains(where: { !$0.scheduleBlocks.isEmpty }) else { return }
        guard await ensureScheduleAuthorization() else {
            print("[Grounded] Schedules not registered — Screen Time permission not granted.")
            return
        }
        for profile in profiles where !profile.scheduleBlocks.isEmpty {
            syncSchedule(for: profile)
        }
    }

    /// Foreground fallback — DeviceActivityMonitor callbacks are unreliable on iOS.
    func evaluateScheduledActivation() {
        refreshAuthorizationStatus()
        guard isAuthorized else { return }

        ProfileStore.pruneExpiredSuppressions(for: profiles)

        if activeState.activationSource == .manual && activeState.profile.isActive {
            return
        }

        if let profile = profiles.first(where: { isCurrentlyInScheduledWindow(for: $0) }) {
            if ProfileStore.isCurrentWindowSuppressed(for: profile) {
                return
            }
            if activeState.profile.id != profile.id || !activeState.profile.isActive {
                var updated = profile
                updated.isActive = true
                activeState = ActiveProfileState(
                    profile: updated,
                    activationSource: .schedule,
                    scheduleActivityName: nil
                )
                ProfileStore.saveActiveState(activeState)
                applyShields(profile)
                print("[Grounded] Schedule window active — applied '\(profile.name)'")
            }
            return
        }

        if activeState.activationSource == .schedule && activeState.profile.isActive {
            activeState = .off
            ProfileStore.saveActiveState(activeState)
            clearShields()
            print("[Grounded] Schedule window ended — cleared shields")
        }
    }

    private func startScheduleWatcher() {
        scheduleWatchTask?.cancel()
        scheduleWatchTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                evaluateScheduledActivation()
            }
        }
    }

    private func resolvedState(_ saved: ActiveProfileState) -> ActiveProfileState {
        var state = saved
        if let match = profiles.first(where: { $0.id == saved.profile.id }) {
            var profile = match
            profile.isActive = saved.profile.isActive
            state.profile = profile
        }
        if state.profile.id == BlockProfile.off.id {
            state.profile.isActive = false
            state.activationSource = .none
            state.scheduleActivityName = nil
        }
        return state
    }

    func requestAuthorization() async {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            isAuthorized = AuthorizationCenter.shared.authorizationStatus == .approved
        } catch {
            print("[Grounded] Authorization failed: \(error)")
            isAuthorized = false
        }
    }

    // MARK: - Profile activation

    /// Manually activate or deactivate a profile from the main app.
    func activate(_ profile: BlockProfile) async {
        let activating = profile.id != BlockProfile.off.id

        if activating {
            if !isAuthorized { await requestAuthorization() }
            ProfileStore.clearSuppression(forProfileID: profile.id)
            var updated = profiles.first(where: { $0.id == profile.id }) ?? profile
            updated.isActive = true
            activeState = ActiveProfileState(
                profile: updated,
                activationSource: .manual,
                scheduleActivityName: nil
            )
            applyShields(updated)
        } else {
            if profiles.contains(where: { isCurrentlyInScheduledWindow(for: $0) }) {
                ProfileStore.suppressCurrentScheduleWindows(for: profiles)
            }
            activeState = .off
            clearShields()
        }

        ProfileStore.saveActiveState(activeState)
    }

    // MARK: - Shields

    func applyShields(_ profile: BlockProfile) {
        print("[Grounded] applyShields — authorized: \(isAuthorized), domains: \(profile.blockedDomains.count), selectionData: \(profile.activitySelectionData?.count ?? 0) bytes")
        guard isAuthorized else { return }

        store.webContent.blockedByFilter = profile.blockedDomains.isEmpty
            ? nil
            : .specific(Set(profile.blockedDomains.map { WebDomain(domain: $0) }))

        if let selection = ActivitySelectionHelpers.decodedSelection(
            from: profile.activitySelectionData,
            includeEntireCategory: profile.activityIncludeEntireCategory
        ) {
            let allowed = ActivitySelectionHelpers.decodeAllowedTokens(from: profile.allowedApplicationTokensData)
            print("[Grounded] Decoded — apps: \(selection.applicationTokens.count), categories: \(selection.categoryTokens.count), allowedExceptions: \(allowed.count), webDomains: \(selection.webDomainTokens.count), includeEntireCategory: \(selection.includeEntireCategory)")
            ActivitySelectionHelpers.applyShield(
                selection: selection,
                allowedExceptions: allowed,
                to: store
            )
        } else {
            store.shield.applications = nil
            store.shield.applicationCategories = nil
            store.shield.webDomains = nil
        }
    }

    private func clearShields() {
        store.shield.applications = nil
        store.shield.applicationCategories = nil
        store.shield.webDomains = nil
        store.webContent.blockedByFilter = nil
    }

    // MARK: - Schedule

    func isCurrentlyInScheduledWindow(for profile: BlockProfile) -> Bool {
        guard !profile.scheduleBlocks.isEmpty else { return false }
        let cal = Calendar.current
        let now = cal.dateComponents([.weekday, .hour, .minute], from: Date())
        guard let weekday = now.weekday, let h = now.hour, let m = now.minute else { return false }
        let minuteOfDay = h * 60 + m
        return profile.scheduleBlocks.contains { block in
            block.isEnabled &&
            block.weekdays.contains(weekday) &&
            minuteOfDay >= block.startMinuteOfDay &&
            minuteOfDay < block.endMinuteOfDay
        }
    }

    /// Registers DeviceActivity monitoring for every enabled block in the profile.
    func syncSchedule(for profile: BlockProfile) {
        let center = DeviceActivityCenter()

        let oldNames = ProfileStore.loadActivityNames(forProfileID: profile.id)
            .map { DeviceActivityName($0) }
        if !oldNames.isEmpty {
            center.stopMonitoring(oldNames)
        }

        guard !profile.scheduleBlocks.isEmpty else {
            ProfileStore.saveActivityNames([], forProfileID: profile.id)
            return
        }

        guard isAuthorized else {
            print("[Grounded] syncSchedule skipped for '\(profile.name)' — not authorized for Screen Time.")
            return
        }

        var registeredNames: [String] = []

        for block in profile.scheduleBlocks where block.isEnabled && (block.endMinuteOfDay - block.startMinuteOfDay) >= 15 {
            for weekday in block.weekdays.sorted() {
                let name = DeviceActivityName(
                    "grounded.\(profile.id).\(block.id).wd\(weekday)"
                )
                let schedule = DeviceActivitySchedule(
                    intervalStart: DateComponents(
                        hour: block.startMinuteOfDay / 60,
                        minute: block.startMinuteOfDay % 60,
                        weekday: weekday
                    ),
                    intervalEnd: DateComponents(
                        hour: block.endMinuteOfDay / 60,
                        minute: block.endMinuteOfDay % 60,
                        weekday: weekday
                    ),
                    repeats: true
                )
                do {
                    try center.startMonitoring(name, during: schedule)
                    registeredNames.append(name.rawValue)
                    print("[Grounded] Monitoring \(name.rawValue) — \(block.summary)")
                } catch {
                    print("[Grounded] Failed to start monitoring \(name.rawValue): \(error)")
                }
            }
        }

        ProfileStore.saveActivityNames(registeredNames, forProfileID: profile.id)
        print("[Grounded] syncSchedule — registered \(registeredNames.count) activity windows for '\(profile.name)'")
        evaluateScheduledActivation()
    }

    // MARK: - Profile CRUD

    func saveProfile(_ profile: BlockProfile) {
        // Capture whether this profile is currently schedule-locked before mutating state.
        let wasScheduleLocked = activeState.profile.id == profile.id
            && activeState.activationSource == .schedule
            && activeState.profile.isActive

        if let idx = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[idx] = profile
        } else {
            profiles.append(profile)
        }
        ProfileStore.saveProfiles(profiles)

        Task { @MainActor in
            if !profile.scheduleBlocks.isEmpty {
                guard await ensureScheduleAuthorization() else { return }
            }
            syncSchedule(for: profile)
        }

        if activeState.profile.id == profile.id {
            var state = activeState
            state.profile = profile
            state.profile.isActive = activeState.profile.isActive
            // Block deleted mid-window: convert to .manual so the schedule watcher
            // can't auto-clear the session. User must still use anchor/QR to unlock.
            if wasScheduleLocked && !isCurrentlyInScheduledWindow(for: profile) {
                state.activationSource = .manual
            }
            activeState = state
            ProfileStore.saveActiveState(activeState)
            if state.profile.isActive {
                applyShields(profile)
            }
        }
    }

    func deleteProfile(_ profile: BlockProfile) {
        let names = ProfileStore.loadActivityNames(forProfileID: profile.id)
            .map { DeviceActivityName($0) }
        if !names.isEmpty {
            DeviceActivityCenter().stopMonitoring(names)
        }
        ProfileStore.saveActivityNames([], forProfileID: profile.id)
        ProfileStore.markStarterDeleted(profile.id)

        profiles.removeAll { $0.id == profile.id }
        ProfileStore.saveProfiles(profiles)

        if activeState.profile.id == profile.id {
            Task { await activate(BlockProfile.off) }
        }
    }
}
