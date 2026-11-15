import Foundation

/// The answer sheet's rules (build 65), apart from how it's drawn, so the
/// unit tests can hold them. One row a day of the month, five bubbles a
/// row, no labels and no numbers on them; one bubble filled marks the day.
///
/// Only today's row takes a mark, and today is the phone's own day
/// (`LocalDay`), turning at its own midnight. A day gone by stays as it
/// was, marked or not, for good: nothing fills in a missed day. Days still
/// to come are drawn faint and take nothing. Nothing here counts, totals,
/// averages, compares or says anything about the marks: the person reads
/// the pattern, and the sheet says nothing about it.
enum MarkSheet {
    enum When: Hashable { case past, today, future }

    struct Row: Hashable {
        /// As the server names days: "2026-11-15".
        let day: String
        let date: Date
        /// One of five, or none.
        let level: Int?
        let when: When

        /// Only today's row can be marked, or its mark changed or taken back.
        var takesAMark: Bool { when == .today }
    }

    /// Every day of the month `date` falls in, first to last, each with its
    /// mark and whether it's gone by, today, or still to come.
    static func rows(
        month date: Date, marks: [String: Int], now: Date = .now, calendar: Calendar = .current
    ) -> [Row] {
        let parts = calendar.dateComponents([.year, .month], from: date)
        guard let first = calendar.date(from: parts),
              let range = calendar.range(of: .day, in: .month, for: first) else { return [] }
        let today = LocalDay.number(of: now, calendar: calendar)
        return (0..<range.count).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: first) else { return nil }
            let number = LocalDay.number(of: day, calendar: calendar)
            let when: When = number < today ? .past : number == today ? .today : .future
            let name = LocalDay.text(of: day, calendar: calendar)
            // A mark is shown only on a day that's had one; one somehow
            // dated ahead of today is never drawn.
            return Row(day: name, date: day, level: when == .future ? nil : marks[name], when: when)
        }
    }

    /// The last five days, oldest first and today last, each with its mark
    /// or none: the five bubbles on your journal's cover.
    static func lastFive(marks: [String: Int], now: Date = .now, calendar: Calendar = .current) -> [Int?] {
        let today = calendar.startOfDay(for: now)
        return (-4...0).map { back in
            guard let day = calendar.date(byAdding: .day, value: back, to: today) else { return nil }
            return marks[LocalDay.text(of: day, calendar: calendar)]
        }
    }

    /// How much ink a mark's square takes at the foot of the sheet: five
    /// neutral shades, lightest to darkest, the same ink throughout, with
    /// no colour that could read as good or bad. None is no ink at all.
    static func shade(_ level: Int?) -> Double {
        guard let level, (1...5).contains(level) else { return 0 }
        return [0.14, 0.30, 0.48, 0.66, 0.86][level - 1]
    }

    /// The one line written at the foot, in the hand.
    static let footLine = "the whole month, one mark a day"

    /// What VoiceOver calls each bubble: where it sits in the row, never a
    /// value or a meaning.
    static let bubbles = ["First bubble", "Second bubble", "Third bubble", "Fourth bubble", "Fifth bubble"]

    /// Everything the sheet and the cover's five bubbles say, on screen or
    /// to VoiceOver (a day's own date aside). The unit tests read every
    /// one: no number, no count, no streak, no average, nothing about how
    /// anyone has been.
    static let words: [String] = [
        footLine,
        "Your days this month. Only you see them.",
        "Marked",
        "Not marked",
        "Today. Tap a bubble to mark it; tap it again to take it back.",
        "Turns to that day",
        "Still to come",
        "Your last few days. Only you see them.",
        "Opens this month's sheet",
    ] + bubbles
}
