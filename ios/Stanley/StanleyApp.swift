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
                // The production audit: the only trail is Stanley's own
                // (`Trail`), fixed words with nothing personal in them.
                // Sentry's automatic one records taps, screens and every
                // request's URL, and a URL can carry a username or an id.
                options.enableAutoBreadcrumbTracking = false
                options.enableNetworkBreadcrumbs = false
                // A server's 5xx is a server problem, logged on the server;
                // reporting it from phones would send request URLs too.
                options.enableCaptureFailedRequests = false
                options.maxBreadcrumbs = 30
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

/// Words in the dark room are a warm white, not a stark one (`DarkRoom.ink`).
/// Set once at the root for everything that doesn't name its own color; in
/// light mode it hands back `.foreground`, which is the default, so the
/// journal's words don't move by a shade. One view either way, so flipping
/// the appearance doesn't rebuild the app.
private struct DarkRoomInk: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    func body(content: Content) -> some View {
        content.foregroundStyle(
            DarkRoom.isDark(colorScheme) ? AnyShapeStyle(DarkRoom.ink) : AnyShapeStyle(ForegroundStyle())
        )
    }
}

extension View {
    func darkRoomInk() -> some View { modifier(DarkRoomInk()) }

    /// A destructive button's red, said outright. The ink above is set at
    /// the root, and an inherited foreground style outranks a button's role,
    /// so from build 24 Leave Circle, Reset Code, Delete Account and Block
    /// came out in ink instead of red (found in the production audit's
    /// screenshots). Alerts, menus and swipe actions are drawn by UIKit and
    /// keep their own red; this is for buttons laid in a page or a form.
    func destructiveInk() -> some View { foregroundStyle(.red) }
}

struct RootView: View {
    @Environment(AppState.self) private var state
    @Environment(\.scenePhase) private var scenePhase
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
                    if state.offline {
                        // Nothing has said whether this person has a circle,
                        // so they aren't sent to join one. It opens by itself
                        // when Stanley answers, and this pass runs again.
                        OfflineCover()
                            .transition(.opacity)
                    } else {
                        ProgressView()
                            .task {
                                // The profile first: whether we know this
                                // person's name decides whether setup comes next.
                                await state.loadProfile()
                                await state.loadCircle()
                                // A fresh thirty days, at most once a day.
                                await state.refreshSignInIfDue()
                            }
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
            // The dark room's ink (build 24): every word warm white on black.
            // In light mode the foreground is left exactly as it was.
            .darkRoomInk()
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
        // Back to the front: if Stanley was out of reach, see whether it
        // answers now rather than wait for the next try.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task {
                    await state.checkConnection()
                    await state.refreshSignInIfDue()
                }
            }
        }
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

    /// Which tab; and a tap on the one already showing, which its page
    /// answers by scrolling to its top, or refreshing (`TabTaps`).
    private var selection: Binding<Tab> {
        Binding(
            get: { tab },
            set: { chosen in
                if chosen == tab, let page = Self.page(chosen) { state.tabTaps.tap(page) }
                if chosen != tab { Trail.note(Self.step(chosen)) }
                tab = chosen
            }
        )
    }

    private static func step(_ tab: Tab) -> Trail.Step {
        switch tab {
        case .today: .openedToday
        case .held: .openedHeld
        case .you: .openedYou
        case .world: .openedWorld
        case .settings: .openedSettings
        }
    }

    private static func page(_ tab: Tab) -> TabTaps.Page? {
        switch tab {
        case .today: .today
        case .held: .held
        case .you: .you
        case .world: .world
        case .settings: nil
        }
    }

    var body: some View {
        TabView(selection: selection) {
            TodayFeedView(capturing: $capturing, sideDock: $sideDock)
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
        .modifier(QuietTabBar(sideDock: sideDock))
    }
}

/// The tab bar steps back while you read (build 17): scrolling down Today's
/// pages folds it to the tab you're on, and scrolling back up brings the rest.
/// Not where it's a dock down the side (the Duo's cover), which stands beside
/// the page rather than over it, so there's nothing to fold out of the way.
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

/// The launch, when Stanley can't be reached. Without an answer nobody knows
/// whether this person has a circle, so instead of the circle gate (which it
/// used to fall through to, as if they had none) it says so and waits. It
/// opens by itself as soon as Stanley answers; Try Again only asks sooner.
private struct OfflineCover: View {
    @Environment(AppState.self) private var state
    @State private var trying = false

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.slash")
                .font(.title2)
                .foregroundStyle(.secondary)
                .padding(.bottom, 4)
            Text("Stanley can't be reached right now.")
                .font(.hand(26, bold: true, relativeTo: .title2))
                .multilineTextAlignment(.center)
            Text("It opens by itself when you're back online.")
                .smallCaps(11)
                .multilineTextAlignment(.center)
            Button {
                Task {
                    trying = true
                    await state.checkConnection()
                    trying = false
                }
            } label: {
                Group {
                    if trying {
                        ProgressView()
                    } else {
                        Text("Try again")
                    }
                }
                .font(.hand(20, relativeTo: .body))
                .frame(minWidth: 120, minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
            .disabled(trying)
            .padding(.top, 10)
        }
        .padding(32)
        .frame(maxWidth: 420)
    }
}
