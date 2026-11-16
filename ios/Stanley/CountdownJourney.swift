import Foundation

/// Where the trip stands on the flight-path strip under Today's dateline
/// (build 74): the plane's place on the line, the words under it, and how
/// warm it's drawn. Foundation only, so the unit tests read it as it is.
///
/// Days are the viewer's own (`LocalDay`, turning at their midnight); the
/// legs begin at absolute moments, shown in the viewer's own zone, so the
/// same strip is right in Bloomington and in Mumbai. Nothing is ever a
/// negative number: before the first leg it counts down, from it on it
/// names the leg, and a day after landing it's gone.
extension Countdown {
    /// A leg with its moment known.
    struct Stop: Equatable {
        let words: String
        let at: Date
    }

    struct Journey: Equatable {
        enum Stage: Equatable {
            /// Before the first leg: whole days left on the viewer's
            /// calendar, or, inside the last day, whole hours (0 is "under
            /// an hour").
            case days(Int)
            case hours(Int)
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

        /// Seven days or fewer: the number is written in the hand.
        var close: Bool {
            switch stage {
            case .days(let days): return days <= Countdown.closeDays
            case .hours, .leg: return true
            }
        }

        /// The leg it's on, if it's begun.
        var current: Int? {
            if case .leg(let index) = stage { return index }
            return nil
        }

        var landed: Bool { current == stops.count - 1 }

        /// The words, cut where the number is, so the view can set the
        /// number apart: ("India in ", "9", " days").
        var words: (lead: String, number: String?, tail: String) {
            switch stage {
            case .days(let days):
                return ("\(label) in ", "\(days)", days == 1 ? " day" : " days")
            case .hours(0):
                return ("\(label) in under an hour", nil, "")
            case .hours(let hours):
                return ("\(label) in ", "\(hours)", hours == 1 ? " hour" : " hours")
            case .leg(let index):
                return (stops[index].words, nil, "")
            }
        }

        var text: String {
            let parts = words
            return parts.lead + (parts.number ?? "") + parts.tail
        }

        /// What VoiceOver reads for the whole strip, one element: the day's
        /// note if there is one, then where things stand, "India in 9 days",
        /// or the trip and the leg it's on, "India. In the air". The plane
        /// says nothing.
        func spoken(reminder: String?) -> String {
            let state = current == nil ? text : "\(label). \(text)"
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
        guard let zone = TimeZone(identifier: targetTz), let lands = arrivesAt.flatMap(Self.moment)
        else { return [] }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        guard let departs = LocalDay.date(targetDate, calendar: calendar), departs < lands else { return [] }
        return [Stop(words: "On the way", at: departs), Stop(words: "Landed", at: lands)]
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
            let remaining = first.at.timeIntervalSince(now)
            let days = LocalDay.number(of: first.at, calendar: calendar) - LocalDay.number(of: now, calendar: calendar)
            let stage: Journey.Stage = remaining < 86_400
                ? .hours(Int(remaining / 3_600))
                : .days(max(1, days))
            // Along the wait, from the start day's midnight to departure.
            let start = startDate.flatMap { LocalDay.date($0, calendar: calendar) }
            let progress: Double
            if let start, start < first.at {
                progress = Self.waitShare * min(1, max(0, now.timeIntervalSince(start) / first.at.timeIntervalSince(start)))
            } else {
                progress = 0
            }
            let close: Bool
            if case .days(let days) = stage { close = days <= Self.closeDays } else { close = true }
            let window = (Double(Self.closeDays) + 0.5) * 86_400
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
