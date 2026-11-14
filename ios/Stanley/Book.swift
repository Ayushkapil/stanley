import SwiftUI
import UIKit

// The journal's pages (build 46; a book with a cover in build 45). The
// Journal tab is the pages themselves: it lands on today's, and everything
// before it lies behind, a swipe to the right at a time. This file is the
// book before anything is drawn: how big a page is, what kinds of page
// there are, how a long day is broken across pages, and how the pages are
// put in order (oldest first, as a book is bound, so today's is the last
// and turning back goes back).
//
// Everything in it is the person's own, and nobody else ever sees it: the
// pages they wrote, the photos they kept, the letters written to them and
// opened, and their weekly reflections.

/// Which page the journal should be at when it's shown.
enum BookStart: Equatable {
    /// Today's page, where the tab lands.
    case today
    /// A day's page ("2026-11-14"), as the widget asks.
    case day(String)
}

/// What the journal is called when nobody has named it, and how long a
/// name may be. The name is kept in Settings since build 46 (it was
/// written on a cover) and shows at the head of each month's opening page.
enum JournalName {
    static let fallback = "My Journal"
    static let limit = 60

    static func shown(_ title: String?) -> String {
        let given = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return given.isEmpty ? fallback : given
    }
}

/// The size of a page and where things sit on it. One of these is made from
/// the room the Journal tab has; pages are broken and drawn from the same
/// one, so what the breaker fits is what the page shows.
struct BookLayout: Hashable {
    /// The strip down the right of the page that isn't page: the rest of
    /// the book seen edge-on, where the ribbon and the paper tabs are.
    static let edge: CGFloat = 18

    /// The page itself: from the screen's top to the tab bar, and from the
    /// left edge to where the fore-edge begins.
    let width: CGFloat
    let height: CGFloat
    /// The screen's own safe edges: the page runs under them, its words don't.
    let safeTop: CGFloat
    let safeBottom: CGFloat
    let safeLeading: CGFloat
    let safeTrailing: CGFloat
    /// The hand's size, following Dynamic Type within reason: a page has to
    /// hold a fair few lines to be a page.
    let fontSize: CGFloat

    init(size: CGSize, safeTop: CGFloat, safeBottom: CGFloat = 0, safeLeading: CGFloat = 0, safeTrailing: CGFloat = 0) {
        width = size.width
        height = size.height
        self.safeTop = safeTop
        self.safeBottom = safeBottom
        self.safeLeading = safeLeading
        self.safeTrailing = safeTrailing
        fontSize = min(25, max(17, UIFontMetrics(forTextStyle: .body).scaledValue(for: 19).rounded()))
    }

    /// The page as the Journal tab last drew it.
    @MainActor static var shown: BookLayout?

    /// The page for when a page's number is wanted and the journal hasn't
    /// been on screen yet this launch (the widget's): as the tab last drew
    /// it, or as near as can be told from the screen.
    @MainActor
    static func forScreen() -> BookLayout {
        if let shown { return shown }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        let insets = scene?.keyWindow?.safeAreaInsets ?? .zero
        let screen = Density.canvasBounds().size
        // A tab bar along the foot takes its own height above the home
        // indicator; a dock down the side (the Duo's cover) takes none.
        let foot = insets.right > 0 ? insets.bottom : insets.bottom + 49
        return BookLayout(
            size: CGSize(width: screen.width - insets.right - edge, height: screen.height - foot),
            safeTop: insets.top, safeLeading: insets.left
        )
    }

    var font: UIFont { BookHand.font(fontSize) }
    /// The ruled lines' pitch: the hand's own line.
    var pitch: CGFloat { ceil(font.lineHeight) }
    /// The page's side margin, inside the screen's safe sides. On a wide
    /// screen the column stops at a readable width and the margins take
    /// the rest.
    var margin: CGFloat { max(28, (width - safeLeading - safeTrailing - 520) / 2) }
    /// Where the writing starts and ends, from the page's left edge.
    var left: CGFloat { safeLeading + margin }
    var right: CGFloat { width - safeTrailing - margin }
    var textWidth: CGFloat { right - left }
    var middle: CGFloat { (left + right) / 2 }
    /// The date, small, at the head of the page: where its line's middle is.
    var headY: CGFloat { safeTop + 20 }
    /// The hand's size for the date at the head.
    var headSize: CGFloat { fontSize - 4 }
    /// Where the first line begins: under the date.
    var contentTop: CGFloat { safeTop + 42 }
    /// Where the last line may end: above the page's number (or the inks).
    var contentBottom: CGFloat { height - safeBottom - Self.foot }
    var rows: Int { max(4, Int((contentBottom - contentTop) / pitch)) }
    var textHeight: CGFloat { CGFloat(rows) * pitch }
    /// How far above the foot of its line a rule is drawn: just under the
    /// letters' feet, where a ruled line sits.
    var ruleRise: CGFloat { max(0, -font.descender - 3) }
    /// The band along the foot that holds the page's number when it's read
    /// and the three inks when it's written.
    static let foot: CGFloat = 50
    /// The middle of that band.
    var numberY: CGFloat { height - safeBottom - Self.foot / 2 }
    /// The ribbon down the fore-edge runs between these.
    var trackTop: CGFloat { safeTop + 18 }
    var trackBottom: CGFloat { height - safeBottom - 18 }

    /// A letter is its own sheet laid on the page, a little in from the
    /// page's margins, with its own margins inside.
    static let letterInset: CGFloat = 20
    var letterTextWidth: CGFloat { textWidth - Self.letterInset * 2 }
    var letterRows: Int { max(3, Int((textHeight - Self.letterInset * 2) / pitch)) }
}

/// One page of the book.
struct BookPage: Identifiable {
    enum Kind {
        /// A month's opening page.
        case chapter
        /// A day's page (or one part of a long day's).
        case written(DayPage)
        /// Today's page, still blank.
        case today
        /// A photo you kept.
        case photo(HeldPage)
        /// Where a photo you kept was, before whoever posted it took it back.
        case tombstone(Memory)
        /// A letter written to you, opened.
        case letter(Letter)
        /// How a week was.
        case reflection(Reflection)
    }

    let id: String
    /// When it's from: what the book is ordered by.
    let date: Date
    let kind: Kind
    /// The words on it, already set in their hand and ink and cut to fit.
    var text: NSAttributedString?
    /// How tall those words stand.
    var textHeight: CGFloat = 0
    /// Which part of a long entry this is, from 0, and of how many.
    var part = 0
    var parts = 1

    /// Ruled paper: the pages that are written on.
    var lined: Bool {
        switch kind {
        case .written, .today, .reflection: true
        default: false
        }
    }

    /// What's written small at the head of the page: its day; a
    /// reflection's week; nothing on a month's opening page.
    var heading: String? {
        switch kind {
        case .chapter: nil
        case .reflection(let reflection): BookType.weekTitle(reflection)
        default: BookType.dayTitle(date)
        }
    }

    /// The day's own page: the one that can still be written on by a tap.
    var isToday: Bool {
        switch kind {
        case .today: true
        case .written(let written): written.day == WidgetSnapshot.day(.now)
        default: false
        }
    }

    /// A few words for VoiceOver and the page grid.
    var name: String {
        let day = date.formatted(.dateTime.weekday(.wide).month(.wide).day().year())
        switch kind {
        case .chapter: return date.formatted(.dateTime.month(.wide).year())
        case .written: return parts > 1 ? "\(day), part \(part + 1)" : day
        case .today: return "Today's page, blank"
        case .photo(let held): return "Photo from \(held.friend.displayName), \(day)"
        case .tombstone: return "A memory was here, \(day)"
        case .letter(let letter): return "Letter from \(letter.sender?.displayName ?? "someone")"
        case .reflection: return "Reflection, week ending \(day)"
        }
    }
}

/// The whole book, in order.
struct Book {
    let pages: [BookPage]

    static let empty = Book(pages: [])

    /// Where the tab lands: today's own page, written or blank; with
    /// neither (a server that can't take a page), the last page there is.
    var todayIndex: Int {
        let today = WidgetSnapshot.day(.now)
        for (index, page) in pages.enumerated() {
            switch page.kind {
            case .today: return index
            case .written(let written) where written.day == today && page.part == 0: return index
            default: continue
            }
        }
        return max(0, pages.count - 1)
    }

    /// A day's written page, if it has one.
    func index(day: String) -> Int? {
        if day == WidgetSnapshot.day(.now) { return todayIndex }
        return pages.firstIndex { page in
            if case .written(let written) = page.kind { return written.day == day && page.part == 0 }
            return false
        }
    }

    func index(id: String) -> Int? { pages.firstIndex { $0.id == id } }

}

// MARK: - Breaking words across pages

/// Lays words out the way a page will draw them (TextKit, a fixed line) and
/// cuts them where one page ends and the next begins.
enum Paginator {
    struct Piece {
        let text: NSAttributedString
        let height: CGFloat
    }

    static func split(_ text: NSAttributedString, width: CGFloat, height: CGFloat) -> [Piece] {
        guard text.length > 0, width > 10, height > 10 else { return [] }
        let storage = NSTextStorage(attributedString: text)
        let manager = NSLayoutManager()
        manager.usesFontLeading = false
        storage.addLayoutManager(manager)
        var pieces: [Piece] = []
        var laid = 0
        let total = manager.numberOfGlyphs
        // A day of fifty thousand characters is a few dozen pages; this
        // stops a page too small for any line from going round forever.
        while laid < total, pieces.count < 600 {
            let container = NSTextContainer(size: CGSize(width: width, height: height))
            container.lineFragmentPadding = 0
            manager.addTextContainer(container)
            let glyphs = manager.glyphRange(for: container)
            guard glyphs.length > 0 else { break }
            let range = manager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
            let used = manager.usedRect(for: container).height
            pieces.append(Piece(text: trimmed(text.attributedSubstring(from: range), leading: !pieces.isEmpty), height: ceil(used)))
            laid = NSMaxRange(glyphs)
        }
        return pieces.filter { $0.text.length > 0 }
    }

    /// A page that begins where a paragraph ended would open on a blank
    /// line; it opens on its first words instead. Trailing blank lines go
    /// from every page.
    private static func trimmed(_ piece: NSAttributedString, leading: Bool) -> NSAttributedString {
        let string = piece.string as NSString
        var start = 0
        var end = string.length
        let blank = CharacterSet.whitespacesAndNewlines
        if leading {
            while start < end, let scalar = UnicodeScalar(string.character(at: start)), blank.contains(scalar) { start += 1 }
        }
        while end > start, let scalar = UnicodeScalar(string.character(at: end - 1)), blank.contains(scalar) { end -= 1 }
        return piece.attributedSubstring(from: NSRange(location: start, length: end - start))
    }
}

// MARK: - Setting words in their hand

enum BookType {
    /// Ink on the cream of a letter's own paper, whatever the room.
    static let letterInk = UIColor(red: 0.16, green: 0.14, blue: 0.11, alpha: 1)

    static func paragraph(_ pitch: CGFloat, alignment: NSTextAlignment = .natural) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = pitch
        style.maximumLineHeight = pitch
        style.alignment = alignment
        return style
    }

    /// What every line of a page's writing carries: the hand, the ink, and
    /// a line exactly as tall as the rules are apart.
    static func writing(_ layout: BookLayout, ink: UIColor, bold: Bool = false, size: CGFloat? = nil) -> [NSAttributedString.Key: Any] {
        [
            .font: BookHand.font(size ?? layout.fontSize, bold: bold),
            .foregroundColor: ink,
            .paragraphStyle: paragraph(layout.pitch),
        ]
    }

    /// Something printed on the page, not written: small, even capitals.
    static func printed(_ layout: BookLayout, color: UIColor, alignment: NSTextAlignment = .natural) -> [NSAttributedString.Key: Any] {
        [
            .font: UIFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: color,
            .kern: 1.2,
            .paragraphStyle: paragraph(layout.pitch, alignment: alignment),
        ]
    }

    static func dayTitle(_ date: Date) -> String {
        let thisYear = Calendar.current.isDate(date, equalTo: .now, toGranularity: .year)
        return thisYear
            ? date.formatted(.dateTime.weekday(.wide).month(.wide).day())
            : date.formatted(.dateTime.weekday(.wide).month(.wide).day().year())
    }

    /// "Week of November 9": a reflection's heading, where a day's page
    /// has its date.
    static func weekTitle(_ reflection: Reflection) -> String {
        let monday = WeekRange.day(reflection.weekStart)
        return "Week of " + (monday?.formatted(.dateTime.month(.wide).day()) ?? reflection.weekStart)
    }

    /// A day's page: the day, in its ink. (Its date is at the head of the
    /// page, small, not in the writing: build 46.)
    static func written(_ page: DayPage, layout: BookLayout) -> NSAttributedString {
        NSAttributedString(string: page.body, attributes: writing(layout, ink: Ink.named(page.ink).ui))
    }

    /// A week's reflection: the words. Its week is at the head of the page.
    static func reflection(_ reflection: Reflection, layout: BookLayout) -> NSAttributedString {
        NSAttributedString(string: reflection.body, attributes: writing(layout, ink: Ink.black.ui))
    }

    /// A letter, as it was written: who it's from at its head, the words,
    /// and the name signed at the foot with the day it was written.
    static func letter(_ letter: Letter, layout: BookLayout) -> NSAttributedString {
        let sender = letter.sender?.displayName ?? "someone"
        let text = NSMutableAttributedString(
            string: "From \(sender)\n\n",
            attributes: writing(layout, ink: letterInk, bold: true, size: layout.fontSize + 1)
        )
        text.append(NSAttributedString(string: letter.body ?? "", attributes: writing(layout, ink: letterInk)))
        var signed = writing(layout, ink: letterInk, bold: true)
        signed[.paragraphStyle] = paragraph(layout.pitch, alignment: .right)
        text.append(NSAttributedString(string: "\n\n— \(sender)", attributes: signed))
        if let written = letter.createdAt {
            text.append(NSAttributedString(
                string: "\nWRITTEN " + written.formatted(date: .long, time: .omitted).uppercased(),
                attributes: printed(layout, color: letterInk.withAlphaComponent(0.6), alignment: .right)
            ))
        }
        return text
    }
}

// MARK: - Putting the book together

@MainActor
enum BookBuilder {
    private static var last: (key: Int, book: Book)?

    /// The book as it stands: every page, oldest first, a chapter page
    /// before each month's first. Built again only when something in it, or
    /// the page's size, has changed.
    static func book(_ state: AppState, layout: BookLayout, now: Date = .now) -> Book {
        let today = WidgetSnapshot.day(now)
        var hasher = Hasher()
        hasher.combine(layout)
        hasher.combine(today)
        hasher.combine(state.journalWritable)
        hasher.combine(state.journalPages)
        hasher.combine(state.threads)
        hasher.combine(state.lettersReceived.opened)
        hasher.combine(state.reflections)
        let key = hasher.finalize()
        if let last, last.key == key { return last.book }
        let made = build(state, layout: layout, now: now, today: today)
        last = (key, made)
        return made
    }

    private struct Leaf {
        let day: Date
        /// Within a day: what was kept, then what arrived, then how the
        /// week was, and last what was written about it. The day's own
        /// page closes the day, so today's is always the last page of the
        /// book and everything else is behind it (build 46; it opened the
        /// day in build 45, when the book was read from the front).
        let order: Int
        let moment: Date
        let pages: [BookPage]
    }

    private static func build(_ state: AppState, layout: BookLayout, now: Date, today: String) -> Book {
        let calendar = Calendar.current
        var leaves: [Leaf] = []

        for page in state.journalPages {
            guard let date = WeekRange.day(page.day) else { continue }
            let pieces = Paginator.split(
                BookType.written(page, layout: layout), width: layout.textWidth, height: layout.textHeight
            )
            let pages = pieces.enumerated().map { part, piece in
                BookPage(
                    id: "w-\(page.id)-\(part)", date: date, kind: .written(page),
                    text: piece.text, textHeight: piece.height, part: part, parts: pieces.count
                )
            }
            leaves.append(Leaf(day: date, order: 8, moment: date, pages: pages))
        }

        for thread in state.threads {
            for memory in thread.memories {
                let moment = memory.takenAt ?? memory.anchoredAt ?? memory.date.flatMap(WeekRange.day) ?? .distantPast
                let kind: BookPage.Kind = memory.isTombstone || memory.urls == nil
                    ? .tombstone(memory)
                    : .photo(HeldPage(memory: memory, friend: thread.friend))
                let page = BookPage(id: "p-\(memory.id)", date: moment, kind: kind)
                leaves.append(Leaf(day: calendar.startOfDay(for: moment), order: 1, moment: moment, pages: [page]))
            }
        }

        for letter in state.lettersReceived.opened where letter.body != nil {
            let moment = letter.openedAt ?? letter.deliveryDay ?? letter.createdAt ?? now
            let pieces = Paginator.split(
                BookType.letter(letter, layout: layout),
                width: layout.letterTextWidth, height: CGFloat(layout.letterRows) * layout.pitch
            )
            let pages = pieces.enumerated().map { part, piece in
                BookPage(
                    id: "l-\(letter.id)-\(part)", date: moment, kind: .letter(letter),
                    text: piece.text, textHeight: piece.height, part: part, parts: pieces.count
                )
            }
            leaves.append(Leaf(day: calendar.startOfDay(for: moment), order: 2, moment: moment, pages: pages))
        }

        for reflection in state.reflections {
            guard let weekEnd = WeekRange.day(reflection.weekEnd) else { continue }
            // At the end of its week; or, written before the week was out,
            // on the day it was written, not ahead of today.
            let sunday = min(weekEnd, calendar.startOfDay(for: reflection.createdAt))
            let pieces = Paginator.split(
                BookType.reflection(reflection, layout: layout), width: layout.textWidth, height: layout.textHeight
            )
            let pages = pieces.enumerated().map { part, piece in
                BookPage(
                    id: "r-\(reflection.id)-\(part)", date: sunday, kind: .reflection(reflection),
                    text: piece.text, textHeight: piece.height, part: part, parts: pieces.count
                )
            }
            leaves.append(Leaf(day: sunday, order: 3, moment: reflection.createdAt, pages: pages))
        }

        leaves.sort { ($0.day, $0.order, $0.moment) < ($1.day, $1.order, $1.moment) }

        // Today's page is always in the book: written, or waiting.
        let todayStart = calendar.startOfDay(for: now)
        if state.journalWritable, !state.journalPages.contains(where: { $0.day == today }) {
            let blank = BookPage(id: "today", date: todayStart, kind: .today)
            // After everything else: the book ends on the page being lived.
            leaves.append(Leaf(day: max(todayStart, leaves.last?.day ?? todayStart), order: 9, moment: now, pages: [blank]))
        }

        var pages: [BookPage] = []
        var chapter: DateComponents?
        for leaf in leaves where !leaf.pages.isEmpty {
            let month = calendar.dateComponents([.year, .month], from: leaf.day)
            if month != chapter {
                chapter = month
                let first = calendar.date(from: month) ?? leaf.day
                pages.append(BookPage(
                    id: String(format: "c-%04d-%02d", month.year ?? 0, month.month ?? 0), date: first, kind: .chapter
                ))
            }
            pages.append(contentsOf: leaf.pages)
        }
        return Book(pages: pages)
    }
}
