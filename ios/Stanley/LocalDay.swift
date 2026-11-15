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
}
