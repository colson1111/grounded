import SwiftUI
import FamilyControls

struct ContentView: View {
    private let manager = BlockingManager.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSettings = false
    @State private var showCamera = false
    @State private var switchToProfile: BlockProfile?

    private var activatableProfiles: [BlockProfile] {
        manager.profiles
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                statusCard
                    .padding(.horizontal)
                    .padding(.top, 8)

                if manager.activeProfile.isActive {
                    unlockRequirements
                        .padding(.horizontal)
                        .padding(.top, 8)
                }

                Divider()
                    .padding(.top, 12)

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(activatableProfiles) { profile in
                            profileRow(profile)
                            if profile.id != activatableProfiles.last?.id {
                                Divider()
                                    .padding(.leading, 52)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                Divider()

                Button {
                    switchToProfile = nil
                    showCamera = true
                } label: {
                    Label("Use Camera", systemImage: "camera.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!manager.activeProfile.isActive)
                .padding()
            }
            .navigationTitle("Grounded")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraUnlockView(switchToProfile: switchToProfile)
            }
            .onChange(of: showCamera) { _, isShowing in
                if !isShowing { switchToProfile = nil }
            }
        }
        .groundedScreen()
        .task {
            manager.load()
            VisionLabelCatalog.preloadTaxonomy()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                manager.refreshAuthorizationStatus()
                manager.evaluateScheduledActivation()
                Task { await manager.registerAllSchedules() }
            }
        }
    }

    private var statusCard: some View {
        VStack(spacing: 6) {
            Text(manager.activeProfile.isActive ? "BLOCKING" : "UNLOCKED")
                .font(.title.bold())
                .foregroundStyle(manager.activeProfile.isActive ? GroundedTheme.gentleRust : GroundedTheme.calmGreen)
            Text(manager.activeProfile.name)
                .font(.title3)
                .foregroundStyle(.secondary)
            if !manager.activeProfile.blockedDomains.isEmpty {
                Text("\(manager.activeProfile.blockedDomains.count) domains blocked")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(GroundedTheme.cardBackground, in: RoundedRectangle(cornerRadius: 16))
    }

    private var unlockRequirements: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("To unlock or switch profiles, scan an anchor with Use Camera:")
                .font(.subheadline.bold())

            if !manager.activeProfile.anchorObjects.isEmpty {
                Label {
                    Text(manager.activeProfile.anchorObjects.map { VisionLabelCatalog.displayName($0) }.joined(separator: ", "))
                } icon: {
                    GroundedAnchorIcon(size: 14)
                }
                .font(.subheadline)
                .foregroundStyle(GroundedTheme.calmGreen)
            }

            Label {
                Text("Master Unlock QR code")
            } icon: {
                Image(systemName: "qrcode")
            }
            .font(.subheadline)
            .foregroundStyle(GroundedTheme.softMist)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(GroundedTheme.accentBackground, in: RoundedRectangle(cornerRadius: 12))
    }

    private func profileRow(_ profile: BlockProfile) -> some View {
        let isActive = manager.activeProfile.id == profile.id && manager.activeProfile.isActive
        let isBlocking = manager.activeProfile.isActive
        let requiresAnchorToSwitch = isBlocking && !isActive

        return HStack(spacing: 12) {
            Button {
                if isBlocking {
                    guard !isActive else { return }
                    switchToProfile = profile
                    showCamera = true
                } else {
                    Task { await manager.activate(profile) }
                }
            } label: {
                rowLeadingIcon(isActive: isActive, requiresAnchor: requiresAnchorToSwitch)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityLabel(
                for: profile,
                isActive: isActive,
                requiresAnchor: requiresAnchorToSwitch
            ))

            VStack(alignment: .leading, spacing: 2) {
                Text(profile.name)
                    .font(.body)
                    .foregroundStyle(isActive ? GroundedTheme.calmGreen : .primary)
                Text(profileSummary(profile))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private func profileSummary(_ profile: BlockProfile) -> String {
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
        return parts.isEmpty ? "Nothing configured" : parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func rowLeadingIcon(isActive: Bool, requiresAnchor: Bool) -> some View {
        if requiresAnchor {
            GroundedAnchorIcon(size: 22, color: GroundedTheme.warmEarth)
                .frame(width: 28, height: 28)
        } else {
            Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundStyle(isActive ? GroundedTheme.calmGreen : .secondary)
        }
    }

    private func accessibilityLabel(for profile: BlockProfile, isActive: Bool, requiresAnchor: Bool) -> String {
        if isActive { return "\(profile.name), active" }
        if requiresAnchor { return "Switch to \(profile.name), requires anchor scan" }
        return "Start \(profile.name)"
    }
}
