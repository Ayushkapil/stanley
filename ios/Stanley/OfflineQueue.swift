import Foundation
import Observation

/// A capture that happened before the network did.
struct PendingCapture: Codable, Equatable, Identifiable {
    let id: String
    var caption: String?
    var location: String?
    var tagged: [String]
    /// The capture filter's name, if one was chosen. The look itself is
    /// already in the saved JPEG. Missing from captures queued by builds
    /// before filters existed, which decode as nil.
    var filter: String?
    var capturedAt: Date
    /// The timezone the shutter closed in — the day it belongs to.
    var timeZone: String
    /// The circle it was taken for. Each circle has its own day, so this is
    /// whose day it holds and where it goes up. Nil for a capture queued by
    /// a build before multiple circles; `AppState` gives it the first circle,
    /// the only one that build knew.
    var circleId: String?
    /// Set only when the server refused the slot. The photo is then stranded:
    /// it will never upload, and the one honest thing left is to let its owner
    /// keep a copy.
    var rejection: String?

    var jpegURL: URL { OfflineQueue.directory.appendingPathComponent("\(id).jpg") }
}

/// One photo a day in each circle, even with no signal.
///
/// The day law is claimed **locally**, the moment the shutter closes: a queued
/// capture blocks a second one in its circle exactly as an uploaded photo
/// would. That is the whole reason the claim lives here rather than waiting on
/// the server — a law that only holds when you have bars isn't a law.
///
/// At most one capture is ever pending per circle, which falls out of the law
/// itself.
///
/// Main-actor isolated like `AppState`, which owns it and is the only thing
/// that changes it; the pending card reads it on the main thread.
@MainActor
@Observable
final class OfflineQueue {
    nonisolated static let directory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("PendingCaptures", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static var indexURL: URL { directory.appendingPathComponent("pending.json") }

    /// The captures waiting to go up, at most one per circle. Survives
    /// relaunches.
    private(set) var items: [PendingCapture] = []

    init() {
        guard let data = try? Data(contentsOf: Self.indexURL) else { return }
        // Builds before 17 kept a single capture; a list since.
        let saved = (try? JSONDecoder().decode([PendingCapture].self, from: data))
            ?? (try? JSONDecoder().decode(PendingCapture.self, from: data)).map { [$0] }
            ?? []
        items = saved.filter { FileManager.default.fileExists(atPath: $0.jpegURL.path) }
    }

    /// The capture waiting for this circle, if any.
    func pending(in circleId: String?) -> PendingCapture? {
        items.first { $0.circleId == circleId }
    }

    /// True while a capture is waiting for this circle: its day is spoken for.
    func isHoldingTheDay(in circleId: String?) -> Bool { pending(in: circleId) != nil }

    /// A capture queued by a build before multiple circles belongs to the
    /// circle that build showed, the first one joined.
    func adopt(into circleId: String) {
        guard items.contains(where: { $0.circleId == nil }) else { return }
        for index in items.indices where items[index].circleId == nil {
            items[index].circleId = circleId
        }
        persist()
    }

    @discardableResult
    func enqueue(
        jpeg: Data, caption: String?, location: String?, tagged: [String], filter: String? = nil,
        circleId: String?
    ) -> PendingCapture {
        let item = PendingCapture(
            id: UUID().uuidString,
            caption: caption?.isEmpty == true ? nil : caption,
            location: location?.isEmpty == true ? nil : location,
            tagged: tagged,
            filter: filter,
            capturedAt: Date(),
            timeZone: TimeZone.current.identifier,
            circleId: circleId,
            rejection: nil
        )
        try? jpeg.write(to: item.jpegURL, options: .atomic)
        items.append(item)
        persist()
        return item
    }

    func jpeg(_ item: PendingCapture) -> Data? {
        try? Data(contentsOf: item.jpegURL)
    }

    /// The server refused the slot — another device got there first. The photo
    /// stays put so it can still be saved; it is never silently discarded.
    func markRejected(_ item: PendingCapture, _ reason: String) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].rejection = reason
        persist()
    }

    /// It went up, or its owner let it go.
    func clear(_ item: PendingCapture) {
        try? FileManager.default.removeItem(at: item.jpegURL)
        items.removeAll { $0.id == item.id }
        persist()
    }

    private func persist() {
        if items.isEmpty {
            try? FileManager.default.removeItem(at: Self.indexURL)
        } else if let data = try? JSONEncoder().encode(items) {
            try? data.write(to: Self.indexURL, options: .atomic)
        }
    }
}

/// Which failures mean "no network" rather than "the server said no". Only the
/// former is worth queueing for; a real refusal deserves an answer, not a retry.
func isOffline(_ error: Error) -> Bool {
    guard let urlError = error as? URLError else { return false }
    switch urlError.code {
    case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost,
         .cannotFindHost, .timedOut, .dataNotAllowed, .internationalRoamingOff,
         .secureConnectionFailed:
        return true
    default:
        return false
    }
}
