import Foundation

struct TransitionEvent: Codable {
    enum EventType: String, Codable { case activate, deactivate }

    var id: String = UUID().uuidString
    var profileId: String
    var profileName: String
    var category: String
    var timestamp: Date
    var eventType: EventType
    var source: String
}

enum TransitionLogger {
    private static let filename = "profileTransitions.json"

    static func log(
        profileId: String,
        profileName: String,
        category: ProfileCategory,
        eventType: TransitionEvent.EventType,
        source: String
    ) {
        let event = TransitionEvent(
            profileId: profileId,
            profileName: profileName,
            category: category.rawValue,
            timestamp: Date(),
            eventType: eventType,
            source: source
        )
        var events = load()
        events.append(event)
        save(events)
    }

    /// Events for the Mon–Sun week that just ended (used on Sundays to show last week's summary).
    static func eventsForPreviousWeek() -> [TransitionEvent] {
        let cal = Calendar.current
        let lastMonday = cal.date(byAdding: .day, value: -6, to: Date()) ?? Date()
        return eventsForWeek(containing: lastMonday)
    }

    /// All events whose timestamp falls within the Mon–Sun week containing `date`.
    static func eventsForWeek(containing date: Date = Date()) -> [TransitionEvent] {
        let cal = Calendar.current
        guard let weekInterval = cal.dateInterval(of: .weekOfYear, for: date) else { return [] }
        // Calendar week starts Sunday; we want Monday. Shift start by 1 day if needed.
        let weekday = cal.component(.weekday, from: weekInterval.start)
        let monday: Date
        if weekday == 1 {
            monday = cal.date(byAdding: .day, value: 1, to: weekInterval.start) ?? weekInterval.start
        } else {
            monday = weekInterval.start
        }
        // End = next Monday (exclusive)
        let nextMonday = cal.date(byAdding: .day, value: 7, to: monday) ?? weekInterval.end

        return load().filter { $0.timestamp >= monday && $0.timestamp < nextMonday }
    }

    static func load() -> [TransitionEvent] {
        guard let url = fileURL,
              let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([TransitionEvent].self, from: data)) ?? []
    }

    private static func save(_ events: [TransitionEvent]) {
        guard let url = fileURL,
              let data = try? JSONEncoder().encode(events) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private static var fileURL: URL? {
        ProfileStore.storageDirectory.appendingPathComponent(filename)
    }
}

// MARK: - Session records (activate→deactivate pairs)

struct SessionRecord: Identifiable {
    var id: String
    var profileName: String
    var category: ProfileCategory
    var start: Date
    var end: Date?

    var durationMinutes: Int {
        guard let end else { return 0 }
        return max(0, Int(end.timeIntervalSince(start) / 60))
    }

    var formattedDuration: String {
        let m = durationMinutes
        let h = m / 60
        let rem = m % 60
        if h == 0 { return "\(rem)m" }
        if rem == 0 { return "\(h)h" }
        return "\(h)h \(rem)m"
    }

    var dateRange: String {
        let df = DateFormatter()
        df.dateStyle = .short
        df.timeStyle = .short
        let startStr = df.string(from: start)
        guard let end else { return startStr }
        let endCal = Calendar.current.isDate(start, inSameDayAs: end)
        if endCal {
            let tf = DateFormatter()
            tf.timeStyle = .short
            return "\(startStr) – \(tf.string(from: end))"
        } else {
            return "\(startStr) – \(df.string(from: end))"
        }
    }

    static func build(from events: [TransitionEvent]) -> [SessionRecord] {
        var activations: [String: TransitionEvent] = [:]
        var records: [SessionRecord] = []

        for event in events.sorted(by: { $0.timestamp < $1.timestamp }) {
            switch event.eventType {
            case .activate:
                activations[event.profileId] = event
            case .deactivate:
                guard let start = activations[event.profileId] else { continue }
                let cat = ProfileCategory(rawValue: start.category) ?? .focus
                records.append(SessionRecord(
                    id: start.id,
                    profileName: start.profileName,
                    category: cat,
                    start: start.timestamp,
                    end: event.timestamp
                ))
                activations.removeValue(forKey: event.profileId)
            }
        }

        // In-progress sessions (no deactivate yet)
        for event in activations.values {
            let cat = ProfileCategory(rawValue: event.category) ?? .focus
            records.append(SessionRecord(id: event.id, profileName: event.profileName, category: cat, start: event.timestamp, end: nil))
        }

        return records.sorted { $0.start > $1.start }
    }
}

// MARK: - Weekly summary model

struct WeeklySummary {
    struct ProfileSummary {
        var profileName: String
        var category: ProfileCategory
        var totalMinutes: Int

        var formattedDuration: String {
            let h = totalMinutes / 60
            let m = totalMinutes % 60
            if h == 0 { return "\(m)m" }
            if m == 0 { return "\(h)h" }
            return "\(h)h \(m)m"
        }

        var groundingContext: String {
            category.groundingContext(minutes: totalMinutes)
        }
    }

    var totalMinutes: Int
    var perProfile: [ProfileSummary]

    static func build(from events: [TransitionEvent]) -> WeeklySummary {
        var activations: [String: (name: String, category: String, start: Date)] = [:]
        var minutesByProfile: [String: (name: String, category: String, minutes: Int)] = [:]

        let sorted = events.sorted { $0.timestamp < $1.timestamp }

        for event in sorted {
            switch event.eventType {
            case .activate:
                activations[event.profileId] = (event.profileName, event.category, event.timestamp)
            case .deactivate:
                guard let start = activations[event.profileId] else { continue }
                let mins = Int(event.timestamp.timeIntervalSince(start.start) / 60)
                if mins > 0 {
                    var existing = minutesByProfile[event.profileId] ?? (start.name, start.category, 0)
                    existing.minutes += mins
                    minutesByProfile[event.profileId] = existing
                }
                activations.removeValue(forKey: event.profileId)
            }
        }

        let profiles = minutesByProfile.values.compactMap { entry -> ProfileSummary? in
            let cat = ProfileCategory(rawValue: entry.category) ?? .focus
            return ProfileSummary(profileName: entry.name, category: cat, totalMinutes: entry.minutes)
        }.sorted { $0.totalMinutes > $1.totalMinutes }

        let total = profiles.reduce(0) { $0 + $1.totalMinutes }
        return WeeklySummary(totalMinutes: total, perProfile: profiles)
    }

    var formattedTotal: String {
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        if h == 0 { return "\(m) minutes" }
        if m == 0 { return "\(h) hour\(h == 1 ? "" : "s")" }
        return "\(h)h \(m)m"
    }
}
