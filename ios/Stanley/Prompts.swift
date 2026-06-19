import Foundation

/// The day's gentle prompt (Part 1). Optional, never tracked. Picked
/// deterministically by calendar date so the whole circle shares the same
/// whisper without coordinating. It lives only in the capture moment — it is
/// never stored, never shown in the feed, never "completed."
enum DailyPrompt {
    static let all: [String] = [
        "something you walked past today",
        "the last thing you ate",
        "a color that caught your eye",
        "someone who made you laugh",
        "where you sat longest today",
        "something you'd forget by tomorrow",
        "the sky right now",
        "your hands",
        "what's on your desk",
        "something kind someone did",
        "a small thing that worked",
        "the view from where you are",
        "what you're holding",
        "a corner of your room",
        "something that smelled good",
        "the light right now",
        "what you almost didn't notice",
        "something old you still use",
        "a face you were glad to see",
        "what's in your pocket",
        "the quietest moment today",
        "something you're grateful is over",
        "a texture you touched",
        "what's left of your coffee",
        "the long way around",
        "something that's usually invisible",
        "where you're going next",
        "a sound you can almost see",
        "the most ordinary thing here",
        "something you'd show a friend",
        "what today felt like",
        "a thing you fixed",
        "the edge of something",
        "what you waited for",
    ]

    /// Deterministic by local calendar day — same prompt across the circle.
    static func forToday(_ date: Date = Date(), calendar: Calendar = .current) -> String {
        let day = calendar.ordinality(of: .day, in: .era, for: date) ?? 0
        return all[((day % all.count) + all.count) % all.count]
    }
}
