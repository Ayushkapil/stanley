import Foundation

/// What the home screen widget shows (build 40), as the app last left it in
/// the App Group folder the two share. The widget reads this file and the
/// small pictures beside it and nothing else: it never signs in, never
/// reaches the server, and knows only what the app wrote the last time it
/// had Today on screen.
///
/// What's here is only what Today already shows the person: the circle's
/// name, its countdown if it has one, the newest note on the board, whether
/// today's photo is up, and a few of the circle's newest photos, small.
/// No counts of anything.
///
/// **It goes stale on purpose.** A photo on Stanley fades in six days and
/// can be taken back by whoever posted it, and the widget can't hear about
/// either. So a picture here is shown for at most a day after the app wrote
/// it (`photosKeep`), never past its own six days, and the note only on the
/// day it was written; after that the widget falls back to words until the
/// app is opened again. With the app lock on, no pictures or notes are
/// written at all.
struct WidgetSnapshot: Codable, Equatable {
    static let group = "group.com.ayushkapileshwar.stanley"
    /// How long after the app last wrote them the widget still shows photos.
    static let photosKeep: TimeInterval = 24 * 3600
    /// A photo's public life (`physics.py`): gone from Today after six days.
    static let photoLife: TimeInterval = 144 * 3600

    var writtenAt: Date
    var signedIn: Bool
    var circleName: String?
    /// The atmosphere, and the app's own light or dark if one is forced
    /// ("system", "light", "dark"), so the widget is the same paper.
    var atmosphere: String = "auto"
    var appearance: String = "system"
    var countdown: Countdown?
    /// The phone's own day ("2026-11-12") on which today's photo is up, or
    /// waiting to go up. Any other day, there's one photo waiting.
    var postedOn: String?
    var note: Note?
    /// Newest first.
    var photos: [Shot] = []
    /// The app lock is on: nothing of anyone's is shown, only the circle's
    /// name, its countdown and whether today's photo is up.
    var locked = false
    /// Written while no widget was on the home screen, so the photos and
    /// the note were held back, not missing: the app leaves them only once
    /// there's a widget to clear them away again. Optional, so a snapshot
    /// from before this was added still reads.
    var withheld: Bool?

    struct Note: Codable, Equatable {
        let text: String
        /// Whose, as a note is signed: a first name.
        let name: String
        /// The day it was on the board. A note is the day's alone.
        let day: String
    }

    struct Shot: Codable, Equatable, Identifiable {
        let id: String
        /// The picture's file in the shared folder's `photos`.
        let file: String
        /// Whose, as a print is signed: a first name.
        let name: String
        let mine: Bool
        let takenAt: Date
    }

    static let signedOut = WidgetSnapshot(writtenAt: .distantPast, signedIn: false)

    // MARK: reading it at a moment

    /// "2026-11-12", by the phone's own calendar.
    static func day(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    func posted(at now: Date) -> Bool { postedOn == Self.day(now) }

    /// The note, on its own day only.
    func note(at now: Date) -> Note? {
        guard !locked, let note, note.day == Self.day(now) else { return nil }
        return note
    }

    /// The photos still to be shown: written within the last day, and not
    /// past their own six.
    func photos(at now: Date) -> [Shot] {
        guard !locked, now.timeIntervalSince(writtenAt) < Self.photosKeep else { return [] }
        return photos.filter { now.timeIntervalSince($0.takenAt) < Self.photoLife }
    }

    /// The app's last look, within the day, found nothing in Today. The only
    /// time the widget may say so: with the photos held back, gone stale or
    /// behind the app lock, it doesn't know, and says to open Stanley.
    func emptied(at now: Date) -> Bool {
        !locked && withheld != true && photos.isEmpty && now.timeIntervalSince(writtenAt) < Self.photosKeep
    }

    /// How far a photo has faded at a moment, 0 to 1, as Today draws it:
    /// nothing for its first third, then a smooth fall.
    static func fade(_ takenAt: Date, at now: Date) -> Double {
        let progress = min(1, max(0, now.timeIntervalSince(takenAt) / photoLife))
        let t = min(1, max(0, (progress - 1.0 / 3.0) / (2.0 / 3.0)))
        return t * t * (3 - 2 * t)
    }

    /// The countdown's phase at a moment, if the circle has one running.
    func phase(at now: Date) -> Countdown.Phase? { countdown?.phase(at: now) }
}

/// The shared folder: one small JSON file and a folder of small pictures.
enum WidgetStore {
    static var folder: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetSnapshot.group)
    }

    private static var file: URL? { folder?.appendingPathComponent("widget.json") }
    static var photos: URL? { folder?.appendingPathComponent("photos", isDirectory: true) }

    static func photo(_ name: String) -> URL? { photos?.appendingPathComponent(name) }

    static func read() -> WidgetSnapshot {
        guard let file, let data = try? Data(contentsOf: file),
              let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
        else { return .signedOut }
        return snapshot
    }

    static func write(_ snapshot: WidgetSnapshot) {
        guard let file, let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: file, options: .atomic)
    }

    /// Delete every picture the snapshot doesn't name. A photo that has left
    /// Today, or been taken back, leaves this folder the next time either
    /// the app or the widget looks.
    static func prune(keeping names: Set<String>) {
        guard let photos,
              let found = try? FileManager.default.contentsOfDirectory(atPath: photos.path)
        else { return }
        for name in found where !names.contains(name) {
            try? FileManager.default.removeItem(at: photos.appendingPathComponent(name))
        }
    }
}
