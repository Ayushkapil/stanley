import CryptoKit
import Foundation

/// Photos kept on the phone between launches (build 79), so a photo seen
/// once isn't downloaded again on the next launch, or when its fifteen-minute
/// link is renewed. Keyed by what the photo is, its blob's path, never by
/// its link, which changes every time a page is fetched.
///
/// What it won't keep, so a deleted photo doesn't linger:
/// - **A day after it was last shown, it's gone** (`maxAge`). A photo is
///   kept fresh only by being shown, and a photo its poster deleted is never
///   shown again (no page names it), so it's gone within a day, as the
///   widget's copies are.
/// - **Faces** are kept too since build 79, when the server began giving a
///   changed face a new name; before that a face's path stayed the same.
/// - **Nothing once signed out** (`forget`).
/// - **At most `maxBytes`**, the least recently shown going first.
///
/// In the app's Caches folder: never backed up, and iOS may empty it when
/// the phone is short of space. Foundation only, so the unit tests drive it
/// with a folder and a clock of their own.
struct PhotoDisk: Sendable {
    let directory: URL
    var maxAge: TimeInterval = 24 * 60 * 60
    var maxBytes: Int = 150 * 1024 * 1024
    var now: @Sendable () -> Date = { Date() }

    static let shared = PhotoDisk(
        directory: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Photos", isDirectory: true)
    )

    /// Whether a photo at this path may be kept at all.
    static func keeps(_ path: String) -> Bool {
        !path.isEmpty
    }

    private func file(_ path: String) -> URL {
        let digest = SHA256.hash(data: Data(path.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(digest + ".jpg")
    }

    /// The photo's bytes, if kept and shown within the last day; showing it
    /// again starts its day over.
    func read(_ path: String) -> Data? {
        guard Self.keeps(path) else { return nil }
        let url = file(path)
        let fm = FileManager.default
        guard let shown = (try? fm.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date else { return nil }
        guard now().timeIntervalSince(shown) < maxAge else {
            try? fm.removeItem(at: url)
            return nil
        }
        guard let data = try? Data(contentsOf: url) else { return nil }
        try? fm.setAttributes([.modificationDate: now()], ofItemAtPath: url.path)
        return data
    }

    func write(_ data: Data, for path: String) {
        guard Self.keeps(path), !data.isEmpty, data.count <= maxBytes else { return }
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = file(path)
        guard (try? data.write(to: url, options: .atomic)) != nil else { return }
        try? fm.setAttributes([.modificationDate: now()], ofItemAtPath: url.path)
    }

    /// Everything not shown in the last day goes, then the least recently
    /// shown until what's left fits `maxBytes`.
    func prune() {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        guard let files = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys) else { return }
        var kept: [(url: URL, shown: Date, size: Int)] = []
        for url in files {
            let values = try? url.resourceValues(forKeys: Set(keys))
            let shown = values?.contentModificationDate ?? .distantPast
            if now().timeIntervalSince(shown) >= maxAge {
                try? fm.removeItem(at: url)
            } else {
                kept.append((url, shown, values?.fileSize ?? 0))
            }
        }
        var total = kept.reduce(0) { $0 + $1.size }
        for entry in kept.sorted(by: { $0.shown < $1.shown }) where total > maxBytes {
            try? fm.removeItem(at: entry.url)
            total -= entry.size
        }
    }

    /// Signed out: nothing one account was shown is kept for the next.
    func forget() {
        try? FileManager.default.removeItem(at: directory)
    }
}
