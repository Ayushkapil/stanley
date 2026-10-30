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
    /// Set only when the server refused the slot. The photo is then stranded:
    /// it will never upload, and the one honest thing left is to let its owner
    /// keep a copy.
    var rejection: String?

    var jpegURL: URL { OfflineQueue.directory.appendingPathComponent("\(id).jpg") }
}

/// One photo a day, even with no signal.
///
/// The day law is claimed **locally**, the moment the shutter closes: a queued
/// capture blocks a second one exactly as an uploaded photo would. That is the
/// whole reason the claim lives here rather than waiting on the server — a law
/// that only holds when you have bars isn't a law.
///
/// At most one capture is ever pending, which falls out of the law itself.
@Observable
final class OfflineQueue {
    static let directory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("PendingCaptures", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static var indexURL: URL { directory.appendingPathComponent("pending.json") }

    /// The one capture waiting to go up, if any. Survives relaunches.
    private(set) var pending: PendingCapture?

    init() {
        if let data = try? Data(contentsOf: Self.indexURL),
           let saved = try? JSONDecoder().decode(PendingCapture.self, from: data),
           FileManager.default.fileExists(atPath: saved.jpegURL.path) {
            pending = saved
        }
    }

    /// True while a capture is waiting — today's slot is spoken for.
    var isHoldingTheDay: Bool { pending != nil }

    @discardableResult
    func enqueue(
        jpeg: Data, caption: String?, location: String?, tagged: [String], filter: String? = nil
    ) -> PendingCapture {
        let item = PendingCapture(
            id: UUID().uuidString,
            caption: caption?.isEmpty == true ? nil : caption,
            location: location?.isEmpty == true ? nil : location,
            tagged: tagged,
            filter: filter,
            capturedAt: Date(),
            timeZone: TimeZone.current.identifier,
            rejection: nil
        )
        try? jpeg.write(to: item.jpegURL, options: .atomic)
        pending = item
        persist()
        return item
    }

    func jpeg() -> Data? {
        guard let pending else { return nil }
        return try? Data(contentsOf: pending.jpegURL)
    }

    /// The server refused the slot — another device got there first. The photo
    /// stays put so it can still be saved; it is never silently discarded.
    func markRejected(_ reason: String) {
        guard var item = pending else { return }
        item.rejection = reason
        pending = item
        persist()
    }

    /// It went up, or its owner let it go.
    func clear() {
        if let pending { try? FileManager.default.removeItem(at: pending.jpegURL) }
        pending = nil
        try? FileManager.default.removeItem(at: Self.indexURL)
    }

    private func persist() {
        guard let pending, let data = try? JSONEncoder().encode(pending) else { return }
        try? data.write(to: Self.indexURL, options: .atomic)
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
