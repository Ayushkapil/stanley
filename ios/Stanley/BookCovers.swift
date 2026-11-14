import SwiftUI

// The covers (build 52, from the brief of 2026-11-14). The Journal tab
// opens to two books lying side by side: your own, and the shared one
// ("Ours"). Build 45 had a cover and build 46 took it away: it was a flat
// rounded rectangle with words in the middle, no craft. This one is an
// object. A spine down the left with the roundness of a spine; the page
// block showing along the right, a little uneven, so it's plainly full of
// paper; a linen weave in the cloth; the title pressed into it, not
// printed on it; a ribbon hanging from the foot in the accent; the
// corners a shade darker, as a book's are once it's been handled. The
// spine and the page edges grow with what's written: ten pages is a thin
// book, a hundred a thick one. In the dark the cloth is oxblood (yours) or
// forest (ours), never gray on black: a dark book is still a book.

/// The cloth a book is bound in: yours oxblood, the shared one forest, so
/// the two are never confused.
enum BookCloth {
    case mine, ours

    private func rgb(_ scheme: ColorScheme) -> (Double, Double, Double) {
        let dark = scheme == .dark
        switch self {
        case .mine: return dark ? (0.31, 0.10, 0.11) : (0.48, 0.17, 0.16)
        case .ours: return dark ? (0.11, 0.23, 0.17) : (0.18, 0.35, 0.26)
        }
    }

    func color(_ scheme: ColorScheme) -> Color {
        let (r, g, b) = rgb(scheme)
        return Color(red: r, green: g, blue: b)
    }

    /// The cloth where a die has pressed it: darker.
    func stamp(_ scheme: ColorScheme) -> Color {
        let (r, g, b) = rgb(scheme)
        return Color(red: r * 0.7, green: g * 0.7, blue: b * 0.7)
    }
}

/// One book, closed, seen from the front with its spine and fore-edge just
/// showing. `pages` is how much is in it; it decides how thick it looks
/// and is never shown as a number.
struct BookCover: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    var subtitle: String?
    let cloth: BookCloth
    let pages: Int
    let accent: Color
    /// The room it has across; the book is narrower by the thickest its
    /// page edges can grow, so it never shifts as it grows.
    let width: CGFloat

    /// The page block's depth: ten pages thin, a hundred thick.
    static func thickness(_ pages: Int) -> CGFloat { min(18, 2 + 0.16 * CGFloat(max(pages, 0))) }

    private var board: CGFloat { width - 20 }
    private var height: CGFloat { (board * 1.42).rounded() }
    private var depth: CGFloat { Self.thickness(pages) }
    /// The spine's own width grows with the book, a little.
    private var spine: CGFloat { (8 + depth * 0.95).rounded() }

    var body: some View {
        let dark = colorScheme == .dark
        let base = cloth.color(colorScheme)
        HStack(alignment: .center, spacing: 0) {
            front(base: base, dark: dark)
                .frame(width: board, height: height)
            edges(dark: dark, base: base)
                .frame(width: depth + 2, height: height)
        }
        // The ribbon hangs out of the foot, from between the pages.
        .background(alignment: .bottomLeading) {
            Ribbon()
                .fill(accent.opacity(dark ? 0.85 : 1))
                .frame(width: 8, height: 30)
                .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
                .offset(x: spine + (board - spine) * 0.7, y: 24)
        }
        .compositingGroup()
        .shadow(color: .black.opacity(dark ? 0.7 : 0.22), radius: dark ? 14 : 9, x: 2, y: 8)
        .frame(width: width, alignment: .leading)
    }

    // MARK: the front board

    private func front(base: Color, dark: Bool) -> some View {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: 2, bottomLeadingRadius: 2, bottomTrailingRadius: 4, topTrailingRadius: 4,
            style: .continuous
        )
        return ZStack(alignment: .topLeading) {
            base
            Weave(seed: cloth == .mine ? 11 : 29)
                .opacity(dark ? 0.7 : 1)
            // The spine, round: dark where it turns away, a little light
            // where it catches it, then into the hinge.
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.42), location: 0),
                    .init(color: .black.opacity(0.12), location: 0.28),
                    .init(color: .white.opacity(dark ? 0.06 : 0.1), location: 0.5),
                    .init(color: .black.opacity(0.04), location: 0.78),
                    .init(color: .black.opacity(0.16), location: 1),
                ],
                startPoint: .leading, endPoint: .trailing
            )
            .frame(width: spine)
            // The hinge: a groove, and the board's edge just past it.
            Rectangle()
                .fill(LinearGradient(
                    colors: [.black.opacity(0), .black.opacity(0.26), .black.opacity(0)],
                    startPoint: .leading, endPoint: .trailing
                ))
                .frame(width: 4)
                .offset(x: spine + 1.5)
            Rectangle()
                .fill(.white.opacity(dark ? 0.05 : 0.09))
                .frame(width: 1)
                .offset(x: spine + 4.5)
            stamped(base: base)
            corners
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(.black.opacity(0.25), lineWidth: 0.5))
    }

    /// The title, pressed into the cloth: darker than it, in shadow along
    /// its top, catching the light along its foot. A blind-stamped frame
    /// round it.
    private func stamped(base: Color) -> some View {
        let fill = cloth.stamp(colorScheme)
        let inset: CGFloat = 12
        let face = board - spine - 6
        return ZStack {
            RoundedRectangle(cornerRadius: 2)
                .strokeBorder(
                    fill.shadow(.inner(color: .black.opacity(0.6), radius: 0.6, x: 0.4, y: 0.8)),
                    lineWidth: 1.2
                )
                .shadow(color: .white.opacity(0.12), radius: 0, x: 0, y: 0.6)
                .frame(width: face - inset * 2, height: height - inset * 2)
            VStack(spacing: 6) {
                Text(title)
                    .font(.custom(BookHand.font(26, bold: true).fontName, fixedSize: 26))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.5)
                if let subtitle {
                    Text(subtitle)
                        .font(.custom(BookHand.font(15).fontName, fixedSize: 15))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }
            .foregroundStyle(fill.shadow(.inner(color: .black.opacity(0.75), radius: 0.8, x: 0.5, y: 1)))
            .shadow(color: .white.opacity(0.16), radius: 0, x: 0, y: 0.8)
            .frame(width: face - inset * 2 - 16)
            .position(x: face / 2, y: height * 0.36)
        }
        .frame(width: face, height: height)
        .offset(x: spine + 6)
        .accessibilityHidden(true)
    }

    /// A book that's been handled: its corners a shade darker.
    private var corners: some View {
        let reach = board * 0.5
        return ZStack {
            ForEach(Array([UnitPoint.topLeading, .topTrailing, .bottomLeading, .bottomTrailing].enumerated()), id: \.offset) { _, corner in
                RadialGradient(
                    colors: [.black.opacity(0.24), .clear],
                    center: corner, startRadius: 0, endRadius: reach
                )
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: the page block and the back board

    private func edges(dark: Bool, base: Color) -> some View {
        Canvas { context, size in
            let block = CGRect(x: 0, y: 3, width: depth, height: size.height - 6)
            // The paper, its tone a little warmer at the middle.
            let paper = dark ? Color(red: 0.62, green: 0.58, blue: 0.51) : Color(red: 0.95, green: 0.92, blue: 0.85)
            context.fill(Path(block), with: .color(paper))
            // Leaf after leaf: fine lines, each a touch longer or shorter
            // than the next, so the block is uneven as paper is.
            var random = SeededRandom(seed: UInt64(pages) &+ (cloth == .mine ? 3 : 7))
            var x: CGFloat = 0.6
            while x < depth {
                let top = block.minY + random.next() * 1.4
                let bottom = block.maxY - random.next() * 1.4
                var line = Path()
                line.move(to: CGPoint(x: x, y: top))
                line.addLine(to: CGPoint(x: x, y: bottom))
                context.stroke(line, with: .color(.black.opacity(0.07 + random.next() * 0.12)), lineWidth: 0.4)
                x += 0.9 + random.next() * 0.5
            }
            // Shade at the head and foot of the block, where it turns.
            context.fill(
                Path(block),
                with: .linearGradient(
                    Gradient(stops: [
                        .init(color: .black.opacity(0.22), location: 0),
                        .init(color: .clear, location: 0.1),
                        .init(color: .clear, location: 0.9),
                        .init(color: .black.opacity(0.22), location: 1),
                    ]),
                    startPoint: CGPoint(x: 0, y: block.minY), endPoint: CGPoint(x: 0, y: block.maxY)
                )
            )
            // In shadow where it meets the front board.
            context.fill(
                Path(CGRect(x: 0, y: block.minY, width: min(3, depth), height: block.height)),
                with: .color(.black.opacity(0.18))
            )
            // The back board's edge, behind the pages.
            let back = CGRect(x: depth, y: 0.5, width: 2, height: size.height - 1)
            context.fill(Path(roundedRect: back, cornerRadius: 1), with: .color(base))
            context.fill(Path(roundedRect: back, cornerRadius: 1), with: .color(.black.opacity(0.3)))
        }
    }
}

/// The ribbon's end: cut in a V.
private struct Ribbon: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - rect.width * 0.6))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// Linen: fine threads both ways, each a little different from the next.
private struct Weave: View {
    let seed: UInt64

    var body: some View {
        Canvas { context, size in
            var random = SeededRandom(seed: seed)
            var y: CGFloat = 0
            while y < size.height {
                var line = Path()
                line.move(to: CGPoint(x: 0, y: y))
                line.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(line, with: .color(.black.opacity(0.05 + random.next() * 0.07)), lineWidth: 0.6)
                y += 1.3
            }
            var x: CGFloat = 0
            while x < size.width {
                var line = Path()
                line.move(to: CGPoint(x: x, y: 0))
                line.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(line, with: .color(.white.opacity(0.025 + random.next() * 0.05)), lineWidth: 0.6)
                x += 1.3
            }
            // A few slubs, as linen has.
            for _ in 0..<Int(size.width * size.height / 900) {
                let at = CGPoint(x: random.next() * size.width, y: random.next() * size.height)
                let slub = CGRect(x: at.x, y: at.y, width: 3 + random.next() * 6, height: 0.8)
                context.fill(Path(slub), with: .color(.white.opacity(0.05)))
            }
        }
        .drawingGroup()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The same numbers every time for the same seed, so a cover is drawn the
/// same way each time it's drawn.
struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed &* 0x9E3779B97F4A7C15 | 1 }

    /// Between 0 and 1.
    mutating func next() -> CGFloat {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return CGFloat(state % 10_000) / 10_000
    }
}

// MARK: - The two books, side by side

/// What the Journal tab opens to: your book and the shared one on the
/// table, a tap opening either. A long press on your book's title names
/// it. Without a shared journal (no circle, an older server) your book is
/// there alone.
struct CoverShelf: View {
    @Environment(AppState.self) private var state
    let layout: BookLayout
    let accent: Color
    let showsOurs: Bool
    let open: (Bool) -> Void
    @State private var renaming = false
    @State private var name = ""

    /// How much is in each book: what decides how thick it is.
    private var minePages: Int { state.journalPages.count + state.reflections.count }
    private var oursPages: Int {
        state.sharedDays.reduce(0) { sum, day in
            sum + day.singles.count + day.spreads.reduce(0) { $0 + 1 + ($1.right == nil ? 0 : 1) }
        }
    }

    var body: some View {
        let across = layout.width - layout.safeLeading
        let gap: CGFloat = 26
        let each = showsOurs
            ? min(200, (across - 40 - gap) / 2)
            : min(240, across - 120)
        VStack(spacing: 0) {
            JournalMasthead(title: "Journal", hand: true) { EmptyView() }
                .padding(.horizontal, 20)
                .padding(.top, layout.safeTop + 8)
            Spacer(minLength: 16)
            HStack(alignment: .top, spacing: gap) {
                book(.mine, width: each)
                if showsOurs { book(.ours, width: each) }
            }
            .padding(.bottom, 34)
            Spacer(minLength: 16)
            Spacer().frame(height: BookLayout.foot)
        }
        .frame(width: across, height: layout.height)
        .offset(x: layout.safeLeading)
        .alert("Name your journal", isPresented: $renaming) {
            TextField(JournalName.fallback, text: $name)
            Button("Save") {
                let wanted = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(JournalName.limit))
                Task { await state.renameJournal(wanted) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It's on the cover, and at the head of each month. Leave it empty for \u{201C}\(JournalName.fallback)\u{201D}.")
        }
    }

    @ViewBuilder
    private func book(_ cloth: BookCloth, width: CGFloat) -> some View {
        let mine = cloth == .mine
        let title = mine ? JournalName.shown(state.journalTitle) : "Ours"
        let subtitle = mine ? state.profile?.displayName : state.circle?.name
        BookCover(
            title: title, subtitle: subtitle, cloth: cloth,
            pages: mine ? minePages : oursPages, accent: accent, width: width
        )
        .contentShape(Rectangle())
        .onTapGesture { open(!mine) }
        // The title is where a long press names your book.
        .overlay(alignment: .top) {
            if mine {
                Color.clear
                    .frame(width: width - 40, height: width * 0.62)
                    .contentShape(Rectangle())
                    .onTapGesture { open(false) }
                    .onLongPressGesture(minimumDuration: 0.45) {
                        name = state.journalTitle ?? ""
                        renaming = true
                    }
                    .offset(y: width * 0.12)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(mine ? "\(title), your journal" : "Ours, the shared journal of \(subtitle ?? "your circle")")
        .accessibilityHint("Opens it")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { open(!mine) }
        .accessibilityActions {
            if mine {
                Button("Rename") {
                    name = state.journalTitle ?? ""
                    renaming = true
                }
            }
        }
    }
}
