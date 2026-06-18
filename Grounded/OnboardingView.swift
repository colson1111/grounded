import SwiftUI
import FamilyControls

struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var page = 0
    @Bindable private var manager = BlockingManager.shared
    private let pageCount = 4

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                welcomePage.tag(0)
                presencePage.tag(1)
                boundariesPage.tag(2)
                permissionPage.tag(3)
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

            Text("Grounded helps you step away from the noise, so you can be where you actually are. Not a productivity hack. A pause for your mind.")
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
            Text("Constant scrolling pulls your attention in a hundred directions. Grounded quiets the pull. The apps and sites you choose stay out of reach while you're living your life.")
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
            Text("Starting a pause is easy. Tap a profile, or let a schedule welcome you into quieter hours.")
                .foregroundStyle(GroundedTheme.warmEarth)

            Text("Coming back takes a small ritual. A moment to ask yourself: am I ready?")
                .foregroundStyle(GroundedTheme.warmEarth)

            VStack(alignment: .leading, spacing: 10) {
                presenceRow("Scan an anchor, something real in your space, like a book or plant", systemImage: "anchor")
                presenceRow("Or scan your printed unlock code", systemImage: "qrcode")
            }
            .padding(.top, 4)

            Text("You're always in control of your device.")
                .font(.subheadline)
                .foregroundStyle(GroundedTheme.softMist)
        }
    }

    private var permissionPage: some View {
        onboardingPage(
            title: "One Last Step",
            systemImage: "hourglass.circle.fill",
            tint: GroundedTheme.calmGreen
        ) {
            Text("Grounded uses Apple's Screen Time to hold your boundaries gently, even when the app is closed.")
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
