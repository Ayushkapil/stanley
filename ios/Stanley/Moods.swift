import SwiftUI

// The mood grid (build 52, from the brief of 2026-11-14). After a photo
// goes up, five small empty circles under the journal's question; a tap
// fills one. No labels, no numbers, no "1 = bad": five dots. In your own
// book, at the end of each month's chapter, a sheet like an answer sheet:
// a row a day, the date small at the left, five circles across, the one
// filled in the accent; and under it the whole month small, a dot matrix
// a day wide and five high, so each month looks like itself. No lines, no
// graph, nothing that says what it means. Yours alone, and it never fades.

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
                .accessibilityLabel(Self.ordinals[at - 1] + " dot")
                .accessibilityAddTraits(shown == at ? .isSelected : [])
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("A mark on your day. Only you see it.")
        .onChange(of: score) { _, _ in picked = nil }
    }

    static let ordinals = ["First", "Second", "Third", "Fourth", "Fifth"]
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

/// A month's dots on a page of the book: the sheet, and the month small
/// beneath it. A tap on a row turns to that day.
struct MoodSheet: View {
    @AppStorage("stanley.atmosphere") private var raw = "auto"
    let month: MoodMonth
    let layout: BookLayout
    let live: Bool
    let open: (String) -> Void

    /// The month small: a column a day, five rows, its dots 3pt.
    private static let matrixDot: CGFloat = 3
    private static let matrixStep: CGFloat = 4.5
    private var matrixHeight: CGFloat { Self.matrixStep * 5 }

    var body: some View {
        let accent = Atmosphere.resolve(raw).palette.accent
        let rows = max(month.days.count, 1)
        let room = layout.contentBottom - layout.contentTop - matrixHeight - 26
        let rowHeight = min(22, max(12, (room / CGFloat(rows)).rounded(.down)))
        let column = min(34, (layout.textWidth - 64) / 5)
        VStack(alignment: .leading, spacing: 0) {
            ForEach(month.days, id: \.day) { day in
                Button { open(day.day) } label: {
                    HStack(spacing: 0) {
                        Text(Self.label(day.date))
                            .font(.system(size: min(11, rowHeight * 0.62)).monospacedDigit())
                            .foregroundStyle(BookPaper.quiet)
                            .frame(width: 52, alignment: .leading)
                        ForEach(1...5, id: \.self) { at in
                            MoodDot(filled: day.score == at, accent: accent, empty: Ink.black.color, faint: 0.17)
                                .frame(width: column)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(height: rowHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!live)
                .accessibilityLabel(day.date.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                .accessibilityValue(day.score.map { MoodDots.ordinals[$0 - 1] + " dot filled" } ?? "No dot")
                .accessibilityHint("Turns to that day")
            }
            matrix(accent: accent)
                .padding(.top, 18)
                .frame(maxWidth: .infinity, alignment: .center)
                .accessibilityHidden(true)
        }
        .frame(width: layout.textWidth, alignment: .topLeading)
        .offset(x: layout.left, y: layout.contentTop + 4)
    }

    /// The month as a barcode: a column a day, the dot of that day's mark
    /// filled. Nothing joins them.
    private func matrix(accent: Color) -> some View {
        Canvas { context, _ in
            for (x, day) in month.days.enumerated() {
                for row in 0..<5 {
                    let rect = CGRect(
                        x: CGFloat(x) * Self.matrixStep, y: CGFloat(row) * Self.matrixStep,
                        width: Self.matrixDot, height: Self.matrixDot
                    )
                    let filled = day.score == row + 1
                    context.fill(
                        Path(ellipseIn: rect),
                        with: .color(filled ? accent : Ink.black.color.opacity(0.1))
                    )
                }
            }
        }
        .frame(width: CGFloat(max(month.days.count, 1)) * Self.matrixStep, height: matrixHeight)
    }

    /// "Sat 14": small, at the left of the row.
    private static func label(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated)) + " " + date.formatted(.dateTime.day())
    }
}
