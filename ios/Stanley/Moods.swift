import SwiftUI

// The mark on a day (build 52; the answer sheet since build 65). After a
// photo goes up, five small empty circles under the journal's question; a
// tap fills one. And on a screen of its own over the Journal tab's covers
// (since build 72; at the end of each month's chapter of your own book
// until then), the month as an exam's answer sheet:
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

/// The month's answer sheet, standing alone (build 72; on a page of your
/// own book from build 65 until then): the Journal tab presents it over the
/// covers, from the card at the end of the deck or from your cover's five
/// bubbles. There are several books and one set of days, so it's in none of
/// them. At its head the month and year, the question in the hand, and the
/// five shades unlabelled; under that the month's form. A swipe or the
/// chevrons go back through the months, as far as the one you joined in and
/// no further. Only this month's today row takes a mark; every other row,
/// and every month gone by, is there to read.
struct MarkSheetScreen: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    /// The months it can turn to, oldest first, this month last.
    private let months: [Date]
    @State private var at: Int

    init(joined: Date?) {
        let months = MarkSheet.months(joined: joined)
        self.months = months
        _at = State(initialValue: max(0, months.count - 1))
    }

    var body: some View {
        let ink = Ink.black.color
        NavigationStack {
            VStack(spacing: 0) {
                header(ink: ink)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
                TabView(selection: $at) {
                    ForEach(months.indices, id: \.self) { index in
                        MarkSheetMonth(
                            rows: MarkSheet.rows(month: months[index], marks: state.moods),
                            mark: { level in Task { _ = await state.setMark(level) } }
                        )
                        .padding(.horizontal, 24)
                        .padding(.bottom, 8)
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
            .background(BookPaper.page.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationBackground(BookPaper.page)
    }

    /// "November 2026" between its chevrons, the question under it in the
    /// hand, and the five shades as the scale, with no words on them.
    private func header(ink: Color) -> some View {
        let month = months.indices.contains(at) ? months[at] : .now
        return VStack(spacing: 8) {
            HStack(spacing: 0) {
                chevron("chevron.left", label: MarkSheet.previousMonth, enabled: at > 0) { at -= 1 }
                Spacer(minLength: 4)
                Text(month.formatted(.dateTime.month(.wide).year()))
                    .font(.system(.title, design: .rounded).weight(.medium))
                    .foregroundStyle(ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 4)
                chevron("chevron.right", label: MarkSheet.nextMonth, enabled: at < months.count - 1) { at += 1 }
            }
            Text(MarkSheet.question)
                .font(Font(BookHand.font(19)))
                .foregroundStyle(BookPaper.quiet)
            Swatches(ink: ink)
                .padding(.top, 2)
        }
    }

    private func chevron(_ symbol: String, label: String, enabled: Bool, go: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) { go() }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .medium))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Ink.black.color.opacity(enabled ? 0.8 : 0.18))
        .disabled(!enabled)
        .accessibilityLabel(label)
    }
}

/// The five shades a mark can leave, lightest to darkest, as a row of small
/// squares: the scale, with no labels and no numbers. Decorative to
/// VoiceOver, which reads each bubble's place instead ("3 of 5").
private struct Swatches: View {
    let ink: Color

    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...5, id: \.self) { level in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(ink.opacity(MarkSheet.shade(level)))
                    .overlay {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .strokeBorder(ink.opacity(0.2), lineWidth: 0.5)
                    }
                    .frame(width: 12, height: 12)
            }
        }
        .accessibilityHidden(true)
    }
}

/// One month's form: a row a day, five bubbles across, faint registration
/// squares in three corners, and at the foot the month small, a square a
/// day. Sized by the room it's given: the rows share the height, today's a
/// little taller for a thumb.
struct MarkSheetMonth: View {
    let rows: [MarkSheet.Row]
    let mark: (Int?) -> Void

    /// The registration squares' side, and the room the foot takes.
    private static let registration: CGFloat = 7
    private static let footHeight: CGFloat = 58
    /// How much taller today's row is than the rest: room for a thumb.
    private static let todayExtra: CGFloat = 12

    var body: some View {
        let ink = Ink.black.color
        GeometryReader { proxy in
            let width = proxy.size.width
            let top = Self.registration + 12
            let hasToday = rows.contains { $0.when == .today }
            let room = proxy.size.height - top - Self.footHeight - (hasToday ? Self.todayExtra : 0)
            let rowHeight = min(24, max(10, (room / CGFloat(max(rows.count, 1))).rounded(.down)))
            let bubble = min(15, max(8, rowHeight - 6))
            // The five spread across as a form's are, a little in from the
            // right edge.
            let column = min(56, (width - 60) / 5)
            VStack(alignment: .leading, spacing: 0) {
                Color.clear.frame(height: top)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(rows, id: \.day) { row in
                        self.row(row, height: row.when == .today ? rowHeight + Self.todayExtra : rowHeight,
                                 bubble: row.when == .today ? min(18, bubble + 3) : bubble, column: column, ink: ink)
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel(MarkSheet.sheetName)
                foot(width: width, ink: ink)
                    .frame(width: width, height: Self.footHeight, alignment: .bottom)
            }
            .frame(width: width, alignment: .topLeading)
            .overlay(alignment: .topLeading) { square(ink) }
            .overlay(alignment: .topTrailing) { square(ink) }
            .overlay(alignment: .bottomLeading) { square(ink) }
        }
    }

    // MARK: a row

    /// A row. To the eye it's a date and five bare bubbles; to VoiceOver
    /// (build 66) it reads as its date, and each bubble as its day and its
    /// place along the five ("Sunday 15, 3 of 5"), the filled one selected.
    /// Today's five are buttons. A day gone by reads as its date, then its
    /// filled bubble, or "not marked"; its empty bubbles, which say
    /// nothing, are left out, and it takes no tap (build 72: it turned to
    /// that day's page while the sheet was in the book). Days to come
    /// aren't read at all. Nothing visible is added for any of it.
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
        case .today, .past:
            line
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

    /// A faint square in a corner, as a form a machine reads has.
    private func square(_ ink: Color) -> some View {
        Rectangle()
            .fill(ink.opacity(0.2))
            .frame(width: Self.registration, height: Self.registration)
            .accessibilityHidden(true)
    }

    /// The whole month small: a square a day, in as much ink as its mark,
    /// the same ink for all five, and the one line in the hand. Decorative:
    /// VoiceOver reads the sheet above it, not this (build 66). Squares and
    /// line are drawn in one `Canvas`, whose contents VoiceOver never sees;
    /// the line as a `Text` was still read with `accessibilityHidden` on it.
    private func foot(width room: CGFloat, ink: Color) -> some View {
        let count = CGFloat(max(rows.count, 1))
        let step = min(10, ((room - 2 * (Self.registration + 10)) / count).rounded(.down))
        let side = max(4, step - 2)
        let strip = count * step - (step - side)
        let quiet = BookPaper.quiet
        let rows = self.rows
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

/// The card at the end of the covers (build 72): your days, which belong to
/// no journal. Visibly not a book: plain paper with the form's registration
/// squares, no glass, no title page, no volume line. The month's name in the
/// hand, its year small, and the month as a small calendar of squares, one
/// a day, each in as much ink as its mark; today ringed; the days to come
/// barely there. A tap opens the sheet.
struct DaysCard: View {
    @Environment(AppState.self) private var state
    @Environment(\.colorScheme) private var colorScheme
    let size: CGSize
    let open: () -> Void

    var body: some View {
        let scale = size.width / 290
        let ink = Ink.black.color
        let now = Date.now
        let rows = MarkSheet.rows(month: now, marks: state.moods, now: now)
        let corner = 30 * scale
        let inset = 26 * scale
        Button(action: open) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(BookPaper.page)
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(ink.opacity(0.12), lineWidth: 0.5)
                VStack(alignment: .leading, spacing: 0) {
                    Text(now.formatted(.dateTime.month(.wide)))
                        .font(.custom(BookHand.font(44, bold: true).fontName, fixedSize: 40 * scale))
                        .foregroundStyle(ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(now.formatted(.dateTime.year()))
                        .font(.system(size: 9 * scale, weight: .semibold))
                        .tracking(2.6 * scale)
                        .foregroundStyle(BookPaper.quiet)
                        .padding(.top, 2 * scale)
                    Spacer(minLength: 12 * scale)
                    MonthSquares(rows: rows, ink: ink, width: size.width - 2 * inset)
                    Spacer(minLength: 12 * scale)
                }
                .padding(.horizontal, inset)
                .padding(.top, inset + 10 * scale)
                .padding(.bottom, inset)
                .frame(width: size.width, height: size.height, alignment: .topLeading)
                // The form's three registration squares.
                ForEach(Array(corners(scale: scale).enumerated()), id: \.offset) { _, point in
                    Rectangle()
                        .fill(ink.opacity(0.2))
                        .frame(width: 6 * scale, height: 6 * scale)
                        .offset(x: point.x, y: point.y)
                }
            }
            .frame(width: size.width, height: size.height)
            .compositingGroup()
            .shadow(color: CoverTone.shadow(colorScheme), radius: 18 * scale, x: 8 * scale, y: 12 * scale)
            .contentShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        }
        .buttonStyle(PressedCard())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(MarkSheet.daysName), \(now.formatted(.dateTime.month(.wide).year())). \(MarkSheet.daysLine).")
        .accessibilityHint(MarkSheet.daysHint)
        .accessibilityAddTraits(.isButton)
    }

    private func corners(scale: CGFloat) -> [CGPoint] {
        let side = 6 * scale
        let edge = 16 * scale
        return [
            CGPoint(x: edge, y: edge),
            CGPoint(x: size.width - edge - side, y: edge),
            CGPoint(x: edge, y: size.height - edge - side),
        ]
    }
}

/// The month as a calendar of small squares, a week to a line from the
/// calendar's own first weekday, with no numbers and no weekday letters.
private struct MonthSquares: View {
    let rows: [MarkSheet.Row]
    let ink: Color
    let width: CGFloat

    var body: some View {
        let calendar = Calendar.current
        let lead = rows.first.map { (calendar.component(.weekday, from: $0.date) - calendar.firstWeekday + 7) % 7 } ?? 0
        let cells: [MarkSheet.Row?] = Array(repeating: nil, count: lead) + rows.map { Optional($0) }
        let gap = (width * 0.035).rounded()
        let side = min(28, ((width - 6 * gap) / 7).rounded(.down))
        let columns = Array(repeating: GridItem(.fixed(side), spacing: gap), count: 7)
        LazyVGrid(columns: columns, alignment: .leading, spacing: gap) {
            ForEach(cells.indices, id: \.self) { index in
                if let row = cells[index] {
                    cell(row, side: side)
                } else {
                    Color.clear.frame(width: side, height: side)
                }
            }
        }
        .frame(width: 7 * side + 6 * gap, alignment: .leading)
    }

    private func cell(_ row: MarkSheet.Row, side: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: side * 0.14, style: .continuous)
        return shape
            .fill(ink.opacity(MarkSheet.shade(row.level)))
            .overlay {
                shape.strokeBorder(
                    ink.opacity(row.when == .today ? 0.7 : row.when == .future ? 0.08 : 0.22),
                    lineWidth: row.when == .today ? 1.2 : 0.5
                )
            }
            .frame(width: side, height: side)
    }
}

/// A card that gives a little under the thumb, as the covers do.
private struct PressedCard: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
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
