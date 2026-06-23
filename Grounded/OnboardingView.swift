import SwiftUI
import FamilyControls

struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var page = 0
    @Bindable private var manager = BlockingManager.shared
    private let pageCount = 6

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                welcomePage.tag(0)
                presencePage.tag(1)
                boundariesPage.tag(2)
                permissionPage.tag(3)
                backupKeyPage.tag(4)
                profileTourPage.tag(5)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))

            HStack {
                if page > 0 {
                    Button("Back") { page -= 1 }
                        .foregroundStyle(GroundedTheme.calmGreen)
                }
                Spacer()
                if page < pageCount - 1 {
                    Button("Next") { page += 1 }
                        .buttonStyle(.borderedProminent)
                        .tint(GroundedTheme.calmGreen)
                } else {
                    Button("Get Started") {
                        Task { await finishOnboarding() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(GroundedTheme.calmGreen)
                }
            }
            .padding()
        }
        .background(GroundedTheme.screenBackground)
        .task { manager.load() }
    }

    private var welcomePage: some View {
        onboardingPage(title: "Welcome to Grounded", tint: GroundedTheme.calmGreen) {
            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 120, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 28))
                    .shadow(color: GroundedTheme.calmGreen.opacity(0.2), radius: 12, y: 4)

            Text("Your phone can wait.")
                .font(.title3)
                .foregroundStyle(GroundedTheme.softMist)
                .multilineTextAlignment(.center)

            Text("Grounded helps you put the phone down and be where you actually are. Not a productivity hack. A pause for your mind.")
                .foregroundStyle(GroundedTheme.warmEarth)
                .multilineTextAlignment(.center)
        }
    }

    private var presencePage: some View {
        onboardingPage(
            title: "Be Here Now",
            systemImage: "sun.horizon.fill",
            tint: GroundedTheme.calmGreen
        ) {
            Text("It's easy to pick up your phone and lose the moment. Grounded quiets the noise. The apps and sites you choose stay out of reach while you're actually living your life.")
                .foregroundStyle(GroundedTheme.warmEarth)

            VStack(alignment: .leading, spacing: 10) {
                presenceRow("Read without reaching for your phone")
                presenceRow("Take a walk and actually look around")
                presenceRow("Be with the people in the room")
                presenceRow("Rest without one more check")
            }
            .padding(.top, 4)
        }
    }

    private var boundariesPage: some View {
        onboardingPage(
            title: "Gentle Boundaries",
            systemImage: "leaf.circle.fill",
            tint: GroundedTheme.calmGreen
        ) {
            Text("Starting a pause is easy. Tap a profile, or let a schedule ease you into quieter hours.")
                .foregroundStyle(GroundedTheme.warmEarth)

            Text("Coming back asks for a small moment of intention. A chance to check in with yourself before you dive back in.")
                .foregroundStyle(GroundedTheme.warmEarth)

            VStack(alignment: .leading, spacing: 10) {
                presenceRow("Scan an anchor (something real in your space, like a book or a plant)", systemImage: "anchor")
                presenceRow("Or scan your printed backup key", systemImage: "qrcode")
            }
            .padding(.top, 4)

            Text("You're always in control of your device.")
                .font(.subheadline)
                .foregroundStyle(GroundedTheme.softMist)
        }
    }

    private var permissionPage: some View {
        onboardingPage(
            title: "Almost There",
            systemImage: "hourglass.circle.fill",
            tint: GroundedTheme.calmGreen
        ) {
            Text("Grounded uses Apple's Screen Time to keep your chosen apps out of reach, even when the app is closed.")
                .foregroundStyle(GroundedTheme.warmEarth)

            if manager.isAuthorized {
                Label("Screen Time access granted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(GroundedTheme.calmGreen)
            } else {
                Button("Allow Screen Time Access") {
                    Task { await manager.ensureScheduleAuthorization() }
                }
                .buttonStyle(.bordered)
                .tint(GroundedTheme.calmGreen)
            }
        }
    }

    private var profileTourPage: some View {
        onboardingPage(
            title: "Creating a Profile",
            systemImage: "person.crop.rectangle.fill",
            tint: GroundedTheme.calmGreen
        ) {
            Text("Tap + on the main screen to create your first profile. Each one is a different kind of pause.")
                .foregroundStyle(GroundedTheme.warmEarth)

            VStack(alignment: .leading, spacing: 14) {
                tourRow("Name", systemImage: "pencil", description: "Something that fits the moment: Work, Sleep, Family Time.")
                tourRow("Apps to Block", systemImage: "shield.fill", description: "The apps you want out of reach while the profile is on.")
                tourRow("Websites", systemImage: "globe", description: "Block categories of sites, or add specific ones.")
                tourRow("Schedule", systemImage: "clock", description: "Have it activate automatically at certain times of day.")
                tourRow("Anchor Object", systemImage: "camera.fill", description: "A real object in your space that your camera must see to unlock.")
            }

            Text("You can edit any profile later. Nothing is set in stone.")
                .font(.subheadline)
                .foregroundStyle(GroundedTheme.softMist)
                .multilineTextAlignment(.center)
        }
    }

    private func tourRow(_ title: String, systemImage: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.subheadline)
                .foregroundStyle(GroundedTheme.calmGreen)
                .frame(width: 20, alignment: .center)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(GroundedTheme.warmEarth)
            }
        }
    }

    private var backupKeyPage: some View {
        onboardingPage(
            title: "Your Backup Key",
            systemImage: "qrcode",
            tint: GroundedTheme.calmGreen
        ) {
            Text("This QR code is your master key. Scan it any time to unlock Grounded, no matter which profile is active.")
                .foregroundStyle(GroundedTheme.warmEarth)

            Text("Print it and tuck it somewhere safe: a drawer, a wallet, the back of a notebook. Out of sight, but there when you need it.")
                .foregroundStyle(GroundedTheme.warmEarth)

            QRCodeSectionView(profile: .off, printTitle: "Grounded — Master Unlock")

            Text("Not near a printer right now? No worries. This is always available under Settings > Master Unlock QR.")
                .font(.subheadline)
                .foregroundStyle(GroundedTheme.softMist)
                .multilineTextAlignment(.center)
        }
    }

    private func presenceRow(_ text: String, systemImage: String = "circle.fill") -> some View {
        HStack(alignment: .top, spacing: 10) {
            Group {
                if systemImage == "anchor" {
                    GroundedAnchorIcon(size: 15)
                } else {
                    Image(systemName: systemImage)
                        .font(systemImage == "circle.fill" ? .system(size: 6) : .subheadline)
                        .foregroundStyle(GroundedTheme.calmGreen)
                }
            }
            .padding(.top, systemImage == "circle.fill" ? 6 : 2)
            .frame(width: systemImage == "circle.fill" ? nil : 20, alignment: .center)
            Text(text)
                .foregroundStyle(.primary)
        }
    }

    private func onboardingPage<Content: View>(
        title: String,
        systemImage: String,
        tint: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        onboardingPage(title: title, tint: tint) {
            Image(systemName: systemImage)
                .font(.system(size: 56))
                .foregroundStyle(tint)

            VStack(alignment: .leading, spacing: 14) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func onboardingPage<Content: View>(
        title: String,
        tint: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ScrollView {
            VStack(spacing: 24) {
                Text(title)
                    .font(.title.bold())
                    .foregroundStyle(tint)
                    .multilineTextAlignment(.center)
                    .padding(.top, 40)
                    .padding(.horizontal, 24)

                VStack(spacing: 20) {
                    content()
                }
                .padding(.horizontal, 24)
            }
            .padding(.bottom, 24)
        }
    }

    private func finishOnboarding() async {
        if !manager.isAuthorized {
            await manager.ensureScheduleAuthorization()
        }
        hasCompletedOnboarding = true
    }
}
