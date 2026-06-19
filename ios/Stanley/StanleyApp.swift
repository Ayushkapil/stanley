import SwiftUI

@main
struct StanleyApp: App {
    @State private var state = AppState()

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
                if !state.signedIn {
                    WelcomeView()
                } else if !state.checkedCircle {
                    ProgressView()
                        .task { await state.loadCircle() }
                } else if state.circle == nil {
                    CircleGateView()
                } else {
                    HomeView()
                }
            }
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
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}
