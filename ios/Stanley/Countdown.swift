import Foundation

/// Something one circle is counting toward (build 35), as the server sends it
/// with the circle on screen: a flag set by hand on a single circle
/// (`scripts/set_countdown.py`), nil for every other. Drawn under Today's
/// dateline by `CountdownRoute`; nothing in the app makes one.
///
/// Dates arrive as text and are read here, so a field the app can't read
/// means only that the countdown isn't drawn.
struct Countdown: Codable, Equatable {
    let label: String
    let emoji: String?
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

    struct Messages: Codable, Equatable {
        let countdown: String?
        let twoDays: String?
        let oneDay: String?
        let departure: String?
        let inTheAir: String?
        let home: String?
    }

    /// Where things stand at a moment: what's drawn, and the words under it.
    struct Phase: Equatable {
        enum Mark: Equatable {
            /// The plane on the route: 0 on the origin dot, 1 on the end.
            case plane(Double)
            /// The route gone, a house where it was.
            case home
        }
        let mark: Mark
        let text: String
    }

    /// Before the day, the plane moves along by how much of the wait has
    /// passed and the words count the days (two left is "Almost there", one
    /// is "Tomorrow"). The day itself, then until landing, the plane sits at
    /// the end. Landed, a house. After `homeUntil`, nothing at all.
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
            case 1: words = fill(messages?.oneDay ?? "Tomorrow {emoji}")
            case 2: words = fill(messages?.twoDays ?? "Almost there {emoji}")
            default: words = fill(messages?.countdown ?? "{days} days until {label} {emoji}", days: days)
            }
            return Phase(mark: .plane(progress), text: words)
        }
        if now < departureEnds {
            return Phase(mark: .plane(1), text: fill(messages?.departure ?? "Today {emoji}"))
        }
        if let lands, now < lands {
            return Phase(mark: .plane(1), text: fill(messages?.inTheAir ?? "On the way {emoji}"))
        }
        if let lands, let leaves, now >= lands, now < leaves {
            return Phase(mark: .home, text: fill(messages?.home ?? "Home 🏠"))
        }
        return nil
    }

    /// A small plane by the time on a photo posted on the day itself.
    func marks(_ posted: Date) -> Bool {
        guard let calendar = calendar, let departs = day(targetDate, in: calendar) else { return false }
        return calendar.isDate(posted, inSameDayAs: departs)
    }

    /// What goes by that time, if anything.
    func mark(for posted: Date) -> String? {
        marks(posted) ? (emoji ?? "✈️") : nil
    }

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

    private func fill(_ template: String, days: Int? = nil) -> String {
        var words = template
            .replacingOccurrences(of: "{label}", with: label)
            .replacingOccurrences(of: "{emoji}", with: emoji ?? "")
        if let days { words = words.replacingOccurrences(of: "{days}", with: "\(days)") }
        return words.trimmingCharacters(in: .whitespaces)
    }
}
