import XCTest

/// The India countdown's flight path (build 74): the clock moved to each
/// leg, and to the day after landing, for a viewer in Bloomington and one in
/// Mumbai. Days turn at the viewer's own midnight (`LocalDay`); legs begin
/// at absolute moments.
final class CountdownJourneyTests: XCTestCase {
    private static let config = """
    {
      "label": "India",
      "start_date": "2026-11-06",
      "target_date": "2026-11-23",
      "target_tz": "America/Chicago",
      "arrives_at": "2026-11-25T02:30:00+05:30",
      "home_until": "2026-11-28T00:00:00+05:30",
      "legs": [
        {"words": "Leaving Bloomington", "at": "2026-11-23T09:00:00-05:00"},
        {"words": "Chicago", "at": "2026-11-23T14:00:00-06:00"},
        {"words": "In the air", "at": "2026-11-23T19:30:00-06:00"},
        {"words": "Dubai", "at": null},
        {"words": "Landed", "at": "2026-11-25T02:30:00+05:30"}
      ]
    }
    """

    private func countdown(_ json: String = config) throws -> Countdown {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(Countdown.self, from: Data(json.utf8))
    }

    private func calendar(_ zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    private let bloomington = "America/Indiana/Indianapolis"
    private let mumbai = "Asia/Kolkata"

    private func at(_ text: String) -> Date { Countdown.moment(text)! }

    private func words(_ moment: String, in zone: String, _ countdown: Countdown) -> String? {
        countdown.journey(at: at(moment), calendar: calendar(zone))?.text
    }

    func testMoreThanAWeekOutIsPlain() throws {
        let journey = try XCTUnwrap(countdown().journey(at: at("2026-11-13T12:00:00-05:00"), calendar: calendar(bloomington)))
        XCTAssertEqual(journey.text, "India in 10 days")
        XCTAssertFalse(journey.close)
        XCTAssertEqual(journey.warmth, 0)
    }

    func testAWeekOrLessIsWrittenAndWarms() throws {
        let c = try countdown()
        let week = try XCTUnwrap(c.journey(at: at("2026-11-16T12:00:00-05:00"), calendar: calendar(bloomington)))
        XCTAssertEqual(week.text, "India in 7 days")
        XCTAssertTrue(week.close)
        XCTAssertEqual(week.words.number, "7")
        let three = try XCTUnwrap(c.journey(at: at("2026-11-20T12:00:00-05:00"), calendar: calendar(bloomington)))
        XCTAssertEqual(three.text, "India in 3 days")
        XCTAssertGreaterThan(week.warmth, 0)
        XCTAssertGreaterThan(three.warmth, week.warmth)
        XCTAssertLessThan(three.warmth, 1)
    }

    func testDaysTurnAtTheViewersOwnMidnight() throws {
        let c = try countdown()
        // 34 hours off at 11 PM on the 21st is still two days on the calendar.
        XCTAssertEqual(words("2026-11-21T23:00:00-05:00", in: bloomington, c), "India in 2 days")
        XCTAssertEqual(words("2026-11-22T00:30:00-05:00", in: bloomington, c), "India in 1 day")
        // The same moment in Mumbai is the 22nd's morning; it leaves at 7:30
        // PM on the 23rd there.
        XCTAssertEqual(words("2026-11-21T23:00:00-05:00", in: mumbai, c), "India in 1 day")
        XCTAssertEqual(words("2026-11-16T12:00:00+05:30", in: mumbai, c), "India in 7 days")
    }

    func testTheLastDayIsHours() throws {
        let c = try countdown()
        XCTAssertEqual(words("2026-11-22T08:00:00-05:00", in: bloomington, c), "India in 1 day")
        XCTAssertEqual(words("2026-11-22T10:00:00-05:00", in: bloomington, c), "India in 23 hours")
        XCTAssertEqual(words("2026-11-23T07:30:00-05:00", in: bloomington, c), "India in 1 hour")
        XCTAssertEqual(words("2026-11-23T08:30:00-05:00", in: bloomington, c), "India in under an hour")
        XCTAssertEqual(words("2026-11-22T22:00:00+05:30", in: mumbai, c), "India in 21 hours")
    }

    func testEachLeg() throws {
        let c = try countdown()
        for zone in [bloomington, mumbai] {
            XCTAssertEqual(words("2026-11-23T09:00:00-05:00", in: zone, c), "Leaving Bloomington")
            XCTAssertEqual(words("2026-11-23T13:59:00-06:00", in: zone, c), "Leaving Bloomington")
            XCTAssertEqual(words("2026-11-23T14:00:00-06:00", in: zone, c), "Chicago")
            XCTAssertEqual(words("2026-11-23T19:30:00-06:00", in: zone, c), "In the air")
            // No Dubai time: "In the air" runs through to landing.
            XCTAssertEqual(words("2026-11-24T08:00:00+04:00", in: zone, c), "In the air")
            XCTAssertEqual(words("2026-11-25T02:29:00+05:30", in: zone, c), "In the air")
            XCTAssertEqual(words("2026-11-25T02:30:00+05:30", in: zone, c), "Landed")
        }
    }

    func testTheDubaiSlotFilledIsALegOfItsOwn() throws {
        let filled = Self.config.replacingOccurrences(
            of: "\"Dubai\", \"at\": null", with: "\"Dubai\", \"at\": \"2026-11-24T08:00:00+04:00\"")
        let c = try countdown(filled)
        XCTAssertEqual(c.stops.map(\.words), ["Leaving Bloomington", "Chicago", "In the air", "Dubai", "Landed"])
        XCTAssertEqual(words("2026-11-24T07:59:00+04:00", in: bloomington, c), "In the air")
        XCTAssertEqual(words("2026-11-24T08:00:00+04:00", in: bloomington, c), "Dubai")
    }

    func testLandedHoldsADayAndThenTheStripGoes() throws {
        let c = try countdown()
        let landed = try XCTUnwrap(c.journey(at: at("2026-11-25T02:30:00+05:30"), calendar: calendar(bloomington)))
        XCTAssertTrue(landed.landed)
        XCTAssertEqual(landed.progress, 1)
        XCTAssertNotNil(c.journey(at: at("2026-11-26T02:29:00+05:30"), calendar: calendar(mumbai)))
        XCTAssertNil(c.journey(at: at("2026-11-26T02:30:00+05:30"), calendar: calendar(mumbai)))
        // The day after landing, in either zone.
        XCTAssertNil(c.journey(at: at("2026-11-26T12:00:00+05:30"), calendar: calendar(mumbai)))
        XCTAssertNil(c.journey(at: at("2026-11-25T18:00:00-05:00"), calendar: calendar(bloomington)))
    }

    /// Every half hour from the first day to well after landing, in both
    /// zones: never a negative number, the plane only ever moving forward.
    func testNeverNegativeAndAlwaysForward() throws {
        let c = try countdown()
        for zone in [bloomington, mumbai] {
            var moment = at("2026-11-06T00:00:00-05:00")
            let end = at("2026-11-28T00:00:00+05:30")
            var last = -1.0
            var gone = false
            while moment < end {
                if let journey = c.journey(at: moment, calendar: calendar(zone)) {
                    XCTAssertFalse(gone, "came back after it had gone")
                    XCTAssertFalse(journey.text.contains("-"), journey.text)
                    switch journey.stage {
                    case .days(let days): XCTAssertGreaterThanOrEqual(days, 1)
                    case .hours(let hours): XCTAssertTrue((0..<24).contains(hours))
                    case .leg(let index): XCTAssertTrue(journey.stops.indices.contains(index))
                    }
                    XCTAssertGreaterThanOrEqual(journey.progress, last)
                    XCTAssertTrue((0...1).contains(journey.progress))
                    last = journey.progress
                } else if last >= 0 {
                    gone = true
                }
                moment.addTimeInterval(1_800)
            }
            XCTAssertTrue(gone)
        }
    }

    func testTheStripMarksTheJourneyAlongItsLastPart() throws {
        let c = try countdown()
        let journey = try XCTUnwrap(c.journey(at: at("2026-11-16T12:00:00-05:00"), calendar: calendar(bloomington)))
        XCTAssertEqual(journey.marks.first, Countdown.waitShare)
        XCTAssertEqual(journey.marks.last, 1)
        XCTAssertEqual(journey.marks, journey.marks.sorted())
        XCTAssertLessThan(journey.progress, Countdown.waitShare)
        let air = try XCTUnwrap(c.journey(at: at("2026-11-24T06:00:00-06:00"), calendar: calendar(bloomington)))
        XCTAssertGreaterThan(air.progress, air.marks[2])
        XCTAssertLessThan(air.progress, 1)
    }

    func testAConfigWithoutLegsStillHasAJourney() throws {
        let old = """
        {"label": "India", "start_date": "2026-11-06", "target_date": "2026-11-23",
         "target_tz": "America/Chicago", "arrives_at": "2026-11-25T02:30:00+05:30"}
        """
        let c = try countdown(old)
        XCTAssertEqual(c.stops.map(\.words), ["On the way", "Landed"])
        XCTAssertEqual(words("2026-11-24T06:00:00-06:00", in: bloomington, c), "On the way")
    }
}

extension CountdownJourneyTests {
    func testTheStripSpeaksAsOneWithTheLegItsOn() throws {
        let c = try countdown()
        let cal = calendar("America/Indiana/Indianapolis")
        let before = try XCTUnwrap(c.journey(at: Countdown.moment("2026-11-16T12:00:00-05:00")!, calendar: cal))
        XCTAssertEqual(before.spoken(reminder: "One week. ONE WEEK."), "One week. ONE WEEK. India in 7 days")
        XCTAssertEqual(before.spoken(reminder: "Pack"), "Pack. India in 7 days")
        let air = try XCTUnwrap(c.journey(at: Countdown.moment("2026-11-24T06:00:00-06:00")!, calendar: cal))
        XCTAssertEqual(air.spoken(reminder: nil), "India. In the air")
    }
}
