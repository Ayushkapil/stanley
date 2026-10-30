import Sentry
import SwiftUI

@main
struct StanleyApp: App {
    @State private var state = AppState()

    init() {
        // Crash visibility for TestFlight. DSN-gated: empty DSN (every dev
        // build) means Sentry never starts. Crash capture only — no sessions,
        // no tracing, no screenshots, and no user identity is ever attached,
        // so crash data stays anonymous ("not linked to you" on the label).
        if let dsn = Bundle.main.object(forInfoDictionaryKey: "STANLEY_SENTRY_DSN") as? String,
           !dsn.isEmpty {
            SentrySDK.start { options in
                options.dsn = dsn
                options.enableAutoSessionTracking = false  // sessions are usage data
                options.enableAppHangTracking = false      // crashes only, no near-miss noise
                options.attachScreenshot = false           // never ship a user's photo
                options.attachViewHierarchy = false
                options.tracesSampleRate = 0               // no performance telemetry
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(state)
        }
    }
}

struct RootView: View {
    @Environment(AppState.self) private var state
    @AppStorage("stanley.appearance") private var appearance = "system"
    @AppStorage("stanley.atmosphere") private var atmosphere = "auto"
    @AppStorage("stanley.hasSeenOnboarding") private var hasSeenOnboarding = false

    private var colorScheme: ColorScheme? {
        switch appearance {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    var body: some View {
        @Bindable var state = state
        LockGate {
            Group {
                if !state.signedIn && !hasSeenOnboarding {
                    // First launch, never signed in: introduce Stanley quietly,
                    // then fall through to Welcome. Shown once, ever.
                    OnboardingView {
                        withAnimation(.easeInOut(duration: 0.35)) { hasSeenOnboarding = true }
                    }
                    .transition(.opacity)
                } else if !state.signedIn {
                    WelcomeView()
                        .transition(.opacity)
                } else if !state.checkedCircle {
                    ProgressView()
                        .task {
                            // The profile first: whether we know this person's
                            // name decides which gate comes next.
                            await state.loadProfile()
                            await state.loadCircle()
                        }
                } else if state.needsName {
                    // Signed in, but Apple never told us what to call them.
                    // Ask before they meet the circle. If loadProfile failed,
                    // needsName is false and this is skipped — a network blip
                    // should not strand anyone behind a name screen.
                    NameGateView()
                } else if state.circle == nil {
                    CircleGateView()
                } else {
                    HomeView()
                }
            }
            // Fill the screen first. A background covers only its own view's
            // frame, and `ignoresSafeArea` only pushes it into the insets that
            // frame touches. Welcome is a column narrower than the screen, and
            // the launch spinner is a dot, so the floor stopped at their edges
            // and the Duo's dock strip showed the bare window as a black band.
            // Children keep their own layout, centered as before.
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Under every safe-area inset there is — including whatever a
            // hinge or a cover-display dock reserves on a foldable. Each screen
            // paints the floor too, but only within the region it is given; the
            // strip the system holds back would otherwise show the bare window,
            // which in dark mode is a black bar. The floor is opaque and the
            // same color at both layers, so the overlap is invisible and
            // nothing can show through.
            .background(Atmosphere.resolve(atmosphere).palette.floor.ignoresSafeArea())
        }
        .alert(
            state.errorMessage ?? "",
            isPresented: Binding(
                get: { state.errorMessage != nil },
                set: { if !$0 { state.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        }
        .overlay(alignment: .bottom) {
            if let flash = state.flash {
                Text(flash)
                    .font(.callout)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.thinMaterial, in: Capsule())
                    .padding(.bottom, 28)
                    .shadow(radius: 8, y: 2)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: flash) {
                        try? await Task.sleep(nanoseconds: 2_600_000_000)
                        withAnimation { state.flash = nil }
                    }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: state.flash)
        .preferredColorScheme(colorScheme)
        // Ambient seasonal tint — accents, tab bar, card edges (Part 5).
        .tint(Atmosphere.resolve(atmosphere).palette.accent)
    }
}

struct HomeView: View {
    var body: some View {
        TabView {
            TodayFeedView()
                .tabItem { Label("Today", systemImage: "sun.haze") }
            MemoriesView()
                .tabItem { Label("Held", systemImage: "bookmark") }
            ProfileView()
                .tabItem { Label("You", systemImage: "person") }
            WorldTodayView()
                .tabItem { Label("World", systemImage: "globe") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}
