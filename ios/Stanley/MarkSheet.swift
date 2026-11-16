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

    /// The months the sheet can turn to (build 72), oldest first: from the
    /// month the person joined to this one, each as its first day. Nothing
    /// before they joined; nothing after this month. A join date that's
    /// missing, or somehow after now, leaves this month alone.
    static func months(joined: Date?, now: Date = .now, calendar: Calendar = .current) -> [Date] {
        guard let current = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) else { return [] }
        guard let joined, joined <= now,
              var month = calendar.date(from: calendar.dateComponents([.year, .month], from: joined)) else {
            return [current]
        }
        var all: [Date] = []
        while month <= current {
            all.append(month)
            guard let next = calendar.date(byAdding: .month, value: 1, to: month) else { break }
            month = next
        }
        return all
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

    /// What a tap on a bubble in today's row leaves: that bubble, or, on
    /// the one already filled, nothing (the day's mark taken back). Only
    /// today's row can be changed either way (build 66).
    static func afterTap(on at: Int, in row: Row) -> Int?? {
        guard row.takesAMark, (1...5).contains(at) else { return .none }
        return .some(row.level == at ? nil : at)
    }

    // MARK: what VoiceOver says (build 66)
    //
    // The sheet is unlabelled to the eye on purpose; to VoiceOver each
    // bubble is its day and its place along the five ("Sunday 15, 3 of 5"),
    // which is a position on the sheet, not a count of anything.

    /// "Sunday 15": a row's day, as VoiceOver reads it.
    static func spokenDay(_ date: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = calendar.locale ?? .current
        formatter.setLocalizedDateFormatFromTemplate("EEEE")
        let weekday = formatter.string(from: date)
        return weekday + " " + String(calendar.component(.day, from: date))
    }

    /// "Sunday 15, 3 of 5": a bubble, by its day and its place.
    static func spokenBubble(_ date: Date, _ at: Int, calendar: Calendar = .current) -> String {
        "\(spokenDay(date, calendar: calendar)), \(at) of 5"
    }

    /// A day gone by with a page written (build 73): "Thursday 12, go to
    /// this day", a link to that day's page in your book.
    static func spokenGoTo(_ date: Date, calendar: Calendar = .current) -> String {
        "\(spokenDay(date, calendar: calendar)), \(goToDay)"
    }
    static let goToDay = "go to this day"

    /// What a day gone by with no mark reads as.
    static let notMarked = "not marked"

    /// How much ink a mark's square takes at the foot of the sheet: five
    /// neutral shades, lightest to darkest, the same ink throughout, with
    /// no colour that could read as good or bad. None is no ink at all.
    static func shade(_ level: Int?) -> Double {
        guard let level, (1...5).contains(level) else { return 0 }
        return [0.14, 0.30, 0.48, 0.66, 0.86][level - 1]
    }

    /// The one line written at the foot, in the hand.
    static let footLine = "the whole month, one mark a day"

    /// Written under the month's name at the head of the sheet (build 72),
    /// in the hand. A question, not a label: the five bubbles and the
    /// shades under it stay unlabelled.
    static let question = "How was the day?"
    /// The sheet, as VoiceOver names it.
    static let sheetName = "Your days. Only you see them."
    /// A bubble in today's row, after its day and place.
    static let todayHint = "Marks today. On the filled one, takes today's mark back."
    /// The chevrons either side of the month's name.
    static let previousMonth = "Previous month"
    static let nextMonth = "Next month"
    /// The card at the end of the covers (build 72), and the words under it.
    static let daysName = "Your days"
    static let daysLine = "Only you see them"
    static let daysHint = "Opens the month's sheet"
    /// The cover's five bubbles.
    static let lastFewName = "Your last few days. Only you see them."
    static let lastFewHint = "Opens the month's sheet"

    /// Everything the sheet and the cover's five bubbles say, on screen or
    /// to VoiceOver, but a day's date and a bubble's place ("3 of 5",
    /// `spokenBubble`), which the tests hold on their own. The unit tests
    /// read every one: no number, no count, no streak, no average, nothing
    /// about how anyone has been.
    static let words: [String] = [
        footLine, question, sheetName, notMarked, goToDay, todayHint, previousMonth, nextMonth,
        daysName, daysLine, daysHint, lastFewName, lastFewHint,
    ]
}
