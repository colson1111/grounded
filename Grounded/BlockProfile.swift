import Foundation

// MARK: - Schedule

struct ScheduleBlock: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var startMinuteOfDay: Int    // 0–1439 (minutes from midnight)
    var endMinuteOfDay: Int      // 0–1439
    var weekdays: Set<Int>       // 1=Sunday … 7=Saturday (Calendar convention)
    var isEnabled: Bool = true

    var startHour: Int { startMinuteOfDay / 60 }
    var startMinute: Int { startMinuteOfDay % 60 }
    var endHour: Int { endMinuteOfDay / 60 }
    var endMinute: Int { endMinuteOfDay % 60 }

    var summary: String {
        "\(weekdaysSummary)  \(formatTime(startMinuteOfDay)) – \(formatTime(endMinuteOfDay))"
    }

    private var weekdaysSummary: String {
        let sorted = weekdays.sorted()
        if sorted == [1, 2, 3, 4, 5, 6, 7] { return "Every day" }
        if sorted == [2, 3, 4, 5, 6] { return "Mon–Fri" }
        if sorted == [1, 7] { return "Weekends" }
        let names = ["", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        return sorted.map { names[$0] }.joined(separator: ", ")
    }

    private func formatTime(_ totalMinutes: Int) -> String {
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        let ampm = h < 12 ? "AM" : "PM"
        let displayH = h == 0 ? 12 : h > 12 ? h - 12 : h
        let displayM = m == 0 ? "" : String(format: ":%02d", m)
        return "\(displayH)\(displayM) \(ampm)"
    }

    /// Same-calendar-day end time; schedules cannot cross midnight.
    static func suggestedEnd(afterStart start: Int, durationMinutes: Int = 60) -> Int {
        min(start + max(durationMinutes, 15), 1439)
    }

    /// Keeps end at least 15 minutes after start, defaulting to start + 1 hour.
    mutating func alignEndAfterStartChange() {
        if endMinuteOfDay <= startMinuteOfDay || endMinuteOfDay - startMinuteOfDay < 15 {
            endMinuteOfDay = Self.suggestedEnd(afterStart: startMinuteOfDay)
        }
    }
}

// MARK: - Scheduled windows (unified scheduler)

struct ScheduledWindowEntry: Identifiable, Hashable {
    var profile: BlockProfile
    var block: ScheduleBlock

    var id: String { "\(profile.id).\(block.id)" }
}

enum ScheduleWindowIndex {
    static func allEntries(from profiles: [BlockProfile]) -> [ScheduledWindowEntry] {
        profiles.flatMap { profile in
            profile.scheduleBlocks.map { ScheduledWindowEntry(profile: profile, block: $0) }
        }
        .sorted { $0.block.startMinuteOfDay < $1.block.startMinuteOfDay }
    }

    /// Pairs of entries whose weekday sets and time ranges overlap on at least one day.
    static func overlaps(in entries: [ScheduledWindowEntry]) -> [(ScheduledWindowEntry, ScheduledWindowEntry)] {
        var pairs: [(ScheduledWindowEntry, ScheduledWindowEntry)] = []
        for i in entries.indices {
            for j in entries.indices where j > i {
                let a = entries[i], b = entries[j]
                guard blocksOverlap(a.block, b.block) else { continue }
                pairs.append((a, b))
            }
        }
        return pairs
    }

    private static func blocksOverlap(_ a: ScheduleBlock, _ b: ScheduleBlock) -> Bool {
        guard a.isEnabled, b.isEnabled else { return false }
        guard !a.weekdays.isDisjoint(with: b.weekdays) else { return false }
        return a.startMinuteOfDay < b.endMinuteOfDay && b.startMinuteOfDay < a.endMinuteOfDay
    }
}

// MARK: - Profile category

enum ProfileCategory: String, Codable, CaseIterable {
    case focus
    case family
    case rest
    case personal

    var displayName: String {
        switch self {
        case .focus:    return "Focus / Deep Work"
        case .family:   return "Family Time"
        case .rest:     return "Rest & Sleep"
        case .personal: return "Personal Time"
        }
    }

    /// Returns a grounding metaphor line for a given number of minutes.
    func groundingContext(minutes: Int) -> String {
        switch self {
        case .focus:
            let sessions = max(1, minutes / 45)
            return "\(sessions) deep work session\(sessions == 1 ? "" : "s")"
        case .family:
            let stories = max(1, minutes / 10)
            return "\(stories) bedtime stor\(stories == 1 ? "y" : "ies")"
        case .rest:
            let nights = max(1, minutes / 480)
            return "\(nights) full night\(nights == 1 ? "" : "s") of sleep"
        case .personal:
            let walks = max(1, minutes / 60)
            return "\(walks) hour-long walk\(walks == 1 ? "" : "s")"
        }
    }
}

// MARK: - Activation

enum ActivationSource: String, Codable {
    case none
    case manual
    case schedule
}

/// Runtime blocking state persisted for the main app and schedule extension.
struct ActiveProfileState: Codable {
    var profile: BlockProfile
    var activationSource: ActivationSource = .none
    /// DeviceActivity name that started schedule-based blocking (used to match intervalDidEnd).
    var scheduleActivityName: String?

    static var off: ActiveProfileState {
        ActiveProfileState(profile: BlockProfile.off, activationSource: .none)
    }
}

/// Identifies one occurrence of a schedule window (activity + calendar day).
enum ScheduleWindowKey {
    static func make(activityName: String, date: Date = Date()) -> String {
        let day = Int(Calendar.current.startOfDay(for: date).timeIntervalSince1970)
        return "\(activityName).\(day)"
    }

    static func make(profileID: String, blockID: String, weekday: Int, date: Date = Date()) -> String {
        make(activityName: "grounded.\(profileID).\(blockID).wd\(weekday)", date: date)
    }

    static func activityName(from key: String) -> String? {
        guard let lastDot = key.lastIndex(of: ".") else { return nil }
        let suffix = key[key.index(after: lastDot)...]
        guard Int(suffix) != nil else { return nil }
        return String(key[..<lastDot])
    }

    static func dayStart(from key: String) -> Date? {
        guard let lastDot = key.lastIndex(of: ".") else { return nil }
        guard let interval = TimeInterval(key[key.index(after: lastDot)...]) else { return nil }
        return Date(timeIntervalSince1970: interval)
    }
}

// MARK: - Profile

struct BlockProfile: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var isActive: Bool
    var blockedDomains: [String] = []
    var activitySelectionData: Data? = nil
    /// `FamilyActivitySelection.includeEntireCategory` is not preserved by JSON encoding.
    var activityIncludeEntireCategory: Bool = false
    /// Apps unchecked in the picker (allowed through category shields). PropertyList-encoded tokens.
    var allowedApplicationTokensData: Data? = nil
    var anchorObjects: [String] = []
    var scheduleBlocks: [ScheduleBlock] = []
    var category: ProfileCategory = .focus

    enum CodingKeys: String, CodingKey {
        case id, name, isActive, blockedDomains, activitySelectionData, activityIncludeEntireCategory
        case allowedApplicationTokensData
        case scheduleBlocks
        case anchorObjects
        case antidoteObjects
        case category
    }

    init(
        id: String,
        name: String,
        isActive: Bool,
        blockedDomains: [String] = [],
        activitySelectionData: Data? = nil,
        activityIncludeEntireCategory: Bool = false,
        allowedApplicationTokensData: Data? = nil,
        anchorObjects: [String] = [],
        scheduleBlocks: [ScheduleBlock] = [],
        category: ProfileCategory = .focus
    ) {
        self.id = id
        self.name = name
        self.isActive = isActive
        self.blockedDomains = blockedDomains
        self.activitySelectionData = activitySelectionData
        self.activityIncludeEntireCategory = activityIncludeEntireCategory
        self.allowedApplicationTokensData = allowedApplicationTokensData
        self.anchorObjects = anchorObjects
        self.scheduleBlocks = scheduleBlocks
        self.category = category
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        isActive = try container.decode(Bool.self, forKey: .isActive)
        blockedDomains = try container.decodeIfPresent([String].self, forKey: .blockedDomains) ?? []
        activitySelectionData = try container.decodeIfPresent(Data.self, forKey: .activitySelectionData)
        activityIncludeEntireCategory = try container.decodeIfPresent(Bool.self, forKey: .activityIncludeEntireCategory) ?? false
        allowedApplicationTokensData = try container.decodeIfPresent(Data.self, forKey: .allowedApplicationTokensData)
        if let anchors = try container.decodeIfPresent([String].self, forKey: .anchorObjects) {
            anchorObjects = anchors
        } else {
            anchorObjects = try container.decodeIfPresent([String].self, forKey: .antidoteObjects) ?? []
        }
        scheduleBlocks = try container.decodeIfPresent([ScheduleBlock].self, forKey: .scheduleBlocks) ?? []
        category = try container.decodeIfPresent(ProfileCategory.self, forKey: .category) ?? .focus
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(isActive, forKey: .isActive)
        try container.encode(blockedDomains, forKey: .blockedDomains)
        try container.encodeIfPresent(activitySelectionData, forKey: .activitySelectionData)
        try container.encode(activityIncludeEntireCategory, forKey: .activityIncludeEntireCategory)
        try container.encodeIfPresent(allowedApplicationTokensData, forKey: .allowedApplicationTokensData)
        try container.encode(anchorObjects, forKey: .anchorObjects)
        try container.encode(scheduleBlocks, forKey: .scheduleBlocks)
        try container.encode(category, forKey: .category)
    }

    static let off = BlockProfile(id: "off", name: "Off", isActive: false)

    /// Default starter profiles seeded into storage on first launch.
    static let starterProfiles: [BlockProfile] = [
        BlockProfile(
            id: "work",
            name: "Work",
            isActive: false,
            blockedDomains: [
                "twitter.com", "x.com", "instagram.com", "tiktok.com",
                "reddit.com", "youtube.com", "youtu.be", "googlevideo.com",
                "facebook.com", "netflix.com"
            ],
            anchorObjects: ["refrigerator", "plant", "tree"]
        ),
        BlockProfile(
            id: "sleep",
            name: "Sleep",
            isActive: false,
            blockedDomains: [
                "twitter.com", "x.com", "instagram.com", "tiktok.com",
                "reddit.com", "youtube.com", "youtu.be", "googlevideo.com",
                "facebook.com", "netflix.com", "espn.com", "nytimes.com"
            ],
            anchorObjects: ["coffee", "mug"],
            category: .rest
        ),
    ]
}

// MARK: - Storage

struct ProfileStore {
    static let appGroupID = "group.com.craig.grounded"

    private static let activeProfileFile = "activeProfile.json"
    private static let customProfilesFile = "customProfiles.json"
    private static let deletedStartersFile = "deletedStarterIDs.json"
    private static let suppressedWindowsFile = "suppressedScheduleWindows.json"
    private static let migrationFlagKey = "ProfileStore.migratedToFiles"

    /// True when the App Group container is present in the signed build (both targets + Developer portal).
    static var isAppGroupAvailable: Bool {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) != nil
    }

    static var appGroupContainerPath: String? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?.path
    }

    /// Shared App Group directory when available; otherwise app-local Application Support.
    static var storageDirectory: URL {
        if let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            return container
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Grounded", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func fileURL(_ filename: String) -> URL {
        storageDirectory.appendingPathComponent(filename)
    }

    private static func readData(_ filename: String) -> Data? {
        try? Data(contentsOf: fileURL(filename))
    }

    private static func writeData(_ data: Data, to filename: String) {
        try? data.write(to: fileURL(filename), options: .atomic)
    }

    /// One-time migration from older UserDefaults-based storage.
    private static func migrateLegacyStorageIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: migrationFlagKey) else { return }

        if readData(customProfilesFile) == nil,
           let data = UserDefaults.standard.data(forKey: "customProfiles") {
            writeData(data, to: customProfilesFile)
        }
        if readData(activeProfileFile) == nil,
           let data = UserDefaults.standard.data(forKey: "activeProfile") {
            writeData(data, to: activeProfileFile)
        }

        UserDefaults.standard.set(true, forKey: migrationFlagKey)
    }

    static func saveActiveState(_ state: ActiveProfileState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        writeData(data, to: activeProfileFile)
    }

    static func loadActiveState() -> ActiveProfileState? {
        migrateLegacyStorageIfNeeded()
        guard let data = readData(activeProfileFile) else { return nil }
        if let state = try? JSONDecoder().decode(ActiveProfileState.self, from: data) {
            return state
        }
        // Legacy: file stored a bare BlockProfile before activation-source tracking.
        if let profile = try? JSONDecoder().decode(BlockProfile.self, from: data) {
            let source: ActivationSource = profile.isActive ? .manual : .none
            return ActiveProfileState(profile: profile, activationSource: source)
        }
        return nil
    }

    static func saveProfiles(_ profiles: [BlockProfile]) {
        guard let data = try? JSONEncoder().encode(profiles) else { return }
        writeData(data, to: customProfilesFile)
    }

    static func loadProfiles() -> [BlockProfile] {
        migrateLegacyStorageIfNeeded()
        guard let data = readData(customProfilesFile) else { return [] }
        return (try? JSONDecoder().decode([BlockProfile].self, from: data)) ?? []
    }

    /// Ensures Work/Sleep exist in storage. Previously they were hardcoded presets;
    /// this merges in any missing starters unless the user explicitly deleted them.
    static func loadProfilesSeedingStartersIfNeeded() -> [BlockProfile] {
        var profiles = loadProfiles()
        let deleted = loadDeletedStarterIDs()
        var changed = false

        for starter in BlockProfile.starterProfiles {
            guard !profiles.contains(where: { $0.id == starter.id }),
                  !deleted.contains(starter.id) else { continue }
            profiles.append(starter)
            changed = true
        }

        if profiles.isEmpty, !BlockProfile.starterProfiles.isEmpty {
            profiles = BlockProfile.starterProfiles.filter { !deleted.contains($0.id) }
            changed = true
        }

        if changed {
            saveProfiles(profiles)
        }
        return profiles
    }

    static func markStarterDeleted(_ id: String) {
        guard BlockProfile.starterProfiles.contains(where: { $0.id == id }) else { return }
        var deleted = loadDeletedStarterIDs()
        deleted.insert(id)
        saveDeletedStarterIDs(deleted)
    }

    private static func loadDeletedStarterIDs() -> Set<String> {
        guard let data = readData(deletedStartersFile) else { return [] }
        return (try? JSONDecoder().decode(Set<String>.self, from: data)) ?? []
    }

    private static func saveDeletedStarterIDs(_ ids: Set<String>) {
        guard let data = try? JSONEncoder().encode(ids) else { return }
        writeData(data, to: deletedStartersFile)
    }

    static func saveActivityNames(_ names: [String], forProfileID id: String) {
        guard let data = try? JSONEncoder().encode(names) else { return }
        writeData(data, to: "scheduleActivityNames-\(id).json")
    }

    static func loadActivityNames(forProfileID id: String) -> [String] {
        guard let data = readData("scheduleActivityNames-\(id).json") else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    // MARK: - Schedule window suppression

    /// User manually turned off during a scheduled window — don't re-activate until it ends.
    static func loadSuppressedScheduleWindows() -> Set<String> {
        guard let data = readData(suppressedWindowsFile) else { return [] }
        return (try? JSONDecoder().decode(Set<String>.self, from: data)) ?? []
    }

    static func saveSuppressedScheduleWindows(_ keys: Set<String>) {
        guard let data = try? JSONEncoder().encode(keys) else { return }
        writeData(data, to: suppressedWindowsFile)
    }

    static func suppressCurrentScheduleWindows(for profiles: [BlockProfile], at date: Date = Date()) {
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: date)
        let minuteOfDay = cal.component(.hour, from: date) * 60 + cal.component(.minute, from: date)
        var keys = loadSuppressedScheduleWindows()

        for profile in profiles {
            for block in profile.scheduleBlocks where block.isEnabled &&
                block.weekdays.contains(weekday) &&
                minuteOfDay >= block.startMinuteOfDay &&
                minuteOfDay < block.endMinuteOfDay {
                keys.insert(ScheduleWindowKey.make(
                    profileID: profile.id,
                    blockID: block.id,
                    weekday: weekday,
                    date: date
                ))
            }
        }

        saveSuppressedScheduleWindows(keys)
    }

    static func isCurrentWindowSuppressed(for profile: BlockProfile, at date: Date = Date()) -> Bool {
        let suppressed = loadSuppressedScheduleWindows()
        guard !suppressed.isEmpty else { return false }

        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: date)
        let minuteOfDay = cal.component(.hour, from: date) * 60 + cal.component(.minute, from: date)

        return profile.scheduleBlocks.contains { block in
            block.isEnabled &&
            block.weekdays.contains(weekday) &&
            minuteOfDay >= block.startMinuteOfDay &&
            minuteOfDay < block.endMinuteOfDay &&
            suppressed.contains(ScheduleWindowKey.make(
                profileID: profile.id,
                blockID: block.id,
                weekday: weekday,
                date: date
            ))
        }
    }

    static func isActivitySuppressedToday(_ activityName: String, at date: Date = Date()) -> Bool {
        loadSuppressedScheduleWindows().contains(ScheduleWindowKey.make(activityName: activityName, date: date))
    }

    static func clearSuppression(forActivity activityName: String, at date: Date = Date()) {
        var keys = loadSuppressedScheduleWindows()
        keys.remove(ScheduleWindowKey.make(activityName: activityName, date: date))
        saveSuppressedScheduleWindows(keys)
    }

    static func clearSuppression(forProfileID profileID: String, at date: Date = Date()) {
        var keys = loadSuppressedScheduleWindows()
        keys = keys.filter { key in
            guard let name = ScheduleWindowKey.activityName(from: key),
                  name.hasPrefix("grounded.\(profileID).") else { return true }
            guard let day = ScheduleWindowKey.dayStart(from: key) else { return true }
            return Calendar.current.startOfDay(for: day) != Calendar.current.startOfDay(for: date)
        }
        saveSuppressedScheduleWindows(keys)
    }

    static func pruneExpiredSuppressions(for profiles: [BlockProfile], at date: Date = Date()) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: date)
        let weekday = cal.component(.weekday, from: date)
        let minuteOfDay = cal.component(.hour, from: date) * 60 + cal.component(.minute, from: date)

        var keys = loadSuppressedScheduleWindows()
        keys = keys.filter { key in
            guard let activity = ScheduleWindowKey.activityName(from: key),
                  let day = ScheduleWindowKey.dayStart(from: key) else { return false }
            if day < today { return false }

            guard cal.isDate(day, inSameDayAs: date) else { return true }

            // Same day — keep until the window's end time has passed.
            guard let parsed = parseActivityName(activity) else { return false }
            guard let profile = profiles.first(where: { $0.id == parsed.profileID }),
                  let block = profile.scheduleBlocks.first(where: { $0.id == parsed.blockID }),
                  block.weekdays.contains(weekday) else { return false }
            return minuteOfDay < block.endMinuteOfDay
        }
        saveSuppressedScheduleWindows(keys)
    }

    private static func parseActivityName(_ raw: String) -> (profileID: String, blockID: String)? {
        guard raw.hasPrefix("grounded.") else { return nil }
        let afterPrefix = raw.dropFirst("grounded.".count)
        guard let dotIndex = afterPrefix.firstIndex(of: ".") else { return nil }
        let profileID = String(afterPrefix[afterPrefix.startIndex..<dotIndex])
        let remainder = afterPrefix[afterPrefix.index(after: dotIndex)...]
        guard let wdRange = remainder.range(of: ".wd") else { return nil }
        let blockID = String(remainder[remainder.startIndex..<wdRange.lowerBound])
        return (profileID, blockID)
    }
}
