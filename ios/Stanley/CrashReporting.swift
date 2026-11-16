import Foundation
import Sentry

/// How Sentry is set up, in one place, so the app and the test that holds
/// it (`CrashScrubTests`) start it the same way. Crash capture only: no
/// sessions, no tracing, no screenshots, no Sentry trail of its own, and no
/// identity of any kind (`CrashScrub`).
enum CrashReporting {
    static func configure(_ options: Options, dsn: String) {
        options.dsn = dsn
        options.enableAutoSessionTracking = false  // sessions are usage data
        options.enableAppHangTracking = false      // crashes only, no near-miss noise
        options.attachScreenshot = false           // never ship a user's photo
        options.attachViewHierarchy = false
        options.tracesSampleRate = 0               // no performance telemetry
        // The production audit: the only trail is Stanley's own (`Trail`),
        // fixed words with nothing personal in them. Sentry's automatic one
        // records taps, screens and every request's URL, and a URL can carry
        // a username or an id.
        options.enableAutoBreadcrumbTracking = false
        options.enableNetworkBreadcrumbs = false
        // A server's 5xx is a server problem, logged on the server; reporting
        // it from phones would send request URLs too.
        options.enableCaptureFailedRequests = false
        options.maxBreadcrumbs = 30
        options.sendDefaultPii = false
        // Last, and it must stay: every report loses what could tell one
        // phone from another, or where it is, before it leaves.
        options.beforeSend = { CrashScrub.scrub($0) }
    }
}

/// What every report loses before it leaves the phone (build 70). Sentry
/// 8.58.4, read at the source, adds three things on its own that the Privacy
/// Policy doesn't allow ("no identifier"):
/// - `user.id`, a random installation id it keeps in a file, set whenever
///   the app sets no user (`SentryClient.setUserIdIfNoUserSet`);
/// - the phone's time zone and locale (`contexts.culture`, and
///   `contexts.device.locale`);
/// - `contexts.app.device_app_hash`, a hash of iOS's identifier for the
///   vendor: the same on this phone for as long as Stanley is installed.
/// `beforeSend` is the last place the app sees a report: Sentry runs it
/// after it has added all three, and nothing after it adds more but session
/// replay, which is off. Any value anywhere in the contexts, tags or extras
/// that is the installation id, the time zone or the locale goes too, so a
/// field a later Sentry adds under another name doesn't carry them out.
enum CrashScrub {
    static func scrub(_ event: Event) -> Event {
        var named = Set([
            TimeZone.current.identifier, TimeZone.autoupdatingCurrent.identifier,
            Locale.current.identifier, Locale.autoupdatingCurrent.identifier,
        ])
        if let installation = event.user?.userId { named.insert(installation) }
        event.user = nil

        if var contexts = event.context {
            contexts["culture"] = nil
            for key in Array(contexts.keys) {
                guard var values = contexts[key] else { continue }
                for drop in ["locale", "timezone", "time_zone", "device_app_hash"] { values[drop] = nil }
                values = values.filter { !names($0.value, named) }
                contexts[key] = values
            }
            event.context = contexts
        }
        event.tags = event.tags?.filter { !named.contains($0.value) }
        event.extra = event.extra?.filter { !names($0.value, named) }
        return event
    }

    /// Whether a value is, or holds, one of these strings.
    private static func names(_ value: Any, _ named: Set<String>) -> Bool {
        if let text = value as? String { return named.contains(text) }
        if let list = value as? [Any] { return list.contains { names($0, named) } }
        if let map = value as? [String: Any] { return map.values.contains { names($0, named) } }
        return false
    }
}
