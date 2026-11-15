import Foundation

/// A day's number on the phone's own calendar: whole days since 1 January
/// 2026 to the start of the day `date` falls in, turning at local midnight.
/// What the day's prompts turn by (`DailyPrompt`, `WritingPrompt`).
/// `ordinality(of: .day, in: .era)` turns at midnight UTC, which is seven
/// in the evening in Bloomington, so a prompt changed under people's
/// evening.
enum LocalDay {
    static func number(of date: Date, calendar: Calendar = .current) -> Int {
        let epoch = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1)) ?? date
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: epoch), to: calendar.startOfDay(for: date)).day ?? 0
    }

    /// The day `date` falls in, as the server names days ("2026-11-22"),
    /// on the phone's own calendar. A sealed letter's day was written out
    /// in UTC until build 64: picked in a Bloomington evening it went to
    /// the server as the day after, and before 5:30 AM in Delhi as the
    /// day before.
    static func text(of date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// The start of a day the server names ("2026-11-22") on the phone's
    /// own calendar, so it's shown as that day. Read as UTC, as a sealed
    /// letter's was until build 64, it showed as the day before anywhere
    /// west of Greenwich.
    static func date(_ text: String, calendar: Calendar = .current) -> Date? {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}
