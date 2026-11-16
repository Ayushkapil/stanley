import XCTest

/// The opened cover's words (build 76): "Last written" is a date, never a
/// number of pages or days, and the week is five days by their letters.
final class OpenedCoverTests: XCTestCase {
    private func calendar(_ zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }

    private func at(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }

    func testLastWrittenIsADate() {
        let cal = calendar("America/Indiana/Indianapolis")
        let now = at("2026-11-16T21:00:00-05:00")
        XCTAssertEqual(OpenedCoverWords.lastWritten(at("2026-11-16T08:00:00-05:00"), now: now, calendar: cal), "Today")
        XCTAssertEqual(OpenedCoverWords.lastWritten(at("2026-11-15T23:30:00-05:00"), now: now, calendar: cal), "Yesterday")
        XCTAssertEqual(OpenedCoverWords.lastWritten(at("2026-11-12T12:00:00-05:00"), now: now, calendar: cal), "Thursday, November 12")
        XCTAssertEqual(OpenedCoverWords.lastWritten(at("2025-12-30T12:00:00-05:00"), now: now, calendar: cal), "December 30, 2025")
        XCTAssertEqual(OpenedCoverWords.lastWritten(nil, now: now, calendar: cal), "Not yet")
    }

    /// The day turns at the reader's own midnight: 1 AM in Delhi is the
    /// 17th there, so the 16th is yesterday.
    func testTheDayIsTheReadersOwn() {
        let cal = calendar("Asia/Kolkata")
        let now = at("2026-11-17T01:00:00+05:30")
        XCTAssertEqual(OpenedCoverWords.lastWritten(at("2026-11-16T20:00:00+05:30"), now: now, calendar: cal), "Yesterday")
    }

    func testTheWeekIsTheLastFiveDaysTodayLast() {
        let cal = calendar("America/Indiana/Indianapolis")
        let days = OpenedCoverWords.lastFiveDays(now: at("2026-11-16T21:00:00-05:00"), calendar: cal)
        XCTAssertEqual(days.map(\.letter), ["T", "F", "S", "S", "M"])
        XCTAssertEqual(days.last.map { cal.component(.day, from: $0.day) }, 16)
        XCTAssertEqual(days.first.map { cal.component(.day, from: $0.day) }, 12)
    }

    /// Nothing the opened cover says counts anything.
    func testNoWordCounts() {
        let forbidden = ["count", "streak", "average", "pages", "days ago", "times", "total"]
        for word in OpenedCoverWords.words {
            XCTAssertNil(word.rangeOfCharacter(from: .decimalDigits), word)
            for bad in forbidden { XCTAssertFalse(word.lowercased().contains(bad), word) }
        }
        XCTAssertFalse(OpenedCoverWords.automaticPhoto.lowercased().contains("kept"))
    }
}
