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
