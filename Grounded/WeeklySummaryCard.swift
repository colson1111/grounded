import SwiftUI

struct WeeklySummaryCard: View {
    let summary: WeeklySummary
    var onDismiss: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Last Week")
                    .font(.headline)
                    .foregroundStyle(GroundedTheme.calmGreen)
                Spacer()
                if let onDismiss {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Dismiss weekly summary")
                }
            }

            Text("\(summary.formattedTotal) of focused time")
                .font(.title3.bold())

            if !summary.perProfile.isEmpty {
                Divider()
                ForEach(summary.perProfile, id: \.profileName) { item in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.profileName)
                                .font(.subheadline.weight(.medium))
                            Text(item.groundingContext)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(item.formattedDuration)
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(GroundedTheme.cardBackground, in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Inline card shown in ContentView on Sundays

@Observable
class WeeklySummaryCardContainer {
    var summary: WeeklySummary? = nil

    func load() {
        let events = TransitionLogger.eventsForPreviousWeek()
        let built = WeeklySummary.build(from: events)
        summary = built.totalMinutes > 0 ? built : nil
    }
}

struct WeeklySummaryCardView: View {
    @AppStorage("lastDismissedSummaryWeek") private var lastDismissedWeek: Int = 0
    var container: WeeklySummaryCardContainer
    private var currentWeekNumber: Int {
        Calendar.current.component(.weekOfYear, from: Date())
    }

    private var isSunday: Bool {
        Calendar.current.component(.weekday, from: Date()) == 1
    }

    var body: some View {
        if isSunday, lastDismissedWeek != currentWeekNumber, let summary = container.summary {
            WeeklySummaryCard(summary: summary) {
                lastDismissedWeek = currentWeekNumber
            }
            .padding(.horizontal)
            .padding(.top, 8)
        }
    }
}
