import XCTest

/// The heart and the bookmark (build 77): set at once, put back when the
/// server refuses, with the refusal reported. The server is a stub that
/// answers yes or no.
@MainActor
final class TapsTests: XCTestCase {
    private struct Refused: Error, Equatable {}

    /// A stand-in for the server: records what it was asked, and refuses if
    /// told to.
    private final class Server {
        var refuses = false
        var asked: [String] = []
        func send(_ what: String) async throws {
            asked.append(what)
            if refuses { throw Refused() }
        }
    }

    private var server: Server!
    private var surfaced: [Error] = []
    private func surface(_ error: Error) { surfaced.append(error) }

    override func setUp() async throws {
        server = Server()
        surfaced = []
    }

    /// Each of the four, as `AppState` does it: like and unlike on the
    /// likes, hold and let go on the holds. `was` is what the photo showed.
    private func tap(_ taps: Taps, _ what: String, from was: Bool) async -> Bool {
        await taps.set("photo", to: !was, from: was, send: { try await self.server.send(what) }, surface: surface)
    }

    func testRefusedLikeUnlikeHoldAndLetGoAllFlipBack() async {
        for (what, was) in [("like", false), ("unlike", true), ("hold", false), ("let go", true)] {
            let taps = Taps()
            server.refuses = true
            surfaced = []
            let stuck = await tap(taps, what, from: was)
            XCTAssertFalse(stuck, what)
            XCTAssertEqual(taps.value("photo", server: was), was, "\(what) should flip back")
            XCTAssertEqual(surfaced.count, 1, "\(what)'s refusal should be reported")
            XCTAssertTrue(surfaced.first is Refused, what)
            XCTAssertEqual(server.asked.last, what)
        }
    }

    func testAcceptedTapsStick() async {
        for (what, was) in [("like", false), ("unlike", true), ("hold", false), ("let go", true)] {
            let taps = Taps()
            server.refuses = false
            surfaced = []
            let stuck = await tap(taps, what, from: was)
            XCTAssertTrue(stuck, what)
            XCTAssertEqual(taps.value("photo", server: was), !was, what)
            XCTAssertTrue(surfaced.isEmpty, what)
        }
    }

    /// Shown before the server has answered: the tap is the first thing
    /// that changes, not the last.
    func testTheNewStateShowsWhileTheServerIsAsked() async {
        let taps = Taps()
        var seenDuringSend: Bool?
        await taps.set("photo", to: true, from: false, send: {
            seenDuringSend = taps.value("photo", server: false)
        }, surface: surface)
        XCTAssertEqual(seenDuringSend, true)
    }

    /// A fresh Today asked for after the tap replaces it; one asked for
    /// before the tap (and answering after) doesn't undo it.
    func testAFreshTodayTakesOverOnlyFromTapsBeforeIt() async {
        var clock = Date(timeIntervalSince1970: 1_000)
        let taps = Taps(now: { clock })
        let askedBefore = clock.addingTimeInterval(-1)
        await taps.set("photo", to: true, from: false, send: {}, surface: surface)
        taps.forget(before: askedBefore)
        XCTAssertTrue(taps.value("photo", server: false), "an older Today mustn't undo a newer tap")
        clock = clock.addingTimeInterval(5)
        taps.forget(before: clock)
        XCTAssertFalse(taps.value("photo", server: false), "a newer Today is the truth")
    }

    func testSignedOutNothingIsKept() async {
        let taps = Taps()
        await taps.set("photo", to: true, from: false, send: {}, surface: surface)
        taps.forgetAll()
        XCTAssertFalse(taps.value("photo", server: false))
    }
}
