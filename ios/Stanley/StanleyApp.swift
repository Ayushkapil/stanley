import Sentry
import SwiftUI

@main
struct StanleyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
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
                .task {
                    // A token from APNs goes to the server for whoever is
                    // signed in; with notifications allowed, every launch
                    // registers again, because a token can change.
                    let state = state
                    Push.shared.onToken = { token in Task { await state.sendPushToken(token) } }
                    await Push.shared.refresh()
                }
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
                            // name decides whether setup comes next.
                            await state.loadProfile()
                            await state.loadCircle()
                        }
                } else if state.needsSetup {
                    // A new account, or one we have no name for: a name, a
                    // username, a few words and a face, one to a screen,
                    // before they meet the circle. If loadProfile failed on
                    // an older account, this is skipped: a network blip
                    // shouldn't strand anyone behind setup.
                    SetupView()
                        .transition(.opacity)
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
    private enum Tab { case today, held, you, world, settings }

    @Environment(AppState.self) private var state
    @State private var tab = Tab.today
    @State private var capturing = false
    @State private var sideDock: CGRect?
    @State private var typing = false

    var body: some View {
        TabView(selection: $tab) {
            TodayFeedView(capturing: $capturing, sideDock: $sideDock, typing: $typing)
                .tabItem { Label("Today", systemImage: "sun.haze") }
                .tag(Tab.today)
            MemoriesView()
                .tabItem { Label("Held", systemImage: "bookmark") }
                .tag(Tab.held)
            ProfileView()
                .tabItem { Label("You", systemImage: "person") }
                .tag(Tab.you)
            WorldTodayView()
                .tabItem { Label("World", systemImage: "globe") }
                .tag(Tab.world)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(Tab.settings)
        }
        // Where the tab bar is a dock down the side (the Duo's cover), Today's
        // camera sits in the dock's column, just above it. It's drawn here,
        // over the tab bar, because UIKit gives a side dock's tab bar the whole
        // strip it stands in, top to bottom: a button inside Today, over that
        // strip, never saw a tap. Today has no pushed screens, so showing it
        // whenever Today is the tab is the same as showing it on Today.
        .overlay {
            if tab == .today, let sideDock, !typing {
                GeometryReader { geo in
                    let origin = geo.frame(in: .global).origin
                    CaptureButton(disabled: state.holdsTheDay) { capturing = true }
                        .position(
                            x: sideDock.midX - origin.x,
                            y: sideDock.minY - 12 - CaptureButton.size / 2 - origin.y
                        )
                }
                .ignoresSafeArea()
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: typing)
        .modifier(QuietTabBar(sideDock: sideDock))
    }
}

/// The tab bar steps back while you read (build 17): scrolling down Today's
/// pages folds it to the tab you're on, and scrolling back up brings the rest.
/// Not where it's a dock down the side (the Duo's cover), where the camera
/// is placed against the dock's own frame and it's out of the page's way
/// already.
private struct QuietTabBar: ViewModifier {
    let sideDock: CGRect?

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.tabBarMinimizeBehavior(sideDock == nil ? .onScrollDown : .never)
        } else {
            content
        }
    }
}
