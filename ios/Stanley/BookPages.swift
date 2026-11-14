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
            .frame(width: layout.textWidth, alignment: .leading)
            .position(x: layout.middle, y: layout.headY)
            .accessibilityAddTraits(.isHeader)
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
        case .chapter:
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
        if case .chapter = page.kind { return false }
        if case .tombstone = page.kind { return false }
        return true
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
        case .chapter, .tombstone:
            EmptyView()
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
