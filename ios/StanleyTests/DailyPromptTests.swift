import XCTest

/// The capture's daily whisper (build 64): it turns at the phone's own
/// midnight, not at midnight UTC (seven in the evening in Bloomington).
final class DailyPromptTests: XCTestCase {
    private func calendar(_ zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    private func at(_ calendar: Calendar, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    func testTheSameAllEveningInBloomington() {
        let indy = calendar("America/Indiana/Indianapolis")
        let morning = DailyPrompt.forToday(at(indy, 15, 0, 1), calendar: indy)
        // 6:59 PM and 7:01 PM sit either side of midnight UTC.
        XCTAssertEqual(morning, DailyPrompt.forToday(at(indy, 15, 18, 59), calendar: indy))
        XCTAssertEqual(morning, DailyPrompt.forToday(at(indy, 15, 19, 1), calendar: indy))
        XCTAssertEqual(morning, DailyPrompt.forToday(at(indy, 15, 23, 59), calendar: indy))
    }

    func testTheNextAtLocalMidnight() {
        for zone in ["America/Indiana/Indianapolis", "Asia/Kolkata", "Pacific/Auckland", "UTC"] {
            let cal = calendar(zone)
            let today = DailyPrompt.forToday(at(cal, 15, 23, 59), calendar: cal)
            let tomorrow = DailyPrompt.forToday(at(cal, 16, 0, 1), calendar: cal)
            XCTAssertNotEqual(today, tomorrow, zone)
            let i = DailyPrompt.all.firstIndex(of: today)!
            XCTAssertEqual(tomorrow, DailyPrompt.all[(i + 1) % DailyPrompt.all.count], zone)
        }
    }

    func testTheCircleSharesItWhereverItsMembersAre() {
        // Two phones, each at noon on their own 15 November, read the same.
        let indy = calendar("America/Indiana/Indianapolis"), delhi = calendar("Asia/Kolkata")
        XCTAssertEqual(DailyPrompt.forToday(at(indy, 15, 12), calendar: indy),
                       DailyPrompt.forToday(at(delhi, 15, 12), calendar: delhi))
    }

    func testTheDayCountsFromItsStart() {
        let indy = calendar("America/Indiana/Indianapolis")
        XCTAssertEqual(LocalDay.number(of: indy.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 23))!, calendar: indy), 0)
        XCTAssertEqual(LocalDay.number(of: at(indy, 15, 23, 59), calendar: indy) + 1,
                       LocalDay.number(of: at(indy, 16, 0, 1), calendar: indy))
        // Across the clocks going back (1 November in Indiana): still one day.
        XCTAssertEqual(LocalDay.number(of: at(indy, 1, 12), calendar: indy) + 1,
                       LocalDay.number(of: at(indy, 2, 12), calendar: indy))
    }
}
