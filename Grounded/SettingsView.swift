import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = true

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        ProfileListView()
                    } label: {
                        Label("Manage Profiles", systemImage: "list.bullet")
                    }

                    NavigationLink {
                        UnifiedScheduleView()
                    } label: {
                        Label("Schedule", systemImage: "clock")
                    }

                    NavigationLink {
                        MasterUnlockQRView()
                    } label: {
                        Label("Master Unlock QR", systemImage: "qrcode")
                    }
                }

                Section {
                    NavigationLink {
                        StatisticsView()
                    } label: {
                        Label("Statistics", systemImage: "chart.bar")
                    }

                    Button {
                        hasCompletedOnboarding = false
                        dismiss()
                    } label: {
                        Label("Replay Onboarding", systemImage: "leaf")
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .groundedListScreen()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct StatisticsView: View {
    @State private var events: [TransitionEvent] = []

    private var allTimeSummary: WeeklySummary {
        WeeklySummary.build(from: events)
    }

    private var sessions: [SessionRecord] {
        SessionRecord.build(from: events)
    }

    var body: some View {
        ScrollView {
            if events.isEmpty {
                ContentUnavailableView(
                    "No data yet",
                    systemImage: "chart.bar",
                    description: Text("Activate a profile to start tracking.")
                )
            } else {
                VStack(alignment: .leading, spacing: 20) {
                    totalSection
                    sessionsSection
                }
                .padding()
            }
        }
        .navigationTitle("Statistics")
        .navigationBarTitleDisplayMode(.inline)
        .groundedScreen()
        .task { events = TransitionLogger.load() }
    }

    private var totalSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("All Time")
                .font(.headline)
                .foregroundStyle(GroundedTheme.calmGreen)

            HStack {
                Text("Total")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(allTimeSummary.formattedTotal)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if !allTimeSummary.perProfile.isEmpty {
                Divider()
                ForEach(allTimeSummary.perProfile, id: \.profileName) { item in
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

    private var sessionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sessions")
                .font(.headline)
                .foregroundStyle(GroundedTheme.calmGreen)

            ForEach(sessions) { session in
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.profileName)
                            .font(.subheadline.weight(.medium))
                        Text(session.dateRange)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(session.formattedDuration)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                if session.id != sessions.last?.id {
                    Divider()
                }
            }
        }
        .padding()
        .background(GroundedTheme.cardBackground, in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct MasterUnlockQRView: View {
    private var offProfile: BlockProfile { BlockProfile.off }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("Print and place somewhere inconvenient. Scan with Use Camera → QR Code to unlock everything.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                QRCodeSectionView(profile: offProfile, printTitle: "Grounded — Master Unlock")
            }
            .padding()
        }
        .navigationTitle("Master Unlock QR")
        .navigationBarTitleDisplayMode(.inline)
        .groundedScreen()
    }
}
