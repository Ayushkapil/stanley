import Foundation

/// Where the trip stands on the flight-path strip under Today's dateline
/// (build 74): the plane's place on the line, the words under it, and how
/// warm it's drawn. Foundation only, so the unit tests read it as it is.
///
/// Before the trip it counts days and hours (build 75) to the first moment
/// of the departure day where the journey begins (midnight on the 23rd in
/// Bloomington): one moment, so "India in 7 days 3 hours" is the same in
/// Bloomington and in Mumbai. From that midnight to the first leg it's
/// "Leaving today"; then the legs, which begin at absolute moments and are
/// shown in the viewer's own zone. Nothing is ever a negative number, and a
/// day after landing it's gone.
extension Countdown {
    /// A leg with its moment known.
    struct Stop: Equatable {
        let words: String
        let at: Date
    }

    struct Journey: Equatable {
        enum Stage: Equatable {
            /// Before the departure day begins: whole days and hours left
            /// (0 and 0 is "under an hour").
            case left(days: Int, hours: Int)
            /// The departure day, before its first leg.
            case today
            /// On the way: the leg it's on, an index into `stops`. The last
            /// is the landing.
            case leg(Int)
        }

        let stage: Stage
        /// The plane on the strip, 0 at its left, 1 on the destination.
        let progress: Double
        /// Where each stop sits on the strip.
        let marks: [Double]
        let stops: [Stop]
        /// 0 as plain as the page; up to 1 as the trip comes close (seven
        /// days or fewer), and 1 once it's begun.
        let warmth: Double
        let label: String

        /// Seven days or fewer: the numbers are written in the hand.
        var close: Bool {
            if case .left(let days, _) = stage { return days <= Countdown.closeDays }
            return true
        }

        /// The leg it's on, if it's begun.
        var current: Int? {
            if case .leg(let index) = stage { return index }
            return nil
        }

        var landed: Bool { current == stops.count - 1 }

        /// The words in pieces, each number apart so the view can set it in
        /// the hand: "India in ", "7", " days ", "3", " hours".
        var words: [(text: String, number: Bool)] {
            switch stage {
            case .left(0, 0):
                return [("\(label) in under an hour", false)]
            case .left(let days, let hours):
                var pieces: [(text: String, number: Bool)] = [("\(label) in ", false)]
                if days > 0 {
                    pieces += [("\(days)", true), (days == 1 ? " day" : " days", false)]
                }
                if hours > 0 {
                    if days > 0 { pieces.append((" ", false)) }
                    pieces += [("\(hours)", true), (hours == 1 ? " hour" : " hours", false)]
                }
                return pieces
            case .today:
                return [("Leaving today", false)]
            case .leg(let index):
                return [(stops[index].words, false)]
            }
        }

        var text: String { words.map(\.text).joined() }

        /// What VoiceOver reads for the whole strip, one element: the day's
        /// note if there is one, then where things stand, "India in 7 days 3
        /// hours", or the trip and where it is, "India. In the air". The
        /// plane says nothing.
        func spoken(reminder: String?) -> String {
            let state: String
            if case .left = stage { state = text } else { state = "\(label). \(text)" }
            guard let note = reminder?.trimmingCharacters(in: .whitespaces), !note.isEmpty else { return state }
            let ended = note.last.map { ".!?".contains($0) } ?? false
            return "\(note)\(ended ? "" : ".") \(state)"
        }
    }

    /// Seven days out or fewer, the trip is close.
    static let closeDays = 7
    /// "Landed" stays this long, then the strip goes.
    static let landedHolds: TimeInterval = 86_400
    /// How much of the strip the wait takes; the journey has the rest, so
    /// the plane moves visibly while it's in the air.
    static let waitShare = 0.6

    /// The legs whose moments are known, in order. Without legs in the
    /// config (one written before build 74), the departure day's start
    /// and the landing.
    var stops: [Stop] {
        if let legs {
            return legs.compactMap { leg in
                guard let text = leg.at, let at = Self.moment(text) else { return nil }
                let words = leg.words.trimmingCharacters(in: .whitespacesAndNewlines)
                return words.isEmpty ? nil : Stop(words: words, at: at)
            }
        }
        guard let departs = departureDay, let lands = arrivesAt.flatMap(Self.moment), departs < lands
        else { return [] }
        return [Stop(words: "On the way", at: departs), Stop(words: "Landed", at: lands)]
    }

    /// What the days and hours count to: the first moment of the departure
    /// day where the journey begins, by the first leg's own date and offset
    /// ("2026-11-23T09:00:00-05:00" is midnight on the 23rd at -05:00).
    /// Without legs, midnight on `target_date` in `target_tz`.
    var departureDay: Date? {
        if let legs {
            for leg in legs {
                guard let text = leg.at, Self.moment(text) != nil else { continue }
                let offset = text.range(of: "(Z|[+-]\\d{2}:\\d{2})$", options: .regularExpression)
                guard text.count >= 10, let offset else { return nil }
                return Self.moment("\(text.prefix(10))T00:00:00\(text[offset])")
            }
            return nil
        }
        guard let zone = TimeZone(identifier: targetTz) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return LocalDay.date(targetDate, calendar: calendar)
    }

    /// The strip at a moment, or nil once "Landed" has held its day (or
    /// with nothing to draw).
    func journey(at now: Date, calendar: Calendar = .current) -> Journey? {
        let stops = stops
        guard stops.count >= 2, let first = stops.first, let last = stops.last,
              now < last.at.addingTimeInterval(Self.landedHolds)
        else { return nil }

        // The journey's stops along the last part of the strip, by time.
        let span = last.at.timeIntervalSince(first.at)
        let marks = stops.map { stop in
            Self.waitShare + (1 - Self.waitShare) * (span > 0 ? stop.at.timeIntervalSince(first.at) / span : 1)
        }

        if now < first.at {
            let target = min(departureDay ?? first.at, first.at)
            let remaining = max(0, target.timeIntervalSince(now))
            let stage: Journey.Stage = now < target
                ? .left(days: Int(remaining / 86_400), hours: Int(remaining.truncatingRemainder(dividingBy: 86_400) / 3_600))
                : .today
            // Along the wait, from the start day's midnight to departure.
            let start = startDate.flatMap { LocalDay.date($0, calendar: calendar) }
            let progress: Double
            if let start, start < first.at {
                progress = Self.waitShare * min(1, max(0, now.timeIntervalSince(start) / first.at.timeIntervalSince(start)))
            } else {
                progress = 0
            }
            let close: Bool
            if case .left(let days, _) = stage { close = days <= Self.closeDays } else { close = true }
            let window = (Double(Self.closeDays) + 1) * 86_400
            let warmth = close ? min(1, max(0.12, 1 - remaining / window)) : 0
            return Journey(stage: stage, progress: progress, marks: marks, stops: stops, warmth: warmth, label: label)
        }

        let index = stops.lastIndex { $0.at <= now } ?? 0
        let progress: Double
        if index == stops.count - 1 || span <= 0 {
            progress = 1
        } else {
            progress = Self.waitShare + (1 - Self.waitShare) * now.timeIntervalSince(first.at) / span
        }
        return Journey(stage: .leg(index), progress: min(1, progress), marks: marks, stops: stops, warmth: 1, label: label)
    }
}
