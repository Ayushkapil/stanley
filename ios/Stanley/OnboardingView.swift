import SwiftUI

/// First-launch onboarding: three calm, swipeable pages that introduce Stanley
/// before the sign-in screen. Shown once — RootView gates it on a UserDefaults
/// flag and records it when the user taps "Get started" (available on any
/// page, so no one is forced through all three). Since build 21 they're pages
/// of the journal: grained paper, each headline written in a hand over the
/// paper's double rule, the words quiet beneath, and above each one a small
/// thing laid on the page (a print, prints fading, faces). No assets: the
/// prints are an evening sky drawn in code, on photo paper. No urgency.
struct OnboardingView: View {
    @Environment(\.horizontalSizeClass) private var hSizeClass
    private var density: Density { Density(hSizeClass) }
    @State private var page = 0

    /// Called when the user is done — RootView sets the flag and shows Welcome.
    let onFinish: () -> Void

    private enum Artifact {
        case print, fading, faces
    }

    private struct Page: Identifiable {
        let id = UUID()
        let headline: String
        let body: String
        let artifact: Artifact
    }

    private let pages = [
        Page(
            headline: "One photo a day.",
            body: "No feed to scroll. No album to curate. Just one moment — the one that mattered today.",
            artifact: .print
        ),
        Page(
            headline: "Everything fades.",
            body: "Your photos live for six days, then they're gone — unless someone keeps them. The moments that survive are the ones someone reached for.",
            artifact: .fading
        ),
        Page(
            headline: "A small circle.",
            body: "No followers, no counts. You see faces, not numbers. This is a quiet place.",
            artifact: .faces
        ),
    ]

    var body: some View {
        VStack(spacing: 0) {
            Text("Stanley")
                .smallCaps(11)
                .padding(.top, 14)
                .accessibilityHidden(true)
            TabView(selection: $page) {
                ForEach(Array(pages.enumerated()), id: \.element.id) { index, p in
                    card(p).tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            dots
                .padding(.bottom, 18)
            WideButton(title: "Get started", action: onFinish)
                .padding(.horizontal, 32)
                .padding(.bottom, 24)
                .readableWidth(density)
        }
        .foldAnimated(hSizeClass)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .atmosphereWash()
    }

    /// Where you are among the three, in ink: the system's white dots
    /// vanish on paper.
    private var dots: some View {
        HStack(spacing: 8) {
            ForEach(pages.indices, id: \.self) { index in
                Circle()
                    .fill(.primary.opacity(index == page ? 0.75 : 0.2))
                    .frame(width: 7, height: 7)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: page)
        .accessibilityHidden(true)
    }

    private func card(_ page: Page) -> some View {
        VStack(spacing: 0) {
            Spacer()
            artifact(page.artifact)
                .frame(height: 150)
                .padding(.bottom, 30)
            // One line, written across the page: two lines of a hand this
            // size pushed the words into the dots on the Duo's cover.
            Text(page.headline)
                .font(.hand(44, bold: true, relativeTo: .largeTitle))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 2) {
                Rule(weight: 1.5)
                Rule(weight: 0.5)
            }
            .frame(maxWidth: 240)
            .padding(.top, 10)
            .padding(.bottom, 20)
            Text(page.body)
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 36)
        .frame(maxWidth: .infinity)
        .readableWidth(density)
    }

    @ViewBuilder
    private func artifact(_ kind: Artifact) -> some View {
        switch kind {
        case .print:
            // One print, the day's.
            snapshot(width: 112)
                .asPrint(border: 7, tilt: -3)
        case .fading:
            // The same moment over the days: each print paler than the last.
            HStack(alignment: .bottom, spacing: 18) {
                ForEach(Array([1.0, 0.5, 0.16].enumerated()), id: \.offset) { index, strength in
                    snapshot(width: 70)
                        .saturation(strength)
                        .opacity(0.25 + 0.75 * strength)
                        .asPrint(border: 5, tilt: [-2.5, 1.5, -1][index])
                }
            }
        case .faces:
            // A few people, as faces: never a number of them.
            HStack(spacing: 14) {
                ForEach(Array(["A", "B", "K", "M"].enumerated()), id: \.offset) { index, initial in
                    face(initial, tone: Self.tones[index])
                        .rotationEffect(.degrees([-3, 2, -1.5, 3][index]))
                        .offset(y: index.isMultiple(of: 2) ? 0 : 10)
                }
            }
        }
    }

    /// A photo-shaped wash of an evening sky, standing in for a photo
    /// without being one: warm at the top, dusk at the foot. On Auto the
    /// atmosphere's own charcoal read as a gray placeholder, not a moment.
    private func snapshot(width: CGFloat) -> some View {
        LinearGradient(
            colors: [
                Color(red: 0.95, green: 0.74, blue: 0.47),
                Color(red: 0.80, green: 0.47, blue: 0.45),
                Color(red: 0.36, green: 0.34, blue: 0.50),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(width: width, height: width / PhotoShape.aspect)
        .clipShape(RoundedRectangle(cornerRadius: PrintStock.photoCorner, style: .continuous))
    }

    /// Watercolor tones, the kind a person's name wears in a story: coral,
    /// sage, dusty blue, gold. Gray initials read as keys on a keyboard,
    /// not people.
    private static let tones: [Color] = [
        Color(red: 0.89, green: 0.58, blue: 0.51),
        Color(red: 0.55, green: 0.70, blue: 0.56),
        Color(red: 0.52, green: 0.64, blue: 0.80),
        Color(red: 0.88, green: 0.72, blue: 0.40),
    ]

    private func face(_ initial: String, tone: Color) -> some View {
        Text(initial)
            .font(.hand(26, bold: true, relativeTo: .title2))
            .foregroundStyle(.white)
            .frame(width: 56, height: 56)
            .background(tone, in: RoundedRectangle(cornerRadius: 56 * 0.28, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 3, y: 1.5)
    }
}
