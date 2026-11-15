import SwiftUI

// The mark on a day (build 52; the answer sheet since build 65). After a
// photo goes up, five small empty circles under the journal's question; a
// tap fills one. And in your own book, at the end of each month's chapter
// (this month's after today's page), the month as an exam's answer sheet:
// a row a day, five bubbles a row with no labels and no numbers, faint
// registration squares in three corners as a real form has, and at the
// foot the whole month as small squares, one a day, shaded by its mark,
// over one line in the hand. Only today's row takes a mark (`MarkSheet`:
// the phone's own day); a day gone by is never filled in, and the days to
// come are faint. Nothing is counted, joined, averaged or said about it.
// Yours alone, it never fades, and it's kept in one place, `day_moods`.

/// The five dots under today's photo. The one filled is a little larger,
/// in the accent; a tap on it again empties it.
struct MoodDots: View {
    @AppStorage("stanley.atmosphere") private var raw = "auto"
    let score: Int?
    let set: (Int?) -> Void
    /// Shown at once, before the server has it.
    @State private var picked: Int??

    private var shown: Int? { picked ?? score }

    var body: some View {
        let accent = Atmosphere.resolve(raw).palette.accent
        HStack(spacing: 0) {
            ForEach(1...5, id: \.self) { at in
                Button {
                    let next = shown == at ? nil : at
                    picked = .some(next)
                    if next != nil { Haptics.moodMarked() }
                    set(next)
                } label: {
                    MoodDot(filled: shown == at, accent: accent, empty: Color.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(MarkSheet.spokenBubble(.now, at))
                .accessibilityAddTraits(shown == at ? .isSelected : [])
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("A mark on your day. Only you see it.")
        .onChange(of: score) { _, _ in picked = nil }
    }

}

/// One circle of five: filled, 14pt in the accent; empty, 12pt and faint.
struct MoodDot: View {
    let filled: Bool
    let accent: Color
    let empty: Color
    var filledSize: CGFloat = 14
    var emptySize: CGFloat = 12
    /// How strong an empty circle is: a little more under a fresh photo,
    /// where it's asking to be tapped; very faint on the month's sheet.
    var faint: Double = 0.35

    var body: some View {
        ZStack {
            if filled {
                Circle().fill(accent).frame(width: filledSize, height: filledSize)
            } else {
                Circle().strokeBorder(empty.opacity(faint), lineWidth: 0.75).frame(width: emptySize, height: emptySize)
            }
        }
        .frame(width: filledSize, height: filledSize)
    }
}

/// A month on a page of the book, as an answer sheet (build 65). Today's
/// row takes a mark; a tap on a day gone by turns to that day's page.
struct MoodSheet: View {
    let month: MoodMonth
    let layout: BookLayout
    let live: Bool
    let open: (String) -> Void
    let mark: (Int?) -> Void

    /// The registration squares' side, and the room the foot takes.
    private static let registration: CGFloat = 7
    private static let footHeight: CGFloat = 58
    /// How much taller today's row is than the rest: room for a thumb.
    private static let todayExtra: CGFloat = 12

    var body: some View {
        let ink = Ink.black.color
        let rows = month.rows
        let top = layout.contentTop + Self.registration + 12
        let hasToday = rows.contains { $0.when == .today }
        let room = layout.contentBottom - top - Self.footHeight - (hasToday ? Self.todayExtra : 0)
        let rowHeight = min(22, max(10, (room / CGFloat(max(rows.count, 1))).rounded(.down)))
        let bubble = min(14, max(8, rowHeight - 6))
        // The five spread across the page as a form's are, a little in
        // from its right edge.
        let column = min(52, (layout.textWidth - 60) / 5)
        ZStack(alignment: .topLeading) {
            registration(ink)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(rows, id: \.day) { row in
                    self.row(row, height: row.when == .today ? rowHeight + Self.todayExtra : rowHeight,
                             bubble: row.when == .today ? min(18, bubble + 3) : bubble, column: column, ink: ink)
                }
            }
            .frame(width: layout.textWidth, alignment: .topLeading)
            .offset(x: layout.left, y: top)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(MarkSheet.sheetName)
            foot(rows: rows, ink: ink)
                .frame(width: layout.textWidth, height: Self.footHeight, alignment: .bottom)
                .offset(x: layout.left, y: layout.contentBottom - Self.footHeight)
        }
    }

    // MARK: a row

    /// A row. To the eye it's a date and five bare bubbles; to VoiceOver
    /// (build 66) it reads as its date, and each bubble as its day and its
    /// place along the five ("Sunday 15, 3 of 5"), the filled one selected.
    /// Today's five are buttons. A day gone by reads as its date, turning
    /// to that day's page, then its filled bubble, or "not marked"; its
    /// empty bubbles, which say nothing, are left out. Days to come aren't
    /// read at all. Nothing visible is added for any of it.
    @ViewBuilder
    private func row(_ row: MarkSheet.Row, height: CGFloat, bubble: CGFloat, column: CGFloat, ink: Color) -> some View {
        let day = MarkSheet.spokenDay(row.date)
        let past = row.when == .past
        // (Each piece is spoken or hidden on its own: hiding a row from
        // above leaves anything inside that's its own element still read,
        // which a dump of the tree showed.)
        let date = Text(Self.label(row.date))
            .font(.system(size: min(11, max(9, height * 0.55)), weight: row.when == .today ? .semibold : .regular)
                .monospacedDigit())
            .foregroundStyle(row.when == .today ? ink : BookPaper.quiet)
            .frame(width: 52, alignment: .leading)
        let line = HStack(spacing: 0) {
            switch row.when {
            case .today:
                date.accessibilityLabel(day)
            case .past:
                date
                    .accessibilityLabel(day)
                    .accessibilityValue(row.level == nil ? MarkSheet.notMarked : "")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint(MarkSheet.pastHint)
                    .accessibilityAction { if live { open(row.day) } }
            case .future:
                date.accessibilityHidden(true)
            }
            ForEach(1...5, id: \.self) { at in
                if row.takesAMark {
                    Button {
                        guard let next = MarkSheet.afterTap(on: at, in: row) else { return }
                        if next != nil { Haptics.moodMarked() }
                        mark(next)
                    } label: {
                        Bubble(filled: row.level == at, size: bubble, ink: ink, strength: 0.6)
                            .frame(width: column, height: height)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!live)
                    .accessibilityLabel(MarkSheet.spokenBubble(row.date, at))
                    .accessibilityHint(MarkSheet.todayHint)
                    .accessibilityAddTraits(row.level == at ? .isSelected : [])
                } else if past, row.level == at {
                    // A day gone by's filled bubble: its day, its place, selected.
                    Bubble(filled: true, size: bubble, ink: ink, strength: 0.3)
                        .frame(width: column)
                        .accessibilityElement()
                        .accessibilityLabel(MarkSheet.spokenBubble(row.date, at))
                        .accessibilityAddTraits(.isSelected)
                } else {
                    // An empty bubble on a day gone by, or any on a day to
                    // come: nothing to read.
                    Bubble(filled: false, size: bubble, ink: ink, strength: 0.3)
                        .frame(width: column)
                        .accessibilityHidden(true)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(height: height)
        .background(alignment: .leading) {
            // Today's row, the one that can still be marked: a faint band.
            if row.when == .today {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(ink.opacity(0.06))
                    .padding(.horizontal, -6)
                    .padding(.vertical, 2)
            }
        }
        switch row.when {
        case .today:
            line
                .accessibilityElement(children: .contain)
                .accessibilityLabel(day)
        case .past:
            // A tap anywhere on the row turns to its day.
            line
                .contentShape(Rectangle())
                .onTapGesture { if live { open(row.day) } }
                .accessibilityElement(children: .contain)
                .accessibilityLabel(day)
        case .future:
            // Still to come: faint, nothing to tap, nothing to read.
            line
                .opacity(0.32)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    // MARK: the form's own marks

    /// Three faint squares in the corners, as a form a machine reads has:
    /// top left, top right, bottom left.
    private func registration(_ ink: Color) -> some View {
        let side = Self.registration
        let corners = [
            CGPoint(x: layout.left, y: layout.contentTop),
            CGPoint(x: layout.left + layout.textWidth - side, y: layout.contentTop),
            CGPoint(x: layout.left, y: layout.contentBottom - side),
        ]
        return ZStack(alignment: .topLeading) {
            ForEach(corners.indices, id: \.self) { at in
                Rectangle()
                    .fill(ink.opacity(0.2))
                    .frame(width: side, height: side)
                    .offset(x: corners[at].x, y: corners[at].y)
            }
        }
        .accessibilityHidden(true)
    }

    /// The whole month small: a square a day, in as much ink as its mark,
    /// the same ink for all five, and the one line in the hand. Decorative:
    /// VoiceOver reads the sheet above it, not this (build 66). Squares and
    /// line are drawn in one `Canvas`, whose contents VoiceOver never sees;
    /// the line as a `Text` was still read with `accessibilityHidden` on it.
    private func foot(rows: [MarkSheet.Row], ink: Color) -> some View {
        let count = CGFloat(max(rows.count, 1))
        let step = min(10, ((layout.textWidth - 2 * (Self.registration + 10)) / count).rounded(.down))
        let side = max(4, step - 2)
        let strip = count * step - (step - side)
        let quiet = BookPaper.quiet
        let room = layout.textWidth
        return Canvas { context, size in
            let left = (size.width - strip) / 2
            for (x, row) in rows.enumerated() {
                let rect = CGRect(x: left + CGFloat(x) * step, y: 0, width: side, height: side)
                let shade = MarkSheet.shade(row.level)
                if shade > 0 {
                    context.fill(Path(rect), with: .color(ink.opacity(shade)))
                }
                context.stroke(
                    Path(rect.insetBy(dx: 0.25, dy: 0.25)),
                    with: .color(ink.opacity(row.when == .future ? 0.08 : 0.2)), lineWidth: 0.5
                )
            }
            // The line, a little smaller if the page is too narrow for it.
            var line = context.resolve(Text(MarkSheet.footLine).font(Font(BookHand.font(15))).foregroundStyle(quiet))
            let width = line.measure(in: CGSize(width: CGFloat.infinity, height: 40)).width
            if width > room {
                let smaller = max(10.5, 15 * room / width)
                line = context.resolve(Text(MarkSheet.footLine).font(Font(BookHand.font(smaller))).foregroundStyle(quiet))
            }
            context.draw(line, at: CGPoint(x: size.width / 2, y: side + 10), anchor: .top)
        }
        .frame(maxWidth: .infinity)
        .frame(height: side + 34)
        .padding(.bottom, Self.registration + 4)
        .accessibilityHidden(true)
    }

    /// "Sat 14": small, at the left of the row.
    private static func label(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated)) + " " + date.formatted(.dateTime.day())
    }
}

/// One bubble on the sheet: a ring, and filled in pencil once marked, a
/// little inside the ring as a pencilled answer is. The same ink for all
/// five: which bubble it is says the mark.
struct Bubble: View {
    let filled: Bool
    let size: CGFloat
    let ink: Color
    /// How strong the empty ring is: stronger on today's row.
    var strength: Double = 0.3

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(ink.opacity(filled ? 0.5 : strength), lineWidth: 0.8)
            if filled {
                Circle()
                    .fill(ink.opacity(0.82))
                    .padding(size * 0.14)
            }
        }
        .frame(width: size, height: size)
    }
}

/// The last few days on your journal's cover (build 65): five bubbles,
/// oldest first and today last, each in as much ink as that day's mark,
/// or an empty ring. Read from the one store of marks, nothing else.
struct LastFiveDays: View {
    let levels: [Int?]
    let ink: Color
    var size: CGFloat = 11

    var body: some View {
        HStack(spacing: size * 0.55) {
            ForEach(levels.indices, id: \.self) { at in
                ZStack {
                    Circle().strokeBorder(ink.opacity(0.45), lineWidth: 0.8)
                    if let level = levels[at] {
                        Circle().fill(ink.opacity(MarkSheet.shade(level)))
                    }
                }
                .frame(width: size, height: size)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(MarkSheet.lastFewName)
        .accessibilityHint(MarkSheet.lastFewHint)
    }
}
