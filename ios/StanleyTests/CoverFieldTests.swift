import XCTest

/// The words on a journal's warm field (build 69): near-black on a light
/// field, the off-white on a dark one, chosen from the field's luminance,
/// across every field the generator can make.
final class CoverFieldTests: XCTestCase {
    /// The generator's whole range, corner to corner and through the
    /// middle: hue, saturation and brightness each at eleven steps.
    private var everyField: [CoverField.RGB] {
        let steps = (0...10).map { Double($0) / 10 }
        return steps.flatMap { h in steps.flatMap { s in steps.map { v in
            CoverField.rgb(hue: 0.03 + h * 0.0899, saturation: 0.5 + s * 0.18, brightness: 0.78 + v * 0.12)
        } } }
    }

    /// The lightest field it makes (amber, least saturated, brightest),
    /// and the darkest (red, most saturated, least bright).
    private let lightest = CoverField.rgb(hue: 0.1199, saturation: 0.5, brightness: 0.9)
    private let darkest = CoverField.rgb(hue: 0.03, saturation: 0.68, brightness: 0.78)

    private func worst(_ warmth: CoverField.RGB, dark: Bool, ink: CoverField.RGB, alpha: Double = 1,
                       area: [(x: Double, y: Double)], scrims: Bool) -> Double {
        area.map { point in
            let under = CoverField.colour(warmth: warmth, dark: dark, x: point.x, y: point.y, scrims: scrims)
            return under.contrast(with: under.under(ink, alpha))
        }.min() ?? 0
    }

    func testEveryDaylightFieldTakesNearBlackAndItReads() {
        for warmth in everyField + [lightest, darkest] {
            XCTAssertEqual(CoverField.ink(warmth: warmth, dark: false), .dark)
            // The title, large in the hand: well over 4.5:1 everywhere it sits.
            XCTAssertGreaterThan(worst(warmth, dark: false, ink: CoverField.nearBlack,
                                       area: CoverField.titleArea, scrims: false), 7)
            // Small capitals and the foot's line, at 85%: 4.5:1 or more.
            XCTAssertGreaterThanOrEqual(worst(warmth, dark: false, ink: CoverField.nearBlack, alpha: CoverField.darkLabel,
                                              area: CoverField.labelArea, scrims: false), 4.5)
        }
    }

    func testTheOffWhiteWasWhatFailedByDay() {
        // What build 68 drew: the off-white title with the scrims over the
        // lightest field. Under 2:1.
        XCTAssertLessThan(worst(lightest, dark: false, ink: CoverField.offWhite,
                                area: CoverField.titleArea, scrims: true), 2)
    }

    func testEveryNightFieldTakesTheOffWhiteAndItReads() {
        for warmth in everyField + [lightest, darkest] {
            XCTAssertEqual(CoverField.ink(warmth: warmth, dark: true), .light)
            // Large text: 3:1, even under the sheen in the top left.
            XCTAssertGreaterThanOrEqual(worst(warmth, dark: true, ink: CoverField.offWhite,
                                              area: CoverField.titleArea, scrims: true), 3)
        }
    }

    func testTheInkFollowsTheLightNotTheScreen() {
        // Whatever the room: a white field asks for near-black, a black one
        // for the off-white.
        let white = CoverField.RGB(0xFFFFFF), black = CoverField.RGB(0x000000)
        XCTAssertGreaterThan(white.contrast(with: CoverField.nearBlack), white.contrast(with: CoverField.offWhite))
        XCTAssertGreaterThan(black.contrast(with: CoverField.offWhite), black.contrast(with: CoverField.nearBlack))
        XCTAssertEqual(CoverField.ink(warmth: white, dark: false), .dark)
    }

    func testAJournalsWarmthIsTheSameEveryTime() {
        let (h, s, v) = CoverField.warmthHSB("climbing-club")
        XCTAssertEqual(h, 0.07401, accuracy: 1e-9)
        XCTAssertEqual(s, 0.635, accuracy: 1e-9)
        XCTAssertEqual(v, 0.804, accuracy: 1e-9)
        XCTAssertEqual(CoverField.ink(for: "climbing-club", dark: false), .dark)
        XCTAssertEqual(CoverField.ink(for: "climbing-club", dark: true), .light)
    }

    /// The cover colours a journal with no photo can be given (build 76):
    /// whichever ink each field asks for, by day and by night and whatever
    /// the journal's own warmth over it, the words read.
    func testEveryCoverColourTakesAnInkThatReads() {
        let warmths = [lightest, darkest, CoverField.rgb(hue: 0.075, saturation: 0.59, brightness: 0.84)]
        for swatch in CoverField.Swatch.allCases {
            for dark in [false, true] {
                for warmth in warmths {
                    let ink = CoverField.ink(warmth: warmth, dark: dark, swatch: swatch)
                    func worst(_ colour: CoverField.RGB, alpha: Double = 1, area: [(x: Double, y: Double)]) -> Double {
                        area.map { point in
                            let under = CoverField.colour(warmth: warmth, dark: dark, x: point.x, y: point.y,
                                                          scrims: ink == .light, swatch: swatch)
                            return under.contrast(with: under.under(colour, alpha))
                        }.min() ?? 0
                    }
                    let label = "\(swatch.name), \(dark ? "night" : "day")"
                    if ink == .dark {
                        XCTAssertGreaterThanOrEqual(worst(CoverField.nearBlack, area: CoverField.titleArea), 4.5, label)
                        XCTAssertGreaterThanOrEqual(worst(CoverField.nearBlack, alpha: CoverField.darkLabel,
                                                          area: CoverField.labelArea), 4.5, label)
                    } else {
                        // Large text in the hand: 3:1, under the sheen too.
                        XCTAssertGreaterThanOrEqual(worst(CoverField.offWhite, area: CoverField.titleArea), 3, label)
                    }
                }
            }
        }
        // Caramel is the field every journal starts with.
        XCTAssertEqual(CoverField.ground(dark: false, swatch: .caramel), CoverField.ground(dark: false))
        XCTAssertEqual(CoverField.ground(dark: true, swatch: nil), CoverField.ground(dark: true))
    }

    func testContrastIsWCAGs() {
        XCTAssertEqual(CoverField.RGB(0xFFFFFF).contrast(with: CoverField.RGB(0x000000)), 21, accuracy: 0.01)
        XCTAssertEqual(CoverField.RGB(0x767676).contrast(with: CoverField.RGB(0xFFFFFF)), 4.54, accuracy: 0.01)
    }
}
