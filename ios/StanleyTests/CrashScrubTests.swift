import Sentry
import XCTest

/// A report built by the real Sentry SDK, with the app's own configuration
/// (`CrashReporting.configure`), leaves with no installation id, time zone,
/// locale or device hash in it (build 70). Built, not hand-made: if a later
/// Sentry adds one of them somewhere new, this is where it shows.
final class CrashScrubTests: XCTestCase {
    override func tearDown() {
        SentrySDK.close()
        super.tearDown()
    }

    /// The report as Sentry hands it to `beforeSend`, and as the app's
    /// `beforeSend` returns it. Nothing is sent: the spy drops it after.
    private func capture() throws -> (before: [String: Any], after: [String: Any]) {
        var before: [String: Any] = [:]
        var after: [String: Any] = [:]
        let seen = expectation(description: "a report reaches beforeSend")
        SentrySDK.start { options in
            // Nowhere: a key and a host that answer nothing.
            CrashReporting.configure(options, dsn: "https://0000000000000000@127.0.0.1:9/1")
            let scrub = options.beforeSend
            XCTAssertNotNil(scrub, "the app's configuration must set beforeSend")
            options.beforeSend = { event in
                before = event.serialize()
                let kept = scrub?(event)
                after = kept?.serialize() ?? [:]
                seen.fulfill()
                return nil
            }
        }
        SentrySDK.capture(message: "a test report")
        wait(for: [seen], timeout: 10)
        return (before, after)
    }

    private func json(_ object: [String: Any]) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]), as: UTF8.self)
    }

    func testAReportLeavesWithNoIdentifierTimeZoneOrLocale() throws {
        let (before, after) = try capture()
        XCTAssertFalse(after.isEmpty, "the scrub must keep the report, not drop it")

        // What Sentry put in on its own, so the test knows what to look for.
        let user = before["user"] as? [String: Any]
        let installation = try XCTUnwrap(user?["id"] as? String,
            "Sentry no longer sets an installation id; read its source again and update this test")
        let contexts = before["contexts"] as? [String: [String: Any]] ?? [:]
        let hash = contexts["app"]?["device_app_hash"] as? String

        let out = try json(after)
        // None of the three, under any key.
        XCTAssertNil(after["user"])
        XCTAssertFalse(out.contains(installation), "the installation id left the phone")
        XCTAssertFalse(out.contains("\"\(TimeZone.current.identifier)\""), "the time zone left the phone")
        XCTAssertFalse(out.contains("\"\(Locale.current.identifier)\""), "the locale left the phone")
        XCTAssertFalse(out.contains("\"\(Locale.autoupdatingCurrent.identifier)\""), "the locale left the phone")
        if let hash { XCTAssertFalse(out.contains(hash), "the device hash left the phone") }
        for key in ["\"culture\"", "\"locale\"", "\"timezone\"", "\"device_app_hash\""] {
            XCTAssertFalse(out.contains(key), "\(key) left the phone")
        }
        // And the report still says what went wrong and on what.
        XCTAssertNotNil(after["message"] ?? after["logentry"])
        let afterContexts = after["contexts"] as? [String: [String: Any]] ?? [:]
        XCTAssertNotNil(afterContexts["os"])
        XCTAssertNotNil(afterContexts["device"]?["model"])
    }
}
