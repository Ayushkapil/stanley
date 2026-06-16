import LocalAuthentication
import SwiftUI

/// Optional Face ID / passcode lock (Part 1). Off by default. When on, the app
/// requires authentication to open and re-locks when it goes to the background.
enum Biometrics {
    static func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            return false
        }
        return await withCheckedContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { ok, _ in
                continuation.resume(returning: ok)
            }
        }
    }
}

/// Wraps the app behind a lock screen when the lock is enabled. The quiet
/// screen mirrors the rest of the product — a single "Unlock" affordance.
struct LockGate<Content: View>: View {
    @AppStorage("stanley.appLock") private var appLock = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var unlocked = false
    @State private var authenticating = false
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            content
            if appLock && !unlocked {
                LockScreen(authenticating: authenticating, unlock: unlock)
            }
        }
        .task {
            if appLock && !unlocked { await unlock() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                unlocked = false  // re-lock the moment we leave
            } else if phase == .active && appLock && !unlocked {
                Task { await unlock() }
            }
        }
        .onChange(of: appLock) { _, enabled in
            if !enabled { unlocked = false } else { Task { await unlock() } }
        }
    }

    private func unlock() async {
        guard !authenticating else { return }
        authenticating = true
        unlocked = await Biometrics.authenticate(reason: "Unlock Stanley")
        authenticating = false
    }
}

private struct LockScreen: View {
    let authenticating: Bool
    let unlock: () async -> Void

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "moon.stars")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                Text("Stanley is locked")
                    .font(.headline)
                Button {
                    Task { await unlock() }
                } label: {
                    Label("Unlock", systemImage: "faceid")
                }
                .buttonStyle(.borderedProminent)
                .disabled(authenticating)
            }
        }
    }
}
