import XCTest

/// The suggestion over a new page (build 63): which one, and which next.
/// A logic test: `WritingPrompts.swift` is compiled into this bundle alone.
final class WritingPromptTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Indiana/Indianapolis")!
        return calendar
    }

    private func day(_ text: String) -> Date {
        let parts = text.split(separator: "-").map { Int($0)! }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 9))!
    }

    func testTheSameAllDayAndTheNextTomorrow() {
        let morning = day("2026-11-15")
        let night = morning.addingTimeInterval(14 * 3600)
        let first = WritingPrompt.first(on: morning, calendar: calendar)
        XCTAssertNotNil(first)
        XCTAssertEqual(first, WritingPrompt.first(on: night, calendar: calendar))
        let tomorrow = WritingPrompt.first(on: day("2026-11-16"), calendar: calendar)
        XCTAssertEqual(tomorrow, (first! + 1) % WritingPrompt.all.count)
    }

    func testAnotherIsADifferentOneAndComesRoundAgain() {
        let count = WritingPrompt.all.count
        var seen: Set<Int> = []
        var at = 0
        for _ in 0..<count {
            seen.insert(at)
            let next = WritingPrompt.after(at)!
            XCTAssertNotEqual(next, at)
            at = next
        }
        XCTAssertEqual(seen.count, count, "every suggestion before any comes again")
        XCTAssertEqual(at, 0, "and round to the first")
    }

    func testOnlyWhatFitsOnItsLine() {
        let fits: (String) -> Bool = { $0.count <= 45 }
        let first = WritingPrompt.first(on: day("2026-11-15"), calendar: calendar, fits: fits)!
        XCTAssertTrue(fits(WritingPrompt.all[first]))
        var at = first
        for _ in 0..<WritingPrompt.all.count {
            at = WritingPrompt.after(at, fits: fits)!
            XCTAssertTrue(fits(WritingPrompt.all[at]), WritingPrompt.all[at])
        }
    }

    func testNothingOfferedWhenNothingFits() {
        XCTAssertNil(WritingPrompt.first(fits: { _ in false }))
        XCTAssertNil(WritingPrompt.after(3, fits: { _ in false }))
    }

    func testTheOnlyOneThatFitsIsOfferedAgain() {
        let only = WritingPrompt.all[7]
        XCTAssertEqual(WritingPrompt.after(7, fits: { $0 == only }), 7)
    }

    func testSuggestionsAreWordsAndOneLineEach() {
        XCTAssertEqual(WritingPrompt.all.count, 40)
        XCTAssertEqual(Set(WritingPrompt.all).count, 40)
        for words in WritingPrompt.all {
            XCTAssertFalse(words.contains("\n"))
            XCTAssertNil(words.rangeOfCharacter(from: .decimalDigits), "no number in a suggestion: \(words)")
        }
    }
}
