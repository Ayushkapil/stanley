import Foundation

/// A suggestion for the page being written (build 63): one line of faint
/// handwriting over a new page, a tap putting it at the top of the page as
/// its first line, another suggestion a tap on the arrow beside it.
/// Ignored, it goes as the first word is written. Never stored, never
/// tracked, never counted. Until build 63 the prompts were a sheet behind
/// a toolbar item ("Prompts", the circle journal).
///
/// The words are the circle's own forty questions of the week
/// (`server/stanley/journal.py`, `QUESTIONS`), the same here as there:
/// `tests/test_writing_prompts.py` fails if the two drift. The circle's
/// question and its weekly turn are the server's, unchanged; this is only
/// where a page begins.
enum WritingPrompt {
    static let all: [String] = [
        "What's something you believed at the start of this week that you're not sure about anymore?",
        "What moment this week would you relive if you could?",
        "What's something you didn't say this week but wanted to?",
        "If this week had a title, what would it be and why?",
        "What's something you noticed that nobody else seemed to?",
        "What felt heavy this week, and did it get lighter?",
        "What would your week look like from someone else's eyes?",
        "What's a conversation you had this week that stuck with you?",
        "What are you carrying into next week that you wish you could leave behind?",
        "What's something small that happened that might matter more than you think?",
        "Where did your mind keep going this week when it wandered?",
        "What's something you did for the first time, even if it was tiny?",
        "What would you want to remember about this week five years from now?",
        "What's something you're figuring out right now?",
        "Who were you closest to this week, and why?",
        "What made you feel most like yourself?",
        "What's something you're not ready to talk about but could write about?",
        "What surprised you about yourself this week?",
        "If you could give this week a color, what would it be?",
        "What are you slowly becoming?",
        "What question should you be asking yourself right now?",
        "What's something you let go of this week?",
        "What's the difference between who you were on Monday and who you are now?",
        "What does your week look like if you only count the quiet moments?",
        "What's one thing you want to be true about next week?",
        "What are you pretending is fine?",
        "What did you make time for, and what made time for itself?",
        "What would you write on a postcard to your future self about this week?",
        "What's a feeling you had this week that you don't have a word for?",
        "What are you building, even if nobody can see it yet?",
        "What mattered more than you expected?",
        "What's something you keep coming back to in your head?",
        "What would this week's photo look like if you could only take one?",
        "What are you grateful for that you didn't expect?",
        "What's the most honest thing you could say about where you are right now?",
        "What did you learn about someone in your circle this week?",
        "What's something you want but haven't admitted to yourself?",
        "What does rest look like for you right now?",
        "What question would you want your circle to answer honestly?",
        "What's one line you'd write in a letter to the person you were a year ago?",
    ]

    /// The day's first suggestion: the same all day, the next one tomorrow
    /// (as the capture's `DailyPrompt` turns), skipping any that won't fit
    /// on one line. Nil when none does.
    static func first(
        on date: Date = .now, calendar: Calendar = .current, fits: (String) -> Bool = { _ in true }
    ) -> Int? {
        // Days counted on the calendar's own clock. (`ordinality(of: .day,
        // in: .era)` turns at midnight UTC, which is seven in the evening
        // in Bloomington: a test caught it.)
        let epoch = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1)) ?? date
        let day = calendar.dateComponents([.day], from: epoch, to: calendar.startOfDay(for: date)).day ?? 0
        let start = ((day % all.count) + all.count) % all.count
        return from(start, fits: fits)
    }

    /// Another suggestion: the next that fits, round again to the start.
    /// Nil when none does; the same one only when it's the only one.
    static func after(_ index: Int, fits: (String) -> Bool = { _ in true }) -> Int? {
        from((index + 1) % all.count, fits: fits)
    }

    private static func from(_ start: Int, fits: (String) -> Bool) -> Int? {
        (0..<all.count).lazy.map { (start + $0) % all.count }.first { fits(all[$0]) }
    }
}
