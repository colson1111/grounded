import SwiftUI
import FamilyControls

struct ProfileListView: View {
    private let manager = BlockingManager.shared
    @State private var showEditor = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if manager.profiles.isEmpty {
                        Text("No profiles yet. Tap + to create one.")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    } else {
                        ForEach(manager.profiles) { profile in
                            NavigationLink {
                                ProfileEditorView(editing: profile)
                            } label: {
                                profileLabel(profile)
                            }
                        }
                        .onDelete { indexSet in
                            for idx in indexSet {
                                manager.deleteProfile(manager.profiles[idx])
                            }
                        }
                    }
                } footer: {
                    Text("Work and Sleep are starter profiles — edit, schedule, or delete them like any other.")
                }
            }
            .navigationTitle("Profiles")
            .groundedListScreen()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showEditor = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showEditor) {
                ProfileEditorView()
            }
        }
    }

    private func profileLabel(_ profile: BlockProfile) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(profile.name)
                .font(.body)
            Text(summaryText(for: profile))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private func summaryText(for profile: BlockProfile) -> String {
        var parts: [String] = []
        if !profile.blockedDomains.isEmpty {
            parts.append("\(profile.blockedDomains.count) domain\(profile.blockedDomains.count == 1 ? "" : "s")")
        }
        if let selection = ActivitySelectionHelpers.decodedSelection(
            from: profile.activitySelectionData,
            includeEntireCategory: profile.activityIncludeEntireCategory
        ) {
            let allowedCount = ActivitySelectionHelpers.decodeAllowedTokens(
                from: profile.allowedApplicationTokensData
            ).count
            let summary = AppBlockingSelectionSummary(selection, allowedExceptionCount: allowedCount)
            if summary.hasBlockingConfigured {
                parts.append(summary.shortProfileSummary)
            }
        }
        if !profile.scheduleBlocks.isEmpty {
            parts.append("\(profile.scheduleBlocks.count) schedule\(profile.scheduleBlocks.count == 1 ? "" : "s")")
        }
        return parts.isEmpty ? "Nothing configured" : parts.joined(separator: " · ")
    }
}
