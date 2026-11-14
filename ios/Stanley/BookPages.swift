import SwiftUI
import UIKit

// The pages of the journal, drawn (builds 45 and 46). Each is the whole
// page, paper to its edges: ruled where it's written on, plain where
// something is pasted or tucked in, its date small at the head and its
// number at the middle of the foot. This is the one place in Stanley where
// paper is right, so it has a grain; in the dark it's a very dark charcoal,
// so it still reads as a page.

/// What a page can ask the book to do. The book asks before anything is
/// thrown away.
struct BookActions {
    var write: () -> Void = {}
    var edit: (DayPage) -> Void = { _ in }
    var changeInk: (DayPage, Ink) -> Void = { _, _ in }
    var delete: (DayPage) -> Void = { _ in }
    var openPhoto: (HeldPage) -> Void = { _ in }
    var deleteReflection: (Reflection) -> Void = { _ in }
    var deleteLetter: (Letter) -> Void = { _ in }
    var reportLetter: (Letter) -> Void = { _ in }
    /// The circle a page can be shared with (build 51): its name, or nil
    /// where there's no sharing (no circle, or a server that keeps none).
    var shareWith: String?
    var share: (DayPage) -> Void = { _ in }
    var makePrivate: (DayPage) -> Void = { _ in }
    /// In the shared journal: a heart left or taken back, a page reported,
    /// and your own page there edited or taken back.
    var heart: (SharedPage) -> Void = { _ in }
    var reportPage: (SharedPage) -> Void = { _ in }
    var editShared: (SharedPage) -> Void = { _ in }
    var privateShared: (SharedPage) -> Void = { _ in }
}

/// Words set by `BookType`, drawn exactly as `Paginator` measured them: the
/// same TextKit, the same fixed line, so they sit on the page's rules.
struct InkText: UIViewRepresentable {
    let text: NSAttributedString

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView(usingTextLayoutManager: false)
        view.isEditable = false
        view.isSelectable = false
        view.isScrollEnabled = false
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.layoutManager.usesFontLeading = false
        view.clipsToBounds = false
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        // The page speaks for itself (`BookPage.name` and its words below).
        view.accessibilityTraits = .staticText
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        if view.attributedText != text { view.attributedText = text }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        guard let width = proposal.width, let height = proposal.height else { return nil }
        return CGSize(width: width, height: height)
    }
}

/// The paper of a page: its color, its grain, the rules if it's a written
/// page, the shade where it meets the spine and where it falls away at its
/// outer edge.
struct BookSheet: View {
    @Environment(\.colorScheme) private var colorScheme
    let layout: BookLayout
    let lined: Bool

    var body: some View {
        let dark = colorScheme == .dark
        ZStack(alignment: .topLeading) {
            BookPaper.page
            // The paper's tooth: specks in daylight; in the dark the same
            // specks barely catching the light.
            Image(uiImage: PaperGrain.tile)
                .resizable(resizingMode: .tile)
                .opacity(dark ? 0.16 : 0.3)
                .blendMode(dark ? .screen : .normal)
            if lined {
                Canvas { context, size in
                    var path = Path()
                    for row in 1...layout.rows {
                        let y = (layout.contentTop + CGFloat(row) * layout.pitch - layout.ruleRise).rounded() + 0.25
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: size.width, y: y))
                    }
                    context.stroke(path, with: .color(BookPaper.rule), lineWidth: 0.5)
                }
            }
            // Where the page curves down into the spine. Always the left:
            // on a phone one page shows at a time, and every page turns on
            // its left edge.
            LinearGradient(
                colors: [.black.opacity(dark ? 0.4 : 0.07), .clear],
                startPoint: .leading, endPoint: .trailing
            )
            .frame(width: 26)
            .frame(maxWidth: .infinity, alignment: .leading)
            // And the other side, where it falls away to the pages under it.
            LinearGradient(
                colors: [.clear, .black.opacity(dark ? 0.22 : 0.035)],
                startPoint: .leading, endPoint: .trailing
            )
            .frame(width: 7)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(width: layout.width, height: layout.height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// What's written small at the head of a page, top left: its date.
struct PageHeading: View {
    let text: String
    let color: Color
    let layout: BookLayout

    var body: some View {
        Text(text)
            .font(.custom(layout.font.fontName, fixedSize: layout.headSize))
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            // Short of the head's right, where "Mine", "Ours" and "+" are.
            .frame(width: layout.headWidth, alignment: .leading)
            .position(x: layout.left + layout.headWidth / 2, y: layout.headY)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Under the date, smaller: whether a page is shared, and with whom. On a
/// page being read it's there only when the page is shared; on a page
/// being written it always says where the page will land.
struct PageTag: View {
    let text: String
    var color: Color = BookPaper.quiet
    let layout: BookLayout

    var body: some View {
        Text(text)
            .font(.system(size: 9.5, weight: .semibold))
            .tracking(0.9)
            .textCase(.uppercase)
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(width: layout.textWidth, alignment: .leading)
            .position(x: layout.middle, y: layout.tagY)
    }
}

/// The cursor on a blank page, waiting where the first word will go.
private struct WaitingCaret: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let color: Color
    let height: CGFloat
    /// Off in the grid of small pages: nothing blinks there.
    let blinks: Bool
    @State private var lit = true

    var body: some View {
        RoundedRectangle(cornerRadius: 1, style: .continuous)
            .fill(color)
            .frame(width: 2, height: height)
            .opacity(lit ? 1 : 0)
            .onAppear {
                guard blinks, !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.5).delay(0.3).repeatForever(autoreverses: true)) { lit = false }
            }
            .accessibilityHidden(true)
    }
}

/// One page of the journal, whole.
struct BookPageView: View {
    @Environment(AppState.self) private var state
    @Environment(\.colorScheme) private var colorScheme
    /// The ink a new page starts in: the last one used, or the one picked
    /// from the three at the foot of today's blank page.
    @AppStorage(InkWell.key) private var inkRaw = Ink.black.rawValue
    let page: BookPage
    /// Its number, from 1.
    let number: Int
    let layout: BookLayout
    var actions = BookActions()
    /// Off for a thumbnail in the page grid: nothing on it is pressed.
    var live = true

    var body: some View {
        ZStack(alignment: .topLeading) {
            BookSheet(layout: layout, lined: page.lined)
            if let heading = page.heading {
                PageHeading(text: heading, color: headInk, layout: layout)
            }
            // A page of your own that's in a circle's shared journal says so.
            if case .written(let written) = page.kind, written.isShared, page.part == 0 {
                PageTag(text: "Shared with \(written.circleName ?? "your circle")", layout: layout)
            }
            content
            foot
        }
        .frame(width: layout.width, height: layout.height)
        .contentShape(Rectangle())
        .modifier(TodayTap(page: page, actions: actions, live: live))
        .modifier(PageMenu(page: page, actions: actions, live: live))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(page.name)
    }

    /// The date is in the page's own ink where the page is written, a
    /// little let down so it's the smaller thing; plain ink elsewhere.
    private var headInk: Color {
        switch page.kind {
        case .written(let written): Ink.named(written.ink).color.opacity(0.7)
        case .today: Ink.named(inkRaw).color.opacity(0.7)
        default: Ink.black.color.opacity(0.62)
        }
    }

    /// The middle of the foot: the page's number when it's read. Today's
    /// blank page has the three inks there instead, since it's being
    /// written; a month's opening page has nothing, as in a printed book.
    @ViewBuilder
    private var foot: some View {
        switch page.kind {
        case .chapter, .oursEmpty:
            EmptyView()
        case .today where live:
            InkPicker(ink: Binding(get: { Ink.named(inkRaw) }, set: { inkRaw = $0.rawValue }))
                .position(x: layout.middle, y: layout.numberY)
        default:
            Text("\(number)")
                .font(.footnote.monospacedDigit())
                .foregroundStyle(BookPaper.quiet)
                .position(x: layout.middle, y: layout.numberY)
                .accessibilityLabel("Page \(number)")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch page.kind {
        case .chapter:
            chapter
        case .written, .reflection:
            written
        case .today:
            blank
        case .photo(let held):
            pasted { photo(held) }
        case .tombstone(let memory):
            pasted { tombstone(memory) }
        case .letter(let letter):
            pasted { self.letter(letter) }
        case .spread(let spread):
            SpreadView(day: page.date, spread: spread, layout: layout, actions: actions, live: live)
        case .oursEmpty:
            SpreadView(day: page.date, spread: nil, layout: layout, actions: actions, live: live)
        }
    }

    // MARK: a month's opening page

    private var chapter: some View {
        ZStack(alignment: .topLeading) {
            // What the journal is called, small, where a day's page has
            // its date (it had a cover to be written on until build 46).
            PageHeading(text: JournalName.shown(state.journalTitle), color: BookPaper.quiet, layout: layout)
            month
        }
        .frame(width: layout.width, height: layout.height)
    }

    private var month: some View {
        VStack(spacing: 14) {
            Text(page.date.formatted(.dateTime.month(.wide)))
                .font(.custom(BookHand.font(44, bold: true).fontName, size: 44, relativeTo: .largeTitle))
                .foregroundStyle(Ink.black.color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Rectangle()
                .fill(BookPaper.quiet.opacity(0.5))
                .frame(width: 44, height: 0.5)
            Text(page.date.formatted(.dateTime.year()))
                .font(.custom(BookHand.font(22).fontName, size: 22, relativeTo: .title3))
                .foregroundStyle(BookPaper.quiet)
        }
        .frame(width: layout.textWidth)
        .position(x: layout.middle, y: layout.height * 0.44)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: a written page

    private var written: some View {
        ZStack(alignment: .topLeading) {
            if let text = page.text {
                InkText(text: text)
                    .frame(width: layout.textWidth, height: layout.textHeight, alignment: .topLeading)
                    .accessibilityLabel(text.string)
            }
            // The week's photos that are still there, under a reflection's
            // last lines when there's room on the page for them.
            if case .reflection(let reflection) = page.kind, page.part == page.parts - 1,
               !reflection.photos.isEmpty,
               page.textHeight + layout.pitch + 64 <= layout.textHeight {
                HStack(spacing: 10) {
                    ForEach(reflection.photos.prefix(7)) { photo in
                        WeekPhotoThumb(photo: photo, width: 36)
                    }
                }
                .offset(y: page.textHeight + layout.pitch * 0.6)
            }
        }
        .frame(width: layout.textWidth, height: layout.textHeight, alignment: .topLeading)
        .offset(x: layout.left, y: layout.contentTop)
    }

    /// Today's page, waiting: ruled, its date at the head, and the cursor
    /// on the first line. A tap anywhere on the page begins writing
    /// (`TodayTap`); this is the same thing for VoiceOver.
    private var blank: some View {
        ZStack(alignment: .topLeading) {
            WaitingCaret(color: Ink.named(inkRaw).color, height: layout.pitch - 7, blinks: live)
                .offset(x: layout.left, y: layout.contentTop + 4)
            Button(action: actions.write) {
                Color.clear
                    .frame(width: layout.textWidth, height: layout.textHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!live)
            .offset(x: layout.left, y: layout.contentTop)
            .accessibilityLabel("Today's page is blank. Write it.")
        }
    }

    // MARK: something pasted or tucked in

    /// A plain page with one thing on it, under the date.
    private func pasted<Inner: View>(@ViewBuilder _ inner: () -> Inner) -> some View {
        inner()
            .frame(width: layout.textWidth, height: layout.textHeight, alignment: .top)
            .offset(x: layout.left, y: layout.contentTop)
    }

    /// A kept photo, pasted in a little crooked, with what was written
    /// under it in a hand.
    private func photo(_ held: HeldPage) -> some View {
        let memory = held.memory
        let mine = state.myId != nil && held.friend.id == state.myId
        // The print gives up height to the words under it, never the
        // other way.
        let room = layout.textHeight
        let width = min(layout.textWidth * 0.84, (room * 0.6) * PhotoShape.aspect)
        let lean = max(0.7, abs(PrintTilt.degrees(memory.id)) * 1.6) * (number.isMultiple(of: 2) ? 1 : -1)
        return VStack(alignment: .leading, spacing: 14) {
            Button { actions.openPhoto(held) } label: {
                Color.clear
                    .frame(width: width, height: width / PhotoShape.aspect)
                    .overlay {
                        SignedImage(url: memory.urls.flatMap { state.api.absoluteURL($0.image) }) { image in
                            image.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Rectangle().fill(BookPaper.quiet.opacity(0.15))
                        }
                    }
                    .asPrint(corner: 4, tilt: lean)
                    // Pasted in: the page shows a little shadow under it.
                    .shadow(color: .black.opacity(colorScheme == .dark ? 0 : 0.10), radius: 6, y: 3)
            }
            .buttonStyle(PressedPrint())
            .disabled(!live)
            .frame(maxWidth: .infinity)
            .padding(.top, 14)
            .accessibilityLabel(memory.caption.flatMap { $0.isEmpty ? nil : "Held photo: \($0)" } ?? "Held photo")
            .accessibilityHint("Opens it large")

            VStack(alignment: .leading, spacing: 4) {
                if let caption = memory.caption, !caption.isEmpty {
                    Text(caption)
                        .font(.custom(layout.font.fontName, size: layout.fontSize, relativeTo: .body))
                        .foregroundStyle(Ink.black.color)
                        .lineLimit(3)
                }
                Text(photoLine(held, mine: mine))
                    .font(.footnote)
                    .foregroundStyle(BookPaper.quiet)
                    .lineLimit(2)
                // What you wrote about the day on your own photo.
                if let words = memory.journal, !words.isEmpty {
                    Text(words)
                        .font(.custom(layout.font.fontName, size: layout.fontSize - 2, relativeTo: .callout))
                        .foregroundStyle(Ink.black.color.opacity(0.85))
                        .lineLimit(5)
                        .padding(.top, 6)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, (layout.textWidth - width) / 2)
        }
    }

    /// "From Ines · Collins · Climbing Club": whose it was, where, and the
    /// circle once there's more than one to tell apart.
    private func photoLine(_ held: HeldPage, mine: Bool) -> String {
        var parts = [mine ? "Yours" : "From \(held.friend.displayName)"]
        if let place = held.memory.location, !place.isEmpty { parts.append(place) }
        if state.circles.count > 1, let circle = held.memory.circleName { parts.append(circle) }
        return parts.joined(separator: " · ")
    }

    /// An honest absence: where the photo was, and that it was.
    private func tombstone(_ memory: Memory) -> some View {
        let width = layout.textWidth * 0.62
        return VStack(spacing: 6) {
            Text("A memory was here")
                .font(.custom(layout.font.fontName, size: layout.fontSize, relativeTo: .body))
                .foregroundStyle(BookPaper.quiet)
        }
        .frame(width: width, height: width / PhotoShape.aspect)
        .overlay {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(BookPaper.quiet.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        }
        .rotationEffect(.degrees(number.isMultiple(of: 2) ? 0.8 : -0.8))
        .padding(.top, 28)
        .accessibilityElement(children: .combine)
    }

    /// A letter written to you, lying open on the page on its own paper.
    private func letter(_ letter: Letter) -> some View {
        let inset = BookLayout.letterInset
        return Group {
            if let text = page.text {
                InkText(text: text)
                    .frame(width: layout.letterTextWidth, height: page.textHeight, alignment: .topLeading)
                    .padding(inset)
                    .creamPaper(corner: 3, tilt: number.isMultiple(of: 2) ? 0.5 : -0.5)
                    .accessibilityLabel(text.string)
            }
        }
        .padding(.top, 10)
    }
}

/// Today's page is still open: a tap anywhere on it begins writing, or
/// goes on with what's written. Older pages are changed from the long
/// press, so that reading one doesn't raise the keyboard.
private struct TodayTap: ViewModifier {
    let page: BookPage
    let actions: BookActions
    let live: Bool

    func body(content: Content) -> some View {
        if live, page.isToday {
            switch page.kind {
            case .written(let written):
                content
                    .onTapGesture { actions.edit(written) }
                    .accessibilityAction(named: "Write More") { actions.edit(written) }
            default:
                content.onTapGesture { actions.write() }
            }
        } else {
            content
        }
    }
}

/// A long press on a page: what can be done with it. A written page can be
/// edited, set in another ink, or torn out; the rest have their own few.
private struct PageMenu: ViewModifier {
    let page: BookPage
    let actions: BookActions
    let live: Bool

    func body(content: Content) -> some View {
        if live, hasMenu {
            content.contextMenu { items }
        } else {
            content
        }
    }

    private var hasMenu: Bool {
        switch page.kind {
        // A spread's two pages each have a menu of their own.
        case .chapter, .tombstone, .spread, .oursEmpty: return false
        default: return true
        }
    }

    @ViewBuilder
    private var items: some View {
        switch page.kind {
        case .written(let written):
            Button { actions.edit(written) } label: { Label("Edit", systemImage: "pencil") }
            Menu {
                ForEach(Ink.allCases) { ink in
                    Button { actions.changeInk(written, ink) } label: {
                        // Ticked only where the whole page is in it.
                        if written.stretches.count == 1, Ink.named(written.ink) == ink {
                            Label(ink.name, systemImage: "checkmark")
                        } else {
                            Text(ink.name)
                        }
                    }
                }
            } label: {
                Label("Change Ink", systemImage: "pencil.tip")
            }
            // Into the circle's shared journal, or back out of it (build 51).
            if written.isShared {
                Button { actions.makePrivate(written) } label: { Label("Make Private", systemImage: "lock") }
            } else if let circle = actions.shareWith {
                Button { actions.share(written) } label: { Label("Share with \(circle)", systemImage: "person.2") }
            }
            Button(role: .destructive) { actions.delete(written) } label: { Label("Delete", systemImage: "trash") }
        case .today:
            Button(action: actions.write) { Label("Write Today's Page", systemImage: "pencil") }
        case .photo(let held):
            Button { actions.openPhoto(held) } label: { Label("Open", systemImage: "arrow.up.left.and.arrow.down.right") }
        case .letter(let letter):
            Button { actions.reportLetter(letter) } label: { Label("Report Letter", systemImage: "exclamationmark.bubble") }
            Button(role: .destructive) { actions.deleteLetter(letter) } label: { Label("Delete Letter", systemImage: "trash") }
        case .reflection(let reflection):
            Button(role: .destructive) { actions.deleteReflection(reflection) } label: {
                Label("Delete Reflection", systemImage: "trash")
            }
        case .chapter, .tombstone, .spread, .oursEmpty:
            EmptyView()
        }
    }
}

// MARK: - The shared journal's facing pages

/// A spread of the shared journal (build 51): two people's pages from the
/// same day, facing each other. On a phone the two are one above the other
/// with a thin rule between; on a screen wide enough for a book lying open
/// (the Duo's inner display) they're side by side, the fold as the spine.
/// With `spread` nil it's the shared journal with nothing in it yet.
struct SpreadView: View {
    @Environment(\.colorScheme) private var colorScheme
    let day: Date
    let spread: SharedSpread?
    let layout: BookLayout
    let actions: BookActions
    let live: Bool

    /// What a facing page says when nobody's writing is on it.
    private var facing: String? {
        guard spread != nil else {
            return "Nobody has written here yet. Tap + and choose “Write to the shared journal”."
        }
        // Today there's still time for someone to; a day that's over is
        // simply a blank page.
        return Calendar.current.isDateInToday(day) ? "Waiting for someone else" : nil
    }

    var body: some View {
        let top = layout.contentTop
        let tall = layout.contentBottom - top
        if layout.width >= 600 {
            // A book lying open: two pages, the spine between them.
            let half = ((layout.width - layout.safeLeading) / 2).rounded(.down)
            let size = CGSize(width: half, height: tall)
            ZStack(alignment: .topLeading) {
                SharedHalf(
                    page: spread?.left, note: nil, layout: layout, size: size,
                    leading: 30, trailing: 22, actions: actions, live: live
                )
                .offset(x: layout.safeLeading, y: top)
                SharedHalf(
                    page: spread?.right, note: facing, layout: layout, size: size,
                    leading: 22, trailing: 30, actions: actions, live: live
                )
                .offset(x: layout.safeLeading + half, y: top)
                LinearGradient(
                    colors: [.clear, .black.opacity(colorScheme == .dark ? 0.45 : 0.09), .clear],
                    startPoint: .leading, endPoint: .trailing
                )
                .frame(width: 34, height: layout.height)
                .offset(x: layout.safeLeading + half - 17)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        } else {
            let gap: CGFloat = 13
            let size = CGSize(width: layout.width, height: ((tall - gap) / 2).rounded(.down))
            let inset = layout.width - layout.right
            ZStack(alignment: .topLeading) {
                SharedHalf(
                    page: spread?.left, note: nil, layout: layout, size: size,
                    leading: layout.left, trailing: inset, actions: actions, live: live
                )
                .offset(y: top)
                // The thin rule between the two pages.
                Rectangle()
                    .fill(BookPaper.quiet.opacity(0.45))
                    .frame(width: layout.textWidth, height: 0.5)
                    .offset(x: layout.left, y: top + size.height + gap / 2)
                    .accessibilityHidden(true)
                SharedHalf(
                    page: spread?.right, note: facing, layout: layout, size: size,
                    leading: layout.left, trailing: inset, actions: actions, live: live
                )
                .offset(y: top + size.height + gap)
            }
        }
    }
}

/// One page of a spread: someone's words on ruled paper, in their inks,
/// their name small at the foot, and the heart. The foot is the heart's:
/// a tap there leaves yours or takes it back. On your own page it shows who
/// left one, as faces, never a number; nobody else is shown them. A day
/// too long for the page scrolls on it.
private struct SharedHalf: View {
    static let foot: CGFloat = 36

    @AppStorage("stanley.atmosphere") private var raw = "auto"
    let page: SharedPage?
    /// What a page with nobody's writing on it says, if anything.
    let note: String?
    let layout: BookLayout
    /// The whole of this page, margins and all; the words sit inside
    /// `leading` and `trailing`.
    let size: CGSize
    let leading: CGFloat
    let trailing: CGFloat
    let actions: BookActions
    let live: Bool

    private var column: CGFloat { size.width - leading - trailing }
    private var area: CGFloat { size.height - (page == nil ? 0 : Self.foot) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            words
                .frame(width: size.width, height: area, alignment: .topLeading)
                .clipped()
            if let page {
                footer(page)
                    .padding(.leading, leading)
                    .padding(.trailing, trailing)
                    .frame(width: size.width, height: Self.foot)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .contentShape(Rectangle())
        .modifier(HalfMenu(page: page, actions: actions, live: live))
    }

    /// The ruled lines of this page: as many as show, or as the words need.
    private func rules(_ rows: Int) -> some View {
        Canvas { context, canvas in
            var path = Path()
            for row in 1...max(rows, 1) {
                let y = (CGFloat(row) * layout.pitch - layout.ruleRise).rounded() + 0.25
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: canvas.width, y: y))
            }
            context.stroke(path, with: .color(BookPaper.rule), lineWidth: 0.5)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var words: some View {
        let showing = Int(area / layout.pitch)
        if let page {
            let text = BookType.shared(page, layout: layout)
            let tall = Paginator.height(text, width: column)
            let rows = max(showing, Int((tall / layout.pitch).rounded(.up)))
            ScrollView(.vertical, showsIndicators: false) {
                ZStack(alignment: .topLeading) {
                    rules(rows)
                    InkText(text: text)
                        .frame(width: column, height: max(tall, layout.pitch), alignment: .topLeading)
                        .offset(x: leading)
                        .accessibilityLabel(page.body)
                }
                .frame(width: size.width, height: CGFloat(rows) * layout.pitch, alignment: .topLeading)
            }
            .scrollDisabled(!live || tall <= area)
            .scrollBounceBehavior(.basedOnSize)
        } else {
            ZStack(alignment: .topLeading) {
                rules(showing)
                if let note {
                    Text(note)
                        .font(.custom(layout.font.fontName, fixedSize: layout.fontSize))
                        .foregroundStyle(BookPaper.quiet.opacity(0.85))
                        .lineSpacing(layout.pitch - layout.font.lineHeight)
                        .frame(width: column, alignment: .leading)
                        .offset(x: leading, y: (layout.pitch - layout.font.lineHeight) / 2)
                }
            }
        }
    }

    /// The foot of the page: whose it is, and the heart.
    @ViewBuilder
    private func footer(_ page: SharedPage) -> some View {
        let accent = Atmosphere.resolve(raw).palette.accent
        let name = Text("— \(page.writer.displayName)")
            .font(.custom(layout.font.fontName, fixedSize: layout.headSize))
            .foregroundStyle(Ink.black.color.opacity(0.62))
            .lineLimit(1)
        if page.mine {
            // Your own page: who left a heart, as faces. Nobody else is
            // sent these, and there's never a number.
            HStack(spacing: 8) {
                name
                Spacer(minLength: 8)
                let faces = (page.hearts ?? []).filter { $0.id != nil }
                if !faces.isEmpty {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(accent.opacity(0.8))
                        .accessibilityHidden(true)
                    HStack(spacing: -7) {
                        ForEach(faces.prefix(8), id: \.id) { face in
                            AvatarView(url: face.avatarUrl, name: face.displayName, size: 20, circular: true)
                                .overlay(Circle().stroke(BookPaper.page, lineWidth: 1.5))
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Hearts from " + faces.map(\.displayName).formatted(.list(type: .and)))
                }
            }
        } else {
            // Someone else's: the foot of the page is the heart's.
            Button { actions.heart(page) } label: {
                HStack(spacing: 8) {
                    name
                    Spacer(minLength: 8)
                    Image(systemName: page.hearted ? "heart.fill" : "heart")
                        .font(.system(size: 15, weight: .light))
                        .foregroundStyle(page.hearted ? accent : BookPaper.quiet)
                        .frame(width: 24)
                }
                .frame(maxWidth: .infinity, minHeight: Self.foot)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!live)
            .accessibilityLabel("Page by \(page.writer.displayName)")
            .accessibilityValue(page.hearted ? "Your heart is on it" : "")
            .accessibilityHint(page.hearted ? "Takes your heart back" : "Leaves a heart. Only they see who.")
        }
    }
}

/// A long press on one page of a spread: someone else's can be reported;
/// your own can be gone on with, or taken back to being yours alone.
private struct HalfMenu: ViewModifier {
    let page: SharedPage?
    let actions: BookActions
    let live: Bool

    func body(content: Content) -> some View {
        if live, let page {
            content.contextMenu {
                if page.mine {
                    Button { actions.editShared(page) } label: { Label("Edit", systemImage: "pencil") }
                    Button { actions.privateShared(page) } label: { Label("Make Private", systemImage: "lock") }
                } else {
                    Button { actions.reportPage(page) } label: {
                        Label("Report Page", systemImage: "exclamationmark.bubble")
                    }
                }
            }
        } else {
            content
        }
    }
}

/// A page made small, for the grid of pages: its top, cut to a print's
/// shape, so six sit on a screen.
struct BookThumb: View {
    let page: BookPage
    let number: Int
    let layout: BookLayout
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        let scale = width / layout.width
        // Its top edge is the screen's status bar: start under it.
        let lift = layout.safeTop * 0.6
        BookPageView(page: page, number: number, layout: layout, live: false)
            // Nothing on a small page is pressed; the whole of it is.
            .allowsHitTesting(false)
            .offset(y: -lift)
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: width, height: height, alignment: .topLeading)
            .contentShape(Rectangle())
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(BookPaper.quiet.opacity(0.35), lineWidth: 0.5)
            }
            .overlay(alignment: .bottom) {
                Text("\(number)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(BookPaper.quiet)
                    .padding(6)
            }
    }
}
