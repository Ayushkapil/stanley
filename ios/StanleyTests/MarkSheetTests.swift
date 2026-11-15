import XCTest

/// The answer sheet's rules (build 65): only today's row takes a mark,
/// today being the phone's own day; a day gone by is never filled in; the
/// days to come take nothing; and nothing it says counts anything.
final class MarkSheetTests: XCTestCase {
    private func calendar(_ zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    private func utc(_ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    private func today(_ rows: [MarkSheet.Row]) -> [String] {
        rows.filter(\.takesAMark).map(\.day)
    }

    func testABloomingtonEveningMarksItsOwnDayNotUTCs() {
        let indy = calendar("America/Indiana/Indianapolis")
        let now = utc(11, 16, 1) // 8 PM EST on the 15th; the 16th in UTC
        let rows = MarkSheet.rows(month: now, marks: [:], now: now, calendar: indy)
        XCTAssertEqual(today(rows), ["2026-11-15"])
        XCTAssertEqual(rows.first { $0.day == "2026-11-16" }?.when, .future)
        XCTAssertEqual(rows.first { $0.day == "2026-11-14" }?.when, .past)
    }

    func testADelhiSmallHourMarksItsOwnDayNotUTCs() {
        let delhi = calendar("Asia/Kolkata")
        let now = utc(11, 15, 21, 30) // 3 AM IST on the 16th; the 15th in UTC
        let rows = MarkSheet.rows(month: now, marks: [:], now: now, calendar: delhi)
        XCTAssertEqual(today(rows), ["2026-11-16"])
        XCTAssertEqual(rows.first { $0.day == "2026-11-15" }?.when, .past)
    }

    func testTheNightTheClocksWentBackIsOneDay() {
        let indy = calendar("America/Indiana/Indianapolis")
        // 1 AM EDT and 11 PM EST on 1 November are the same day.
        for moment in [utc(11, 1, 5), utc(11, 2, 4)] {
            XCTAssertEqual(today(MarkSheet.rows(month: moment, marks: [:], now: moment, calendar: indy)), ["2026-11-01"])
        }
        // Midnight EST: the 2nd.
        let next = utc(11, 2, 5)
        XCTAssertEqual(today(MarkSheet.rows(month: next, marks: [:], now: next, calendar: indy)), ["2026-11-02"])
    }

    func testEveryDayOfTheMonthIsARowAndOnlyTodayTakesAMark() {
        let indy = calendar("America/Indiana/Indianapolis")
        let now = utc(11, 15, 17)
        let marks = ["2026-11-03": 2, "2026-11-15": 4, "2026-11-20": 5]
        let rows = MarkSheet.rows(month: now, marks: marks, now: now, calendar: indy)
        XCTAssertEqual(rows.count, 30)
        XCTAssertEqual(rows.first?.day, "2026-11-01")
        XCTAssertEqual(rows.last?.day, "2026-11-30")
        XCTAssertEqual(rows.filter(\.takesAMark).count, 1)
        // A day gone by keeps what it had, and takes nothing.
        let third = rows.first { $0.day == "2026-11-03" }!
        XCTAssertEqual(third.level, 2)
        XCTAssertFalse(third.takesAMark)
        let missed = rows.first { $0.day == "2026-11-04" }!
        XCTAssertNil(missed.level)
        XCTAssertFalse(missed.takesAMark)
        XCTAssertEqual(rows.first { $0.day == "2026-11-15" }?.level, 4)
        // A day to come is drawn empty, whatever came back for it.
        let later = rows.first { $0.day == "2026-11-20" }!
        XCTAssertEqual(later.when, .future)
        XCTAssertNil(later.level)
        XCTAssertFalse(later.takesAMark)
    }

    func testAMonthGoneByTakesNoMark() {
        let indy = calendar("America/Indiana/Indianapolis")
        let now = utc(11, 15, 17)
        let october = MarkSheet.rows(month: utc(10, 10, 12), marks: [:], now: now, calendar: indy)
        XCTAssertEqual(october.count, 31)
        XCTAssertTrue(october.allSatisfy { $0.when == .past && !$0.takesAMark })
    }

    func testTheLastFiveDaysEndOnTodayOnThePhonesCalendar() {
        let delhi = calendar("Asia/Kolkata")
        let now = utc(11, 15, 21, 30) // the 16th in Delhi
        let marks = ["2026-11-12": 1, "2026-11-14": 3, "2026-11-16": 5, "2026-11-11": 2]
        XCTAssertEqual(MarkSheet.lastFive(marks: marks, now: now, calendar: delhi), [1, nil, 3, nil, 5])
    }

    func testFiveNeutralShadesLightToDarkAndNoneIsNoInk() {
        let shades = (1...5).map { MarkSheet.shade($0) }
        XCTAssertEqual(shades, shades.sorted())
        XCTAssertEqual(Set(shades).count, 5)
        XCTAssertTrue(shades.allSatisfy { $0 > 0 && $0 < 1 })
        XCTAssertEqual(MarkSheet.shade(nil), 0)
        XCTAssertEqual(MarkSheet.shade(0), 0)
        XCTAssertEqual(MarkSheet.shade(6), 0)
    }

    func testNothingTheSheetSaysCountsOrJudges() {
        let refused = [
            "streak", "average", "count", "total", "in a row", "trend", "best", "worst", "good", "bad",
            "mood", "score", "missed", "don't forget", "keep it up", "you've been", "week", "%",
        ]
        XCTAssertFalse(MarkSheet.words.isEmpty)
        for line in MarkSheet.words {
            XCTAssertNil(line.rangeOfCharacter(from: .decimalDigits), line)
            for word in refused {
                XCTAssertFalse(line.lowercased().contains(word), "\(line) says \(word)")
            }
        }
        XCTAssertEqual(MarkSheet.footLine, "the whole month, one mark a day")
    }

    // MARK: VoiceOver (build 66)

    private func english(_ zone: String) -> Calendar {
        var calendar = self.calendar(zone)
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }

    func testEachBubbleIsItsDayAndItsPlace() {
        let indy = english("America/Indiana/Indianapolis")
        let now = utc(11, 16, 1) // 8 PM EST on Sunday the 15th
        XCTAssertEqual(MarkSheet.spokenDay(now, calendar: indy), "Sunday 15")
        XCTAssertEqual(MarkSheet.spokenBubble(now, 3, calendar: indy), "Sunday 15, 3 of 5")
        XCTAssertEqual(
            (1...5).map { MarkSheet.spokenBubble(now, $0, calendar: indy) },
            ["Sunday 15, 1 of 5", "Sunday 15, 2 of 5", "Sunday 15, 3 of 5", "Sunday 15, 4 of 5", "Sunday 15, 5 of 5"]
        )
        // Delhi's small hour is already Monday the 16th there.
        XCTAssertEqual(MarkSheet.spokenBubble(utc(11, 15, 21, 30), 1, calendar: english("Asia/Kolkata")), "Monday 16, 1 of 5")
    }

    func testAnEmptyDayGoneByReadsAsNotMarked() {
        XCTAssertEqual(MarkSheet.notMarked, "not marked")
    }

    func testOnlyAPlaceAlongTheFiveIsANumberVoiceOverSays() {
        // The one number spoken is a bubble's place; nothing totals,
        // counts or compares, and no word judges.
        let indy = english("America/Indiana/Indianapolis")
        let spoken = MarkSheet.spokenBubble(utc(11, 16, 1), 4, calendar: indy)
        XCTAssertTrue(spoken.hasSuffix(", 4 of 5"))
        let words = spoken.lowercased()
        for word in ["streak", "average", "count", "total", "good", "bad", "mood", "score"] {
            XCTAssertFalse(words.contains(word), word)
        }
    }

    // MARK: taking a mark back (build 66)

    func testATapOnTheFilledBubbleTakesTodaysMarkBack() {
        let indy = calendar("America/Indiana/Indianapolis")
        let now = utc(11, 15, 17)
        let rows = MarkSheet.rows(month: now, marks: ["2026-11-15": 3, "2026-11-14": 2], now: now, calendar: indy)
        let today = rows.first { $0.day == "2026-11-15" }!
        // The filled one: nothing left.
        XCTAssertEqual(MarkSheet.afterTap(on: 3, in: today), .some(nil))
        // Another: that one instead.
        XCTAssertEqual(MarkSheet.afterTap(on: 5, in: today), .some(5))
        // Past and future rows take neither a mark nor a mark taken back.
        let yesterday = rows.first { $0.day == "2026-11-14" }!
        XCTAssertNil(MarkSheet.afterTap(on: 2, in: yesterday) as Int??)
        XCTAssertNil(MarkSheet.afterTap(on: 4, in: yesterday) as Int??)
        let tomorrow = rows.first { $0.day == "2026-11-16" }!
        XCTAssertNil(MarkSheet.afterTap(on: 1, in: tomorrow) as Int??)
        // Not a bubble.
        XCTAssertNil(MarkSheet.afterTap(on: 6, in: today) as Int??)
    }

    func testTakingBackIsTodayOnThePhonesOwnCalendar() {
        // In a Bloomington evening (the 16th in UTC) the 15th can still be
        // cleared, and UTC's 16th can't.
        let indy = calendar("America/Indiana/Indianapolis")
        let now = utc(11, 16, 1)
        let rows = MarkSheet.rows(month: now, marks: ["2026-11-15": 2], now: now, calendar: indy)
        XCTAssertEqual(MarkSheet.afterTap(on: 2, in: rows.first { $0.day == "2026-11-15" }!), .some(nil))
        XCTAssertNil(MarkSheet.afterTap(on: 2, in: rows.first { $0.day == "2026-11-16" }!) as Int??)
    }
}
