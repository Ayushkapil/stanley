import XCTest

/// When the Privacy Policy's notice comes up, and what it says (build 70).
final class PolicyNoticeTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "PolicyNoticeTests")
        defaults.removePersistentDomain(forName: "PolicyNoticeTests")
    }

    func testTheNewestRevisionIsThePolicysOwnDate() {
        XCTAssertEqual(PolicyNotice.current.title, Legal.privacyEffective)
    }

    func testRevisionsAreInOrderAndEachSaysSomething() {
        let days = PolicyNotice.revisions.map(\.day)
        XCTAssertEqual(days, days.sorted())
        XCTAssertEqual(Set(days).count, days.count)
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.timeZone = TimeZone(identifier: "UTC")
        for revision in PolicyNotice.revisions {
            XCTAssertFalse(revision.changes.isEmpty)
            format.dateFormat = "yyyy-MM-dd"
            let date = format.date(from: revision.day)
            XCTAssertNotNil(date, revision.day)
            format.dateFormat = "MMMM d, yyyy"
            XCTAssertEqual(date.map(format.string(from:)), revision.title)
        }
    }

    func testSomeoneSignedInFromBeforeIsToldEverythingSinceBuild40() {
        XCTAssertTrue(PolicyNotice.due(acknowledged: nil))
        let told = PolicyNotice.unread(acknowledged: nil)
        XCTAssertEqual(told.map(\.day), PolicyNotice.revisions.filter { $0.day > "2026-11-12" }.map(\.day).reversed())
        XCTAssertEqual(told.first, PolicyNotice.current, "newest first")
    }

    func testAcknowledgingOrSigningInEndsIt() {
        XCTAssertNil(PolicyNotice.acknowledged(in: defaults))
        PolicyNotice.acknowledge(in: defaults)
        XCTAssertEqual(PolicyNotice.acknowledged(in: defaults), PolicyNotice.current.day)
        XCTAssertFalse(PolicyNotice.due(acknowledged: PolicyNotice.acknowledged(in: defaults)))
        XCTAssertTrue(PolicyNotice.unread(acknowledged: PolicyNotice.current.day).isEmpty)
    }

    func testOnlyWhatsNewerThanTheLastAcknowledged() {
        guard PolicyNotice.revisions.count >= 2 else { return }
        let previous = PolicyNotice.revisions[PolicyNotice.revisions.count - 2]
        XCTAssertEqual(PolicyNotice.unread(acknowledged: previous.day), [PolicyNotice.current])
        // A date from a later build (a phone that went back a version) tells nothing.
        XCTAssertFalse(PolicyNotice.due(acknowledged: "2099-01-01"))
    }
}
