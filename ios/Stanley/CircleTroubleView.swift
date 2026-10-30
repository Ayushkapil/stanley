import SwiftUI

/// What the launch check shows when it couldn't learn which circle this is.
///
/// Not the circle gate. Only the server answering `no_circle` sends anyone
/// there; before this screen, a member who opened Stanley with no signal was
/// asked to join the circle they were already in. This says what is true,
/// offers one way forward, and looks again by itself whenever the app comes
/// back to the foreground. Nothing counts down, nothing nudges.
struct CircleTroubleView: View {
    let trouble: AppState.CircleTrouble

    @Environment(AppState.self) private var state
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var hSizeClass
    private var density: Density { Density(hSizeClass) }
    @State private var trying = false

    private var title: String {
        switch trouble {
        case .unreachable: return "Couldn't reach Stanley"
        case .signInExpired: return "Your sign-in has expired"
        }
    }

    private var words: String {
        switch trouble {
        case .unreachable: return "Check your connection, or try again in a moment."
        case .signInExpired: return "Sign in again to pick up where you left off."
        }
    }

    private var action: String {
        switch trouble {
        case .unreachable: return "Try again"
        case .signInExpired: return "Sign in again"
        }
    }

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Text(title)
                .font(.keepsake(30))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(words)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if trouble == .unreachable, let pending = state.queue.pending, pending.rejection == nil {
                // Today's photo, taken with no signal and still waiting. Whoever
                // reopens Stanley still offline shouldn't wonder where it went.
                Text("Today's photo is safe on this phone. It'll go up when you're back online.")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(action: act) {
                ZStack {
                    // The word keeps its width while the spinner shows, so the
                    // button doesn't jump between the two.
                    Text(action).opacity(trying ? 0 : 1)
                    if trying { ProgressView() }
                }
                .accentInk()
                .frame(minWidth: 140)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(trying)
            .padding(.top, 8)
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 36)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .readableWidth(density)
        .onChange(of: scenePhase) { _, phase in
            // Back in the foreground: the connection may well be back too.
            if phase == .active && trouble == .unreachable { retry() }
        }
    }

    private func act() {
        switch trouble {
        case .unreachable: retry()
        case .signInExpired: state.signOut()
        }
    }

    private func retry() {
        guard !trying else { return }
        trying = true
        Task {
            let began = ContinuousClock.now
            await state.checkIn()
            // A phone with no signal answers instantly, and a button that
            // seems to do nothing reads as broken. Let the look be seen.
            try? await Task.sleep(until: began + .milliseconds(700), clock: .continuous)
            trying = false
        }
    }
}
