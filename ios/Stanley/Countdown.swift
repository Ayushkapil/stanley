import Foundation

/// Something one circle is counting toward (build 35), as the server sends it
/// with the circle on screen: a flag set by hand on a single circle
/// (`scripts/set_countdown.py`), nil for every other. Drawn under Today's
/// dateline by `CountdownRoute`; nothing in the app makes one.
///
/// Dates arrive as text and are read here, so a field the app can't read
/// means only that the countdown isn't drawn. No emoji anywhere (build 36):
/// the plane and the house are drawn, and the words are only words.
struct Countdown: Codable, Equatable {
    let label: String
    /// The day the plane leaves the origin dot.
    let startDate: String?
    /// The day itself, in `targetTz`. The days are counted in that zone.
    let targetDate: String
    let targetTz: String
    /// When the plane lands, with its own offset: the trip's zone, not
    /// `targetTz`.
    let arrivesAt: String?
    /// When it all goes, with its own offset.
    let homeUntil: String?
    let messages: Messages?
    /// Little notes tucked into the page (build 36; one for every day since
    /// build 38), keyed by how many calendar days are left ("14": "Two weeks.
    /// Let that sink in."), "0" being the day itself. A note shows on its day
    /// only; a day without one has none.
    let reminders: [String: String]?

    struct Messages: Codable, Equatable {
        let countdown: String?
        let twoDays: String?
        let oneDay: String?
        let departure: String?
        let inTheAir: String?
        let home: String?
    }

    /// Where things stand at a moment: what's drawn, the words under it, and
    /// what the flip clock counts down to, if it's still counting.
    struct Phase: Equatable {
        enum Mark: Equatable {
            /// The plane on the route: 0 on the origin dot, 1 on the end.
            case plane(Double)
            /// The route gone, a house where it was.
            case home
        }
        let mark: Mark
        let text: String
        /// The start of the day itself, while it's still ahead (build 36).
        /// Nil once it has come: the moment has arrived, nothing to count.
        var until: Date? = nil
        /// Today's tucked-in note, if today has one (build 36; the day
        /// itself too since build 38).
        var reminder: String? = nil
    }

    /// Before the day, the plane moves along by how much of the wait has
    /// passed, the words count the days (two left is "Almost Home", one is
    /// "Tomorrow"), and the clock counts to the first second of the day. The
    /// day itself, then until landing, the plane sits at the end. Landed, a
    /// house. After `homeUntil`, nothing at all.
    ///
    /// Which words is a matter of calendar days in `targetTz` (the day before
    /// is "Tomorrow" all day). The number in them is the clock's own whole
    /// days, so the words and the clock under them never disagree: on Nov 6
    /// at 7 PM it's "16 days for Home" over 16 Days : 05 Hours, not a 17 over
    /// a 16.
    func phase(at now: Date) -> Phase? {
        guard let calendar = calendar, let departs = day(targetDate, in: calendar),
              let departureEnds = calendar.date(byAdding: .day, value: 1, to: departs)
        else { return nil }
        let lands = arrivesAt.flatMap(Self.moment)
        let leaves = homeUntil.flatMap(Self.moment)

        if now < departs {
            let today = calendar.startOfDay(for: now)
            let days = calendar.dateComponents([.day], from: today, to: departs).day ?? 0
            let start = startDate.flatMap { day($0, in: calendar) } ?? today
            let span = departs.timeIntervalSince(start)
            let progress = span > 0 ? min(1, max(0, now.timeIntervalSince(start) / span)) : 0
            let words: String
            switch days {
            case 1: words = fill(messages?.oneDay ?? "Tomorrow")
            case 2: words = fill(messages?.twoDays ?? "Almost there")
            default:
                words = fill(messages?.countdown ?? "{days} days until {label}",
                             days: Self.wholeDays(departs.timeIntervalSince(now)))
            }
            return Phase(mark: .plane(progress), text: words, until: departs, reminder: note(days))
        }
        if now < departureEnds {
            return Phase(mark: .plane(1), text: fill(messages?.departure ?? "Today"), reminder: note(0))
        }
        if let lands, now < lands {
            return Phase(mark: .plane(1), text: fill(messages?.inTheAir ?? "On the way"))
        }
        if let lands, let leaves, now >= lands, now < leaves {
            return Phase(mark: .home, text: fill(messages?.home ?? "Home"))
        }
        return nil
    }

    /// A photo posted on the day itself, which gets a small drawn plane by
    /// its time.
    func marks(_ posted: Date) -> Bool {
        guard let calendar = calendar, let departs = day(targetDate, in: calendar) else { return false }
        return calendar.isDate(posted, inSameDayAs: departs)
    }

    /// What the flip clock shows for so many seconds left: whole days, then
    /// hours, minutes and seconds. Rounded to the nearest second, since the
    /// clock ticks on whole seconds.
    static func clock(_ remaining: TimeInterval) -> (days: Int, hours: Int, minutes: Int, seconds: Int) {
        let total = max(0, Int(remaining.rounded()))
        return (total / 86_400, total % 86_400 / 3_600, total % 3_600 / 60, total % 60)
    }

    static func wholeDays(_ remaining: TimeInterval) -> Int { clock(remaining).days }

    // MARK: reading it

    private var calendar: Calendar? {
        guard let zone = TimeZone(identifier: targetTz) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar
    }

    /// The start of a YYYY-MM-DD day in the calendar's zone.
    private func day(_ text: String, in calendar: Calendar) -> Date? {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    private static func moment(_ text: String) -> Date? {
        let reader = ISO8601DateFormatter()
        reader.formatOptions = [.withInternetDateTime]
        return reader.date(from: text)
    }

    /// The note for so many calendar days left, if there's one with words.
    private func note(_ days: Int) -> String? {
        guard let words = reminders?[String(days)]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !words.isEmpty
        else { return nil }
        return words
    }

    private func fill(_ template: String, days: Int? = nil) -> String {
        var words = template.replacingOccurrences(of: "{label}", with: label)
        if let days { words = words.replacingOccurrences(of: "{days}", with: "\(days)") }
        return words.trimmingCharacters(in: .whitespaces)
    }
}
