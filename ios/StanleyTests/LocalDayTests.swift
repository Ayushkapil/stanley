import XCTest

/// A day written out and read back on the phone's own calendar (build 64):
/// a sealed letter's day went to the server, and was shown, in UTC.
final class LocalDayTests: XCTestCase {
    private func calendar(_ zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    private func utc(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    /// The day a date shows as on `calendar`, the way the envelope prints it.
    private func shown(_ date: Date, on calendar: Calendar) -> Int {
        calendar.component(.day, from: date)
    }

    func testABloomingtonEveningIsStillItsOwnDay() {
        let indy = calendar("America/Indiana/Indianapolis")
        // 8 PM EST on the 15th is the 16th in UTC.
        XCTAssertEqual(LocalDay.text(of: utc(16, 1), calendar: indy), "2026-11-15")
        // The 22nd reads back as the 22nd, not the evening of the 21st.
        let day = LocalDay.date("2026-11-22", calendar: indy)!
        XCTAssertEqual(shown(day, on: indy), 22)
        XCTAssertEqual(day, indy.startOfDay(for: day))
    }

    func testADelhiSmallHourIsAlreadyItsOwnDay() {
        let delhi = calendar("Asia/Kolkata")
        // 3 AM IST on the 16th is still the 15th in UTC.
        XCTAssertEqual(LocalDay.text(of: utc(15, 21, 30), calendar: delhi), "2026-11-16")
        XCTAssertEqual(shown(LocalDay.date("2026-11-23", calendar: delhi)!, on: delhi), 23)
    }

    func testTheNightTheClocksWentBack() {
        let indy = calendar("America/Indiana/Indianapolis")
        // 11 PM EST on 1 November, a day 25 hours long, is the 2nd in UTC.
        XCTAssertEqual(LocalDay.text(of: utc(2, 4), calendar: indy), "2026-11-01")
        // Read back, each day is its own midnight on either side of the change.
        let first = LocalDay.date("2026-11-01", calendar: indy)!
        let second = LocalDay.date("2026-11-02", calendar: indy)!
        XCTAssertEqual(second.timeIntervalSince(first), 25 * 3600)
        XCTAssertEqual(LocalDay.text(of: first, calendar: indy), "2026-11-01")
        XCTAssertEqual(LocalDay.text(of: second, calendar: indy), "2026-11-02")
    }

    func testNotADay() {
        XCTAssertNil(LocalDay.date("soon"))
        XCTAssertNil(LocalDay.date("2026-11"))
    }
}
