import Foundation

/// What the opened cover says (build 76), Foundation only so the unit
/// tests read it as it is. Nothing here is a number of anything: "Last
/// written" is a date, and the week is five days by their letters.
enum OpenedCoverWords {
    static let lastWritten = "Last written"
    static let thisWeek = "This week"
    static let nothingYet = "Not yet"
    static let open = "Open"
    static let edit = "Edit Cover"
    static let changePhoto = "Change Photo"
    static let rename = "Rename"
    static let coverColour = "Cover Colour"
    /// The brief's "Use most kept photo": the cover never says anything
    /// about anyone's keeps (a product decision, kept on 2026-11-16), so
    /// this puts back the automatic cover, which reads none but your own.
    static let automaticPhoto = "Use Automatic Photo"
    static let openHint = "Opens the journal"
    static let weekHint = "Opens the month's sheet"
    static let closedAnnouncement = "Journals"

    /// "Today", "Yesterday", "Thursday 12 November", or with its year once
    /// it's another year's; nil is "Not yet". A date, never "3 days ago".
    static func lastWritten(_ day: Date?, now: Date = .now, calendar: Calendar = .current) -> String {
        guard let day else { return nothingYet }
        let start = calendar.startOfDay(for: now)
        let then = calendar.startOfDay(for: day)
        if then == start { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: start), then == yesterday { return "Yesterday" }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = calendar.locale ?? .current
        let sameYear = calendar.component(.year, from: then) == calendar.component(.year, from: start)
        formatter.setLocalizedDateFormatFromTemplate(sameYear ? "EEEEdMMMM" : "dMMMMyyyy")
        return formatter.string(from: then)
    }

    /// The last five local days, oldest first and today last, each with
    /// its letter ("S", "M") and the day itself.
    static func lastFiveDays(now: Date = .now, calendar: Calendar = .current) -> [(day: Date, letter: String)] {
        let today = calendar.startOfDay(for: now)
        let letters = calendar.veryShortStandaloneWeekdaySymbols
        return (-4...0).compactMap { back in
            guard let day = calendar.date(byAdding: .day, value: back, to: today) else { return nil }
            return (day, letters[calendar.component(.weekday, from: day) - 1])
        }
    }

    /// Every fixed word the opened cover says; the tests read them all.
    static let words: [String] = [
        lastWritten, thisWeek, nothingYet, open, edit, changePhoto, rename, coverColour, automaticPhoto,
        openHint, weekHint, closedAnnouncement,
    ]
}
