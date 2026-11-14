import SwiftUI
import UIKit

// The Journal widget (build 45): today's page on the Home Screen, and in
// its medium size yesterday's beside it. Like the circle's widget it makes
// no network calls and holds no sign-in: it draws what the app last left in
// the App Group folder the two share.
//
// What's left there is only the person's own words: the opening lines of
// their last few days' pages, the ink each was written in and the number
// of the page in the book. Nothing of anyone else's. With the app lock on
// nothing is left at all, and it's emptied on sign-out.

/// What the Journal widget shows, as the app last left it.
struct JournalWidgetSnapshot: Codable, Equatable {
    /// How much of a page is left for the widget: plenty for the three
    /// lines it shows, and no more of someone's journal than that.
    static let opening = 240

    var writtenAt: Date
    var signedIn: Bool
    /// The app lock is on: no words are shown, only that it's the journal.
    var locked = false
    /// Written while no Journal widget was on the Home Screen, so the pages
    /// were held back, not missing.
    var withheld: Bool?
    /// What the journal is called, if it has a name of its own.
    var title: String?
    /// The last few days' pages, newest first.
    var days: [Day] = []
    /// The number today's page would have if it's written now: the page
    /// after the book's last.
    var nextPage: Int?

    struct Day: Codable, Equatable, Identifiable {
        /// "2026-11-14", by the phone's own calendar.
        let day: String
        /// The page's opening, cut short.
        let text: String
        let ink: String
        /// Its number in the book, when the app knew it.
        let page: Int?
        var id: String { day }
    }

    static let signedOut = JournalWidgetSnapshot(writtenAt: .distantPast, signedIn: false)

    func page(on day: String) -> Day? {
        guard !locked else { return nil }
        return days.first { $0.day == day }
    }

    /// Yesterday's day string, by the phone's calendar.
    static func dayBefore(_ date: Date) -> String {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: date) ?? date
        return WidgetSnapshot.day(yesterday)
    }
}

enum JournalWidgetStore {
    private static var file: URL? { WidgetStore.folder?.appendingPathComponent("journal.json") }

    static func read() -> JournalWidgetSnapshot {
        guard let file, let data = try? Data(contentsOf: file),
              let snapshot = try? JSONDecoder().decode(JournalWidgetSnapshot.self, from: data)
        else { return .signedOut }
        return snapshot
    }

    static func write(_ snapshot: JournalWidgetSnapshot) {
        guard let file, let data = try? JSONEncoder().encode(snapshot) else { return }
        // Readable after the first unlock, as a widget needs, and never
        // copied off in a backup: the pages themselves are on the server.
        try? data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var url = file
        try? url.setResourceValues(values)
    }
}

/// Where a tap on the widget goes: the journal, opened at a day's page.
enum JournalLink {
    static func url(day: String) -> URL? { URL(string: "stanley://journal?day=\(day)") }
}

// MARK: - The widget's pages

/// One page of the book, small: a date, the first lines in their ink on
/// ruled paper, the page's number in its outer corner.
struct JournalWidgetPage: View {
    @Environment(\.colorScheme) private var colorScheme
    let day: String
    let entry: JournalWidgetSnapshot.Day?
    /// What to say when there's no page for the day.
    let blank: String
    /// Its number, and which corner is the outer one.
    let number: Int?
    let rightHand: Bool
    var lines = 3
    var size: CGFloat = 14

    private var font: UIFont { BookHand.font(size) }
    /// The ruled lines' pitch: the hand's own line, so the words sit on them.
    private var pitch: CGFloat { ceil(font.lineHeight) }

    private var date: String {
        guard let parsed = Self.parse(day) else { return day }
        return parsed.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    static func parse(_ day: String) -> Date? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    var body: some View {
        let ink = Ink.named(entry?.ink)
        VStack(alignment: .leading, spacing: 0) {
            Text(date)
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.1)
                .textCase(.uppercase)
                .foregroundStyle(BookPaper.quiet)
                .lineLimit(1)
                .padding(.bottom, 4)
            ZStack(alignment: .topLeading) {
                // The rules, one under each line of writing.
                VStack(spacing: 0) {
                    ForEach(0..<lines, id: \.self) { _ in
                        Color.clear
                            .frame(height: pitch)
                            .overlay(alignment: .bottom) {
                                Rectangle().fill(BookPaper.rule).frame(height: 0.5)
                                    .offset(y: font.descender + 3)
                            }
                    }
                }
                if let entry {
                    Text(entry.text)
                        .font(.custom(font.fontName, fixedSize: size))
                        .foregroundStyle(ink.color)
                        .lineLimit(lines)
                        .multilineTextAlignment(.leading)
                } else {
                    Text(blank)
                        .font(.custom(font.fontName, fixedSize: size))
                        .foregroundStyle(BookPaper.quiet)
                        .lineLimit(lines)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            Spacer(minLength: 0)
            if let number {
                Text("\(number)")
                    .font(.system(size: 10, weight: .regular).monospacedDigit())
                    .foregroundStyle(BookPaper.quiet)
                    .frame(maxWidth: .infinity, alignment: rightHand ? .trailing : .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.map { "\(date). \($0.text)" } ?? "\(date). \(blank)")
    }
}

/// The Journal widget at one size.
struct JournalWidgetView: View {
    let snapshot: JournalWidgetSnapshot
    let date: Date
    let size: WidgetSize

    private var today: String { WidgetSnapshot.day(date) }
    private var yesterday: String { JournalWidgetSnapshot.dayBefore(date) }

    /// Today's page number: its own if it's written, else the next page's.
    private var todaysNumber: Int? {
        snapshot.page(on: today)?.page ?? snapshot.nextPage
    }

    var body: some View {
        if !snapshot.signedIn {
            closed("Open Stanley to write in your journal.")
        } else if snapshot.locked {
            closed("Locked. Open Stanley to read it.")
        } else if snapshot.withheld == true {
            closed("Open Stanley to see today's page.")
        } else if size == .small {
            page(today, blank: "Today's page is blank.", number: todaysNumber, rightHand: true)
        } else {
            spread
        }
    }

    private func page(_ day: String, blank: String, number: Int?, rightHand: Bool) -> some View {
        JournalWidgetPage(
            day: day, entry: snapshot.page(on: day), blank: blank,
            number: number, rightHand: rightHand,
            lines: size == .small ? 3 : 4
        )
    }

    /// The medium size: the book lying open, yesterday on the left and
    /// today on the right, each a way into its own page.
    private var spread: some View {
        HStack(spacing: 0) {
            link(yesterday) {
                page(yesterday, blank: "Nothing written.", number: snapshot.page(on: yesterday)?.page, rightHand: false)
                    .padding(.trailing, 14)
            }
            // The gutter, where the pages meet.
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.10), .clear],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
                .frame(width: 10)
                .padding(.vertical, -16)
                .accessibilityHidden(true)
            link(today) {
                page(today, blank: "Today's page is blank.", number: todaysNumber, rightHand: true)
                    .padding(.leading, 14)
            }
        }
    }

    @ViewBuilder
    private func link<Content: View>(_ day: String, @ViewBuilder content: () -> Content) -> some View {
        if let url = JournalLink.url(day: day) {
            Link(destination: url) { content() }
        } else {
            content()
        }
    }

    /// The book shut: its name, and a line.
    private func closed(_ line: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(snapshot.locked || !snapshot.signedIn ? "Journal" : (snapshot.title ?? "My Journal"))
                .font(.custom(BookHand.font(20, bold: true).fontName, fixedSize: 20))
                .foregroundStyle(Ink.black.color)
                .lineLimit(2)
            Text(line)
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(BookPaper.quiet)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }
}

/// The widget's paper: the book's page, in the Home Screen's light or dark.
struct JournalWidgetBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            BookPaper.page
            if colorScheme != .dark {
                Image(uiImage: PaperGrain.tile)
                    .resizable(resizingMode: .tile)
                    .opacity(0.3)
            }
        }
        .accessibilityHidden(true)
    }
}
