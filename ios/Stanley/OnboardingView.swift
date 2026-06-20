import SwiftUI

/// First-launch onboarding: three calm, swipeable cards that introduce Stanley
/// before the sign-in screen. Shown once — RootView gates it on a UserDefaults
/// flag and records it when the user taps "Get started" (available on any card,
/// so no one is forced through all three). Quiet by design: a serif headline, a
/// couple of low-contrast lines, and the atmosphere's tint. No assets, no urgency.
struct OnboardingView: View {
    @AppStorage("stanley.atmosphere") private var atmosphere = "auto"
    @State private var page = 0

    /// Called when the user is done — RootView sets the flag and shows Welcome.
    let onFinish: () -> Void

    private struct Page: Identifiable {
        let id = UUID()
        let headline: String
        let body: String
    }

    private let pages = [
        Page(
            headline: "One photo a day.",
            body: "No feed to scroll. No album to curate. Just one moment — the one that mattered today."
        ),
        Page(
            headline: "Everything fades.",
            body: "Your photos live for six days, then they're gone — unless someone keeps them. The moments that survive are the ones someone reached for."
        ),
        Page(
            headline: "A small circle.",
            body: "Thirty people, no followers, no counts. You see faces, not numbers. This is a quiet place."
        ),
    ]

    var body: some View {
        let accent = Atmosphere.resolve(atmosphere).palette.accent
        ZStack {
            // Full-bleed atmosphere tint over the system background — reads in
            // both light and dark mode (it's a wash over the system base).
            Color(.systemBackground).ignoresSafeArea()
            LinearGradient(
                colors: [accent.opacity(0.22), accent.opacity(0.05)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                TabView(selection: $page) {
                    ForEach(Array(pages.enumerated()), id: \.element.id) { index, p in
                        card(p).tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))

                Button(action: onFinish) {
                    Text("Get started")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal, 40)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
    }

    private func card(_ page: Page) -> some View {
        VStack(spacing: 20) {
            Spacer()
            Text(page.headline)
                .font(.keepsake(46))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(page.body)
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(6)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 36)
        .frame(maxWidth: .infinity)
    }
}
