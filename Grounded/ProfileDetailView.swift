import SwiftUI

/// Read-only detail view for built-in profiles.
struct ProfileDetailView: View {
    let profile: BlockProfile

    var body: some View {
        List {
            Section("Blocked Domains") {
                if profile.blockedDomains.isEmpty {
                    Text("No domains blocked")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(profile.blockedDomains.sorted(), id: \.self) { domain in
                        Text(domain).font(.subheadline)
                    }
                }
            }

            if !profile.anchorObjects.isEmpty {
                Section("Anchor — Unlocks This Profile") {
                    ForEach(profile.anchorObjects, id: \.self) { label in
                        Label {
                            Text(VisionLabelCatalog.displayName(label))
                        } icon: {
                            GroundedAnchorIcon(size: 14)
                        }
                            .foregroundStyle(GroundedTheme.calmGreen)
                    }
                }
            }

        }
        .navigationTitle(profile.name)
        .navigationBarTitleDisplayMode(.large)
        .groundedListScreen()
    }
}
