import Foundation
import Observation

/// Your own heart or bookmark as you've just set it (build 77): shown at
/// once wherever the photo is while the server is told, put back if it says
/// no, and forgotten once a fresh Today has caught up. Foundation only, so
/// the unit tests drive it with a stubbed server. One for likes and one for
/// holds, in `AppState`. Never a count: only your own state.
@MainActor
@Observable
final class Taps {
    private var entries: [String: (on: Bool, at: Date)] = [:]
    private let now: () -> Date

    init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    /// What's showing for this photo: what you just set, else what the
    /// server last said.
    func value(_ id: String, server: Bool) -> Bool {
        entries[id]?.on ?? server
    }

    /// Set it at once, tell the server, and put it back if the server says
    /// no, handing the refusal to `surface`. Returns whether it stuck.
    @discardableResult
    func set(
        _ id: String, to on: Bool, from was: Bool,
        send: () async throws -> Void,
        surface: (Error) -> Void
    ) async -> Bool {
        entries[id] = (on, now())
        do {
            try await send()
            return true
        } catch {
            entries[id] = (was, now())
            surface(error)
            return false
        }
    }

    /// A fresh Today asked for at `since` knows everything set before it.
    func forget(before since: Date) {
        entries = entries.filter { $0.value.at >= since }
    }

    /// Signed out: nothing set by one account is kept for the next.
    func forgetAll() {
        entries = [:]
    }
}
