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

    var body: some View {
        @Bindable var state = state
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
        .alert(
            state.errorMessage ?? "",
            isPresented: Binding(
                get: { state.errorMessage != nil },
                set: { if !$0 { state.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        }
    }
}

struct HomeView: View {
    var body: some View {
        TabView {
            TodayFeedView()
                .tabItem { Label("Today", systemImage: "sun.haze") }
            MemoriesView()
                .tabItem { Label("Kept", systemImage: "bookmark") }
            SettingsView()
                .tabItem { Label("Quiet", systemImage: "moon") }
        }
    }
}
