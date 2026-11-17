import XCTest

/// A photo waiting to go up is its taker's alone (build 77): signing out
/// and letting someone else sign in on the phone never sends it, or shows
/// it, as theirs.
@MainActor
final class OfflineQueueTests: XCTestCase {
    private var queue: OfflineQueue!

    override func setUp() async throws {
        queue = OfflineQueue()
        for item in queue.items { queue.clear(item) }
    }

    override func tearDown() async throws {
        for item in queue.items { queue.clear(item) }
    }

    func testAWaitingPhotoIsOnlyItsTakersToSeeOrSend() {
        queue.owner = "maya"
        queue.enqueue(jpeg: Data([0xFF, 0xD8]), caption: "hi", location: nil, tagged: [], circleId: "floor")
        XCTAssertNotNil(queue.pending(in: "floor"))
        XCTAssertTrue(queue.isHoldingTheDay(in: "floor"))

        // Maya signs out; Ruby, in the same circle, signs in on the phone.
        queue.owner = nil
        XCTAssertTrue(queue.mine.isEmpty)
        queue.owner = "ruby"
        XCTAssertNil(queue.pending(in: "floor"))
        XCTAssertFalse(queue.isHoldingTheDay(in: "floor"))
        XCTAssertTrue(queue.mine.isEmpty, "Ruby would send Maya's photo as hers")

        // Maya back: it's still hers, waiting.
        queue.owner = "maya"
        XCTAssertEqual(queue.mine.count, 1)
        XCTAssertEqual(queue.pending(in: "floor")?.caption, "hi")
    }

    func testSignedOutNothingIsAnyonesToSend() {
        queue.owner = "maya"
        queue.enqueue(jpeg: Data([0xFF, 0xD8]), caption: nil, location: nil, tagged: [], circleId: "floor")
        queue.owner = nil
        XCTAssertNil(queue.pending(in: "floor"))
        XCTAssertTrue(queue.mine.isEmpty)
        XCTAssertEqual(queue.items.count, 1, "kept on the phone for its owner, never thrown away")
    }

    func testOneQueuedByAnOlderBuildGoesToTheNextToSignIn() throws {
        queue.owner = nil
        let item = queue.enqueue(jpeg: Data([0xFF, 0xD8]), caption: nil, location: nil, tagged: [], circleId: "floor")
        XCTAssertNil(item.ownerId)
        queue.owner = "maya"
        XCTAssertEqual(queue.mine.map(\.id), [item.id])
        // And it stays hers.
        queue.owner = "ruby"
        XCTAssertTrue(queue.mine.isEmpty)
    }
}
