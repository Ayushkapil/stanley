import XCTest

/// The rule for when Stanley offers to ask iOS about notifications (build
/// 61). A logic test: `AskToNotify.swift` is compiled into this bundle on
/// its own, without the app.
final class AskToNotifyTests: XCTestCase {
    func testOffersOnlyWhileIOSHasntBeenAskedAndTheSwitchIsOn() {
        let ask = AskToNotify()
        XCTAssertTrue(ask.offers(iosUndecided: true, switchOn: true))
        XCTAssertFalse(ask.offers(iosUndecided: false, switchOn: true), "iOS has its answer")
        XCTAssertFalse(ask.offers(iosUndecided: true, switchOn: false), "Written to You turned off")
    }

    func testContinueIsTheLastOffer() {
        var ask = AskToNotify()
        ask.choseContinue()
        XCTAssertFalse(ask.offers(iosUndecided: true, switchOn: true))
    }

    func testNotNowIsAskedAgainTwiceThenNever() {
        var ask = AskToNotify()
        ask.choseNotNow()
        XCTAssertTrue(ask.offers(iosUndecided: true, switchOn: true), "first re-ask")
        ask.choseNotNow()
        XCTAssertTrue(ask.offers(iosUndecided: true, switchOn: true), "second re-ask")
        ask.choseNotNow()
        XCTAssertFalse(ask.offers(iosUndecided: true, switchOn: true), "then never")
    }

    func testOnlySomethingNewWrittenToYouIsAMoment() {
        var ask = AskToNotify()
        XCTAssertFalse(ask.cameUpon([]), "nothing written to you yet")
        XCTAssertTrue(ask.cameUpon(["letter-1"]))
        XCTAssertFalse(ask.cameUpon(["letter-1"]), "the same letter again isn't a new moment")
        XCTAssertTrue(ask.cameUpon(["letter-1", "page-2"]), "a page for you is")
    }

    func testItIsKeptAcrossLaunches() throws {
        var ask = AskToNotify()
        _ = ask.cameUpon(["letter-1"])
        ask.choseNotNow()
        let kept = try JSONDecoder().decode(AskToNotify.self, from: JSONEncoder().encode(ask))
        XCTAssertEqual(kept, ask)
        var again = kept
        XCTAssertFalse(again.cameUpon(["letter-1"]))
    }

    func testTheLineSaysWhatTheNoticesAreAndNothingElse() {
        XCTAssertEqual(AskToNotify.line, "Stanley only notifies you when someone writes to you directly.")
        XCTAssertNil(AskToNotify.line.rangeOfCharacter(from: .decimalDigits), "no number")
    }
}
