import SwiftUI
import WidgetKit

// Stanley on the home screen (build 40): one widget in three sizes, drawn
// from what the app last left in the shared App Group folder
// (`WidgetSnapshot`). It makes no network calls and holds no sign-in; it
// knows only what Today showed the last time the app had it on screen.

@main
struct StanleyWidgetBundle: WidgetBundle {
    var body: some Widget {
        StanleyWidget()
        JournalWidget()
    }
}

struct StanleyWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "StanleyWidget", provider: StanleyTimeline()) { entry in
            StanleyWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Your circle")
        .description("Today in your circle: its countdown or note, and its newest photos.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct StanleyEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

/// The timeline: what the snapshot looks like now and at each moment it
/// changes by itself over the next while. WidgetKit is asked to come back
/// in half an hour; the app also asks whenever it writes something new.
struct StanleyTimeline: TimelineProvider {
    /// How often the widget reads the shared folder again.
    static let refresh: TimeInterval = 30 * 60

    func placeholder(in context: Context) -> StanleyEntry {
        StanleyEntry(date: .now, snapshot: Self.sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (StanleyEntry) -> Void) {
        // In the widget gallery, before there's anything of the person's to
        // show, a made-up circle stands in.
        let stored = WidgetStore.read()
        let shown = context.isPreview && !stored.signedIn ? Self.sample : stored
        completion(StanleyEntry(date: .now, snapshot: shown))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StanleyEntry>) -> Void) {
        let now = Date.now
        let snapshot = WidgetStore.read()
        // What the widget can no longer show leaves the folder too: photos a
        // day stale, or past their six days.
        WidgetStore.prune(keeping: Set(snapshot.photos(at: now).map(\.file)))
        let entries = Self.moments(for: snapshot, from: now).map { StanleyEntry(date: $0, snapshot: snapshot) }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(Self.refresh))))
    }

    /// Now, and every moment in the next hour at which the same snapshot
    /// reads differently: each whole minute while a countdown's clock is
    /// running, the end of the day (a new day's photo is waiting, and
    /// yesterday's note is gone), and the moment the photos go stale. An
    /// hour's worth, though the next read is asked for in half that, so a
    /// late one still finds the clock turning.
    static func moments(for snapshot: WidgetSnapshot, from now: Date) -> [Date] {
        let horizon = now.addingTimeInterval(2 * refresh)
        var moments: Set<Date> = [now]
        let calendar = Calendar.current
        if snapshot.phase(at: now)?.until != nil || snapshot.phase(at: horizon)?.until != nil {
            var minute = calendar.dateInterval(of: .minute, for: now)?.end ?? now
            while minute <= horizon {
                moments.insert(minute)
                minute = minute.addingTimeInterval(60)
            }
        } else {
            moments.insert(now.addingTimeInterval(refresh))
        }
        if let midnight = calendar.dateInterval(of: .day, for: now)?.end, midnight <= horizon {
            moments.insert(midnight)
        }
        let stale = snapshot.writtenAt.addingTimeInterval(WidgetSnapshot.photosKeep)
        if stale > now, stale <= horizon { moments.insert(stale) }
        return moments.sorted()
    }

    /// A made-up circle for the widget gallery: words only, no one's photos.
    static let sample = WidgetSnapshot(
        writtenAt: .now, signedIn: true, circleName: "Third Floor",
        postedOn: WidgetSnapshot.day(.now),
        note: .init(text: "movie night in the lounge at 9, bring blankets", name: "Ruby", day: WidgetSnapshot.day(.now))
    )
}

struct StanleyWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: StanleyEntry

    private var size: WidgetSize {
        switch family {
        case .systemMedium: .medium
        case .systemLarge: .large
        default: .small
        }
    }

    /// Light or dark is the home screen's, never the app's own setting.
    /// Build 40 followed the app when it was set to Light or Dark, but the
    /// system draws a widget's container background in the home screen's
    /// appearance whatever the content is told: with the app set to Dark on
    /// a light phone, the dark room's warm white words landed on cream paper
    /// and couldn't be read.
    var body: some View {
        page
            // The small one opens Stanley as it was left; the others open Today.
            .widgetURL(URL(string: size == .small ? "stanley://open" : "stanley://today"))
    }

    /// An entry is drawn as it reads a second in: an entry on the whole
    /// minute stays up for that minute, and at its first instant the clock
    /// still has the minute before on it (12:00 left, where the app spends
    /// the minute counting 11:59 down to 11:00). A second in, the widget's
    /// minutes are the app's.
    private var page: some View {
        StanleyWidgetView(snapshot: entry.snapshot, date: entry.date.addingTimeInterval(1), size: size)
            .containerBackground(for: .widget) {
                WidgetBackdrop(atmosphere: entry.snapshot.atmosphere)
            }
    }
}

// MARK: - The Journal widget (build 45)

/// Today's page of the journal, and in the medium size yesterday's beside
/// it. Drawn from the few lines the app last left in the shared folder
/// (`JournalWidgetSnapshot`): the person's own words and nobody else's.
struct JournalWidget: Widget {
    static let kind = "StanleyJournalWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: JournalTimeline()) { entry in
            JournalWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Journal")
        .description("Today's page of your journal, in your own ink.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct JournalTimelineEntry: TimelineEntry {
    let date: Date
    let snapshot: JournalWidgetSnapshot
}

/// Now, and midnight: a new day's page is blank, and today's is yesterday's.
struct JournalTimeline: TimelineProvider {
    func placeholder(in context: Context) -> JournalTimelineEntry {
        JournalTimelineEntry(date: .now, snapshot: Self.sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (JournalTimelineEntry) -> Void) {
        let stored = JournalWidgetStore.read()
        let shown = context.isPreview && (!stored.signedIn || stored.days.isEmpty) ? Self.sample : stored
        completion(JournalTimelineEntry(date: .now, snapshot: shown))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<JournalTimelineEntry>) -> Void) {
        let now = Date.now
        let snapshot = JournalWidgetStore.read()
        var entries = [JournalTimelineEntry(date: now, snapshot: snapshot)]
        let midnight = Calendar.current.dateInterval(of: .day, for: now)?.end ?? now.addingTimeInterval(86_400)
        entries.append(JournalTimelineEntry(date: midnight, snapshot: snapshot))
        completion(Timeline(entries: entries, policy: .after(midnight.addingTimeInterval(60))))
    }

    /// A made-up page for the widget gallery.
    static var sample: JournalWidgetSnapshot {
        let today = WidgetSnapshot.day(.now)
        let yesterday = JournalWidgetSnapshot.dayBefore(.now)
        return JournalWidgetSnapshot(
            writtenAt: .now, signedIn: true,
            days: [
                .init(day: today, text: "Rain all morning, then the lawn after, everything rinsed and bright.", ink: "blue", page: 24),
                .init(day: yesterday, text: "Stayed up too late talking on the stairs. Worth it.", ink: "black", page: 23),
            ],
            nextPage: 25
        )
    }
}

struct JournalWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: JournalTimelineEntry

    var body: some View {
        // An entry on the stroke of midnight is drawn a second in, so its
        // day is the new one.
        let date = entry.date.addingTimeInterval(1)
        JournalWidgetView(snapshot: entry.snapshot, date: date, size: family == .systemMedium ? .medium : .small)
            .widgetURL(JournalLink.url(day: WidgetSnapshot.day(date)))
            .containerBackground(for: .widget) { JournalWidgetBackdrop() }
    }
}
