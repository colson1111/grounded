import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings
import UserNotifications

// Minimal copies for the extension — cannot import the main app module.
private struct BlockProfile: Codable {
    var id: String
    var name: String
    var isActive: Bool
    var blockedDomains: [String]
    var activitySelectionData: Data?
    var activityIncludeEntireCategory: Bool = false
    var allowedApplicationTokensData: Data? = nil
    var category: String = "focus"
}

private enum ActivationSource: String, Codable {
    case none, manual, schedule
}

private struct ActiveProfileState: Codable {
    var profile: BlockProfile
    var activationSource: ActivationSource
    var scheduleActivityName: String?
}

private enum ScheduleWindowKey {
    static func make(activityName: String, date: Date = Date()) -> String {
        let day = Int(Calendar.current.startOfDay(for: date).timeIntervalSince1970)
        return "\(activityName).\(day)"
    }
}

private struct TransitionEvent: Codable {
    enum EventType: String, Codable { case activate, deactivate }
    var id: String = UUID().uuidString
    var profileId: String
    var profileName: String
    var category: String
    var timestamp: Date
    var eventType: EventType
    var source: String
}

private enum TransitionLog {
    static func append(profileId: String, profileName: String, category: String, eventType: TransitionEvent.EventType, source: String) {
        let event = TransitionEvent(profileId: profileId, profileName: profileName, category: category, timestamp: Date(), eventType: eventType, source: source)
        var events: [TransitionEvent] = []
        if let url = fileURL, let data = try? Data(contentsOf: url) {
            events = (try? JSONDecoder().decode([TransitionEvent].self, from: data)) ?? []
        }
        events.append(event)
        if let url = fileURL, let data = try? JSONEncoder().encode(events) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: "group.com.craig.grounded")?
            .appendingPathComponent("profileTransitions.json")
    }
}

private enum AppGroupStorage {
    static let id = "group.com.craig.grounded"
    static let profilesFile = "customProfiles.json"
    static let activeProfileFile = "activeProfile.json"
    static let suppressedWindowsFile = "suppressedScheduleWindows.json"

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id)
    }

    static func readData(_ filename: String) -> Data? {
        guard let url = containerURL?.appendingPathComponent(filename) else { return nil }
        return try? Data(contentsOf: url)
    }

    static func writeData(_ data: Data, to filename: String) {
        guard let url = containerURL?.appendingPathComponent(filename) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func loadActiveState() -> ActiveProfileState? {
        guard let data = readData(activeProfileFile) else { return nil }
        if let state = try? JSONDecoder().decode(ActiveProfileState.self, from: data) {
            return state
        }
        if let profile = try? JSONDecoder().decode(BlockProfile.self, from: data) {
            let source: ActivationSource = profile.isActive ? .manual : .none
            return ActiveProfileState(profile: profile, activationSource: source, scheduleActivityName: nil)
        }
        return nil
    }

    static func saveActiveState(_ state: ActiveProfileState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        writeData(data, to: activeProfileFile)
    }

    static func isActivitySuppressedToday(_ activityName: String) -> Bool {
        guard let data = readData(suppressedWindowsFile),
              let keys = try? JSONDecoder().decode(Set<String>.self, from: data) else { return false }
        return keys.contains(ScheduleWindowKey.make(activityName: activityName))
    }

    static func clearSuppression(forActivity activityName: String) {
        guard var keys = try? JSONDecoder().decode(
            Set<String>.self,
            from: readData(suppressedWindowsFile) ?? Data()
        ) else { return }
        keys.remove(ScheduleWindowKey.make(activityName: activityName))
        guard let data = try? JSONEncoder().encode(keys) else { return }
        writeData(data, to: suppressedWindowsFile)
    }
}

class ScheduleMonitor: DeviceActivityMonitor {
    private let store = ManagedSettingsStore()

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        guard let profile = loadProfile(for: activity) else { return }

        if AppGroupStorage.isActivitySuppressedToday(activity.rawValue) {
            return
        }

        if let state = AppGroupStorage.loadActiveState(),
           state.profile.isActive,
           state.activationSource == .manual {
            return
        }

        var updated = profile
        updated.isActive = true
        let state = ActiveProfileState(
            profile: updated,
            activationSource: .schedule,
            scheduleActivityName: activity.rawValue
        )
        AppGroupStorage.saveActiveState(state)
        applyShields(profile)
        postActivationNotification(profileName: profile.name)
        TransitionLog.append(profileId: profile.id, profileName: profile.name, category: profile.category, eventType: .activate, source: "schedule")
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        guard let state = AppGroupStorage.loadActiveState() else {
            clearShields()
            return
        }

        // Manual activation overrides schedule — don't clear when the user took control.
        guard state.activationSource == .schedule else { return }

        // Only clear if this window owns the active session.
        if let startedBy = state.scheduleActivityName {
            guard startedBy == activity.rawValue else { return }
        } else if let profileID = profileID(from: activity) {
            guard profileID == state.profile.id else { return }
        } else {
            return
        }

        let off = BlockProfile(id: "off", name: "Off", isActive: false, blockedDomains: [], activitySelectionData: nil)
        let cleared = ActiveProfileState(
            profile: off,
            activationSource: .none,
            scheduleActivityName: nil
        )
        AppGroupStorage.saveActiveState(cleared)
        clearShields()
        AppGroupStorage.clearSuppression(forActivity: activity.rawValue)
        TransitionLog.append(profileId: state.profile.id, profileName: state.profile.name, category: state.profile.category, eventType: .deactivate, source: "schedule")
    }

    // Activity name format: "grounded.<profileID>.<blockID>.wd<n>"
    private func profileID(from activity: DeviceActivityName) -> String? {
        let raw = activity.rawValue
        guard raw.hasPrefix("grounded.") else { return nil }
        let afterPrefix = raw.dropFirst("grounded.".count)
        guard let dotIndex = afterPrefix.firstIndex(of: ".") else { return nil }
        return String(afterPrefix[afterPrefix.startIndex..<dotIndex])
    }

    private func loadProfile(for activity: DeviceActivityName) -> BlockProfile? {
        guard let profileID = profileID(from: activity) else { return nil }

        if let data = AppGroupStorage.readData(AppGroupStorage.profilesFile),
           let profiles = try? JSONDecoder().decode([BlockProfile].self, from: data),
           let match = profiles.first(where: { $0.id == profileID }) {
            return match
        }
        if let state = AppGroupStorage.loadActiveState(),
           state.profile.id == profileID {
            return state.profile
        }
        return nil
    }

    private func applyShields(_ profile: BlockProfile) {
        store.webContent.blockedByFilter = profile.blockedDomains.isEmpty
            ? nil
            : .specific(Set(profile.blockedDomains.map { WebDomain(domain: $0) }))

        if let data = profile.activitySelectionData,
           let selection = decodeActivitySelection(from: data) {
            let allowed = decodeAllowedTokens(from: profile.allowedApplicationTokensData)
            applyActivityShield(
                selection: selection,
                includeEntireCategory: profile.activityIncludeEntireCategory,
                allowedExceptions: allowed
            )

            store.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens
        } else {
            store.shield.applications = nil
            store.shield.applicationCategories = nil
            store.shield.webDomains = nil
        }
    }

    private func decodeActivitySelection(from data: Data) -> FamilyActivitySelection? {
        if let decoded = try? PropertyListDecoder().decode(FamilyActivitySelection.self, from: data) {
            return decoded
        }
        return try? JSONDecoder().decode(FamilyActivitySelection.self, from: data)
    }

    private func decodeAllowedTokens(from data: Data?) -> Set<ApplicationToken> {
        guard let data,
              let selection = decodeActivitySelection(from: data) else {
            return []
        }
        return selection.applicationTokens
    }

    private func applyActivityShield(
        selection: FamilyActivitySelection,
        includeEntireCategory storedFlag: Bool,
        allowedExceptions: Set<ApplicationToken>
    ) {
        let includeEntireCategory = storedFlag
            || !selection.categoryTokens.isEmpty
            || !selection.applicationTokens.isEmpty
        let exceptions: Set<ApplicationToken>
        if !allowedExceptions.isEmpty {
            exceptions = allowedExceptions
        } else if includeEntireCategory,
                  !selection.categoryTokens.isEmpty,
                  selection.applicationTokens.count <= 50 {
            exceptions = selection.applicationTokens
        } else {
            exceptions = []
        }

        if includeEntireCategory && !selection.categoryTokens.isEmpty {
            store.shield.applicationCategories = .all(except: exceptions)
            store.shield.applications = nil
        } else if !selection.categoryTokens.isEmpty {
            store.shield.applicationCategories = .specific(
                selection.categoryTokens,
                except: exceptions
            )
            store.shield.applications = nil
        } else if !selection.applicationTokens.isEmpty {
            store.shield.applications = selection.applicationTokens
            store.shield.applicationCategories = nil
        } else {
            store.shield.applications = nil
            store.shield.applicationCategories = nil
        }
    }

    private func clearShields() {
        store.shield.applications = nil
        store.shield.applicationCategories = nil
        store.shield.webDomains = nil
        store.webContent.blockedByFilter = nil
    }

    private func postActivationNotification(profileName: String) {
        let content = UNMutableNotificationContent()
        content.title = "Grounded is active"
        content.body = "\"\(profileName)\" is now blocking distractions."
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "grounded.schedule.activate.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
