import SwiftUI

// The covers (build 54; redrawn in build 56 from the brief of 2026-11-14,
// "Five fixes to the Journal cover screen"). The Journal tab opens here:
// one journal to a card, paged sideways, yours first and then one for each
// circle you're in. Each card is its cover photo with a slab of glass laid
// over it: where it's kept and its title in the hand, and at its foot the
// dates it covers and its volume. The next card's edge shows at the right,
// and is a real card: a swipe brings it. Under the cards, the journal's
// name and a line, the pips (which follow the scroll) and the arrow that
// opens it, as a tap on the card does.
//
// The room is the atmosphere's own floor, cream by day and black by night,
// as every other screen is; the photo is on the card, not the room. By day
// the slab is 20% white; at night 8%, with its thin white edge carrying it
// (material over black goes muddy). A dark scrim only where the card's
// words sit on the photo.
//
// The cover photo is the reader's own newest keep in that journal, else
// its newest photo still in the light (`sharing.cover`, with a signed link).
// The brief asked for the most-kept photo; that ranks by keeps and would
// let a circle see which was kept most, so it isn't (a product decision,
// 2026-11-14). With no photo at all: the palette's warm field, a gradient,
// never a flat gray.

/// One journal on the table.
struct CoverJournal: Identifiable, Hashable {
    /// "mine", or the circle's id.
    let id: String
    let circleId: String?
    /// Small, at the slab's head: whose it is or where it's kept.
    let place: String
    /// In the hand, under that.
    let title: String
    /// Under the cards.
    let name: String
    let subtitle: String
    let cover: URL?
    /// The first real entry; nil while the journal is empty, and then no
    /// dates are shown at all.
    let since: Date?
    /// A circle's journal whose notices you've muted (build 57); nil for
    /// your own, or a server that has no such thing.
    var muted: Bool? = nil
}

struct JournalCovers: View {
    @Environment(AppState.self) private var state
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("stanley.atmosphere") private var raw = "auto"
    let layout: BookLayout
    /// The room the covers have: across (without a side dock) and down
    /// (to the tab bar).
    let width: CGFloat
    let height: CGFloat
    /// How much further the room runs on under a side dock: the backdrop
    /// goes there too.
    var beyond: CGFloat = 0
    /// The safe edge at the leading side (a phone on its side keeps its
    /// cards clear of the island): the cards are centered between it and
    /// the room's trailing edge.
    var lead: CGFloat = 0
    /// The date's line along the top, with Letters and Prompts at its
    /// right: drawn for a left edge, a right edge and a middle (the card's
    /// edges, so the three line up).
    let bar: (_ left: CGFloat, _ right: CGFloat, _ y: CGFloat) -> AnyView
    let open: (CoverJournal) -> Void
    @Binding var page: String
    @State private var shown: String?
    @State private var renaming = false
    @State private var name = ""
    /// How far through the journals the deck is, as it moves: 0 at the
    /// first, 1 at the second, and between while paging (iOS 18 and up;
    /// nil before, and the room changes as each card settles).
    @State private var progress: CGFloat?

    private var palette: Atmosphere.Palette { Atmosphere.resolve(raw).palette }

    private var journals: [CoverJournal] {
        var all = [mine]
        if state.sharedAvailable {
            for circle in state.circles {
                all.append(CoverJournal(
                    id: circle.id, circleId: circle.id,
                    place: circle.name, title: "Ours",
                    name: circle.name,
                    subtitle: circle.journalMuted == true ? "Shared with your circle · muted" : "Shared with your circle",
                    cover: circle.coverUrl.flatMap { state.api.absoluteURL($0) } ?? state.coverURL(circle.coverPhotoId),
                    since: circle.firstDay.flatMap(WeekRange.day),
                    muted: circle.journalMuted
                ))
            }
        }
        return all
    }

    private var mine: CoverJournal {
        // The volume begins with the first real thing in the book.
        let calendar = Calendar.current
        var firsts: [Date] = state.journalPages.compactMap { WeekRange.day($0.day) }
        firsts += state.reflections.map { calendar.startOfDay(for: $0.createdAt) }
        firsts += state.threads.flatMap(\.memories).compactMap { $0.anchoredAt }
        return CoverJournal(
            id: "mine", circleId: nil,
            place: state.profile?.displayName ?? "Yours",
            title: JournalName.shown(state.journalTitle),
            name: "Mine", subtitle: "Only you read it",
            cover: state.journalCoverLink.flatMap { state.api.absoluteURL($0) } ?? state.coverURL(state.journalCover),
            since: firsts.min()
        )
    }

    /// On its side (build 58): the room is wider than it's tall (a phone
    /// turned, or the Duo's inner display turned). The cards and what's
    /// under them are then centered as one group, not the portrait layout
    /// stretched.
    private var landscape: Bool { width > height }

    /// The room across, between the leading safe edge and the trailing
    /// edge (a dock's, or the screen's).
    private var across: CGFloat { width - lead }

    /// Where the cards begin: under the date's line.
    private var top: CGFloat { layout.safeTop + (landscape ? 64 : 72) }

    /// The card: about three quarters of the room across, held at 290 by
    /// 416, never over 420 wide, leaving a sliver of a card either side,
    /// and no taller than the room leaves under the bar and above what's
    /// written under it. On its side the room's height decides it.
    private var card: CGSize {
        let across = min(420, (self.across * 0.74).rounded(), self.across - 2 * (14 + 24))
        let down = (across * 416 / 290).rounded()
        if landscape {
            // The deck's frame (the card and 24 for its shadow), the gap,
            // the row (the arrow's 44 and a little), and a margin.
            let tallest = height - top - 24 - 14 - 48 - 12
            let fitted = max(140, min(down, tallest)).rounded()
            return CGSize(width: (fitted * 290 / 416).rounded(), height: fitted)
        }
        let tallest = height - top - 4 - 150 - 16
        guard down > tallest else { return CGSize(width: across, height: down) }
        let fitted = max(240, tallest)
        return CGSize(width: (fitted * 290 / 416).rounded(), height: fitted)
    }

    var body: some View {
        let journals = self.journals
        let card = self.card
        let scale = card.width / 290
        let gap = (14 * scale).rounded()
        // The card in view is always centered (build 58), with an equal
        // sliver of the one before and the one after; the first and the
        // last show only the neighbour they have, and don't move over.
        let leading = (lead + (across - card.width) / 2).rounded()
        // On its side there's room for more than a sliver: the deck is
        // shown through a window a little wider than the card, its edges
        // soft, so either neighbour shows as much as it would upright.
        let peek = max(28, (card.width * 0.4).rounded())
        let window = landscape ? min(across, card.width + 2 * (gap + peek)) : width
        let current = journals.first { $0.id == (shown ?? page) } ?? journals[0]
        let at = journals.firstIndex(of: current) ?? 0
        // The date's line: the card's edges upright; on its side, no
        // narrower than the line needs.
        let span = landscape ? max(card.width, min(across - 32, 360)) : card.width
        let left = (lead + (across - span) / 2).rounded()

        ZStack(alignment: .topLeading) {
            CoverBackdrop(
                journals: journals, progress: progress ?? CGFloat(at),
                size: CGSize(width: width + beyond, height: height + 160)
            )
            .animation(progress == nil ? .easeInOut(duration: 0.35) : nil, value: at)
            .ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                if landscape { Spacer(minLength: 0) }
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: gap) {
                        ForEach(journals) { journal in
                            CoverCard(
                                journal: journal, size: card,
                                open: { open(journal) },
                                rename: journal.circleId == nil ? {
                                    name = state.journalTitle ?? ""
                                    renaming = true
                                } : nil
                            )
                            // The journal's own settings: its notices, muted
                            // or not (build 57).
                            .contextMenu {
                                if let circleId = journal.circleId, let muted = journal.muted {
                                    Button {
                                        Task { await state.setJournalMuted(circleId, !muted) }
                                    } label: {
                                        muted
                                            ? Label("Unmute Pages Written to You", systemImage: "bell")
                                            : Label("Mute Pages Written to You", systemImage: "bell.slash")
                                    }
                                }
                                Button { open(journal) } label: { Label("Open", systemImage: "book") }
                            }
                            .id(journal.id)
                        }
                    }
                    .scrollTargetLayout()
                }
                .contentMargins(.leading, leading, for: .scrollContent)
                .contentMargins(.trailing, width - leading - card.width, for: .scrollContent)
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $shown)
                .modifier(ScrollProgress(step: card.width + gap, count: journals.count, progress: $progress))
                .frame(width: width, height: card.height + 24)
                // A turn (or any new size) keeps the journal in view where
                // it was: the scroll would otherwise keep its old offset,
                // with the cards somewhere off to the side.
                .onChange(of: card) { _, _ in
                    let id = shown ?? page
                    shown = nil
                    DispatchQueue.main.async { shown = id }
                }
                // Shadows run on up and down; sideways the cards stop at the
                // room's edge, which stops short of a side dock (the Duo's
                // cover), so the next card's edge is never under the dock.
                // On its side, at the window's soft edges.
                .scrollClipDisabled()
                .mask { DeckWindow(width: width, center: lead + across / 2, window: window, height: card.height + 140, soft: landscape) }
                Group {
                    if landscape {
                        across(current, at: at, of: journals.count, scale: scale)
                    } else {
                        underneath(current, at: at, of: journals.count, width: card.width, scale: scale)
                    }
                }
                .frame(width: across)
                .padding(.leading, lead)
                .padding(.top, 14)
                Spacer(minLength: 16)
            }
            .padding(.top, top)
            .frame(width: width, height: height, alignment: .topLeading)
            bar(left, left + span, layout.safeTop + 30)
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .onAppear {
            shown = page
            Turning.coversShowing(true)
        }
        .onDisappear { Turning.coversShowing(false) }
        .onChange(of: shown) { _, now in if let now { page = now } }
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

    /// On its side: one row centered under the card, the journal's name
    /// and its line, the pips, and the arrow at the row's right.
    private func across(_ journal: CoverJournal, at: Int, of: Int, scale: CGFloat) -> some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .center, spacing: 2) {
                Text(journal.name)
                    .font(.system(size: 20 * min(max(scale, 0.9), 1.2), weight: .semibold, design: .rounded))
                    .foregroundStyle(TextTone.primary)
                    .lineLimit(1)
                Text(journal.subtitle)
                    .font(.system(size: 13 * min(max(scale, 0.9), 1.2)))
                    .foregroundStyle(TextTone.secondary)
                    .lineLimit(1)
            }
            .fixedSize()
            Pips(at: at, of: of, ink: TextTone.primary)
            arrow(journal)
        }
    }

    private func arrow(_ journal: CoverJournal) -> some View {
        Button { open(journal) } label: {
            GlassCircle(size: 44) {
                Image(systemName: "arrow.right")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(palette.accent)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open \(journal.name)")
    }

    /// Under the cards: the journal in view, its name and a line, the pips,
    /// and the arrow that opens it. In the room's own ink.
    private func underneath(_ journal: CoverJournal, at: Int, of: Int, width: CGFloat, scale: CGFloat) -> some View {
        let ink = TextTone.primary
        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(journal.name)
                    .font(.system(size: 22 * min(scale, 1.2), weight: .semibold, design: .rounded))
                    .foregroundStyle(ink)
                    .lineLimit(1)
                Text(journal.subtitle)
                    .font(.system(size: 14 * min(scale, 1.2)))
                    .foregroundStyle(TextTone.secondary)
                    .lineLimit(1)
                Pips(at: at, of: of, ink: ink)
                    .padding(.top, 8)
            }
            Spacer(minLength: 8)
            arrow(journal)
        }
        .frame(width: width)
    }
}

/// Which journal is in view: a pip each, this one's full.
private struct Pips: View {
    let at: Int
    let of: Int
    let ink: Color

    var body: some View {
        HStack(spacing: 7) {
            ForEach(0..<max(of, 1), id: \.self) { index in
                Circle()
                    .fill(ink.opacity(index == at ? 0.85 : 0.22))
                    .frame(width: 6, height: 6)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Journal \(at + 1) of \(of)")
    }
}

/// The card's outline: corners of 30 (scaled with the card).
private func cardShape(_ scale: CGFloat) -> RoundedRectangle {
    RoundedRectangle(cornerRadius: 30 * scale, style: .continuous)
}

/// One journal's card: its photo (or the warm field), the slab of glass
/// over it, and what's written on the slab.
private struct CoverCard: View {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("stanley.atmosphere") private var raw = "auto"
    let journal: CoverJournal
    let size: CGSize
    let open: () -> Void
    let rename: (() -> Void)?

    private var scale: CGFloat { size.width / 290 }

    var body: some View {
        let shape = cardShape(scale)
        ZStack(alignment: .topLeading) {
            picture
            // Dark only where words sit on the photo: under the head and
            // under the foot.
            VStack(spacing: 0) {
                LinearGradient(colors: [CoverTone.scrimHead, .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: size.height * 0.42)
                Spacer(minLength: 0)
                LinearGradient(colors: [.clear, CoverTone.scrimFoot], startPoint: .top, endPoint: .bottom)
                    .frame(height: size.height * 0.26)
            }
            // The slab: a little white, a sheen across its top left, a thin
            // white edge.
            shape.fill(CoverTone.slab(colorScheme))
            shape.fill(LinearGradient(
                colors: [CoverTone.sheen, .clear],
                startPoint: .topLeading, endPoint: UnitPoint(x: 0.45, y: 0.35)
            ))
            words
        }
        .frame(width: size.width, height: size.height)
        .clipShape(shape)
        .overlay(shape.strokeBorder(CoverTone.edge, lineWidth: 0.5))
        .shadow(color: CoverTone.shadow(colorScheme), radius: 18 * scale, x: 8 * scale, y: 12 * scale)
        .contentShape(shape)
        .onTapGesture(perform: open)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(journal.title), \(journal.place)" + (dates.isEmpty ? "" : ". \(dates)") + ", volume one")
        .accessibilityHint("Opens it")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { open() }
        .accessibilityActions {
            if let rename { Button("Rename", action: rename) }
        }
    }

    /// The cover photo filling the card; with none, the palette's warm
    /// field.
    @ViewBuilder
    private var picture: some View {
        if let cover = journal.cover {
            SignedImage(url: cover) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                field
            }
            .frame(width: size.width, height: size.height)
            .clipped()
        } else {
            field
        }
    }

    /// The journal's warmth, graded: a field, never flat gray.
    private var field: some View {
        return ZStack {
            // A warm ground, the journal's own warmth laid lightly over it
            // (the same the room glows with, build 58), and light coming in
            // from the top left (`CoverTone`).
            CoverTone.ground(colorScheme)
            CoverTone.warmth(journal.id).opacity(CoverTone.accentWash(colorScheme))
            LinearGradient(colors: [CoverTone.light(colorScheme), .clear], startPoint: .topLeading, endPoint: .bottomTrailing)
            LinearGradient(colors: [.clear, CoverTone.deep(colorScheme)], startPoint: .center, endPoint: .bottom)
        }
        .frame(width: size.width, height: size.height)
    }

    private var words: some View {
        let inset = 26 * scale
        let label = Font.system(size: 8.5 * scale, weight: .semibold)
        return VStack(alignment: .leading, spacing: 0) {
            Text(journal.place)
                .font(label)
                .tracking(2.6 * scale)
                .textCase(.uppercase)
                .foregroundStyle(TextTone.onPhotoLabel)
                .lineLimit(1)
            Text(journal.title)
                .font(.custom(BookHand.font(44, bold: true).fontName, fixedSize: 44 * scale).leading(.tight))
                .foregroundStyle(TextTone.onPhoto)
                .lineLimit(3)
                .minimumScaleFactor(0.5)
                .padding(.top, 10 * scale)
                .onLongPressGesture(minimumDuration: 0.45) { rename?() }
            Spacer(minLength: 12)
            Rectangle()
                .fill(CoverTone.hairline)
                .frame(height: max(0.5, 0.5 * scale))
            HStack {
                // Only once there's a first entry: an empty journal says
                // nothing about when it began.
                Text(dates)
                Spacer()
                Text("Vol. I")
            }
            .font(label)
            .tracking(2.6 * scale)
            .textCase(.uppercase)
            .foregroundStyle(TextTone.onPhotoLabel)
            .padding(.top, 12 * scale)
        }
        .padding(inset)
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    /// "Oct 2026 – now", this month alone, or nothing at all.
    private var dates: String {
        guard let since = journal.since else { return "" }
        let start = since.formatted(.dateTime.month(.abbreviated).year())
        if Calendar.current.isDate(since, equalTo: .now, toGranularity: .month) { return start }
        return start + " – now"
    }
}

/// The room behind the cards (build 58, from the brief of 2026-11-14,
/// "Three fixes to the Journal cover screen"): the glass needs something
/// behind it. A journal with a cover photo lays it under everything, filling
/// the room, blurred heavily and veiled (at night to about 35% of its
/// brightness; by day under the floor, so the room stays light), and the
/// slab sits over a bloom of its own photo's colour. A journal with no photo
/// glows with its own warm colour, top left and bottom right, over the
/// floor: never flat black or gray. Paging cross-fades from one journal's
/// room to the next's as the deck moves.
private struct CoverBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("stanley.atmosphere") private var raw = "auto"
    let journals: [CoverJournal]
    let progress: CGFloat
    let size: CGSize

    var body: some View {
        let floor = Atmosphere.resolve(raw).palette.floor
        let clamped = min(max(progress, 0), CGFloat(max(journals.count - 1, 0)))
        let under = Int(clamped.rounded(.down))
        let over = clamped - CGFloat(under)
        ZStack {
            floor
            ForEach(Array(journals.enumerated()), id: \.element.id) { index, journal in
                // The journal in view, and the next one coming in over it.
                if index == under || (index == under + 1 && over > 0.001) {
                    room(journal, floor: floor)
                        .opacity(index == under ? 1 : over)
                        .transition(.opacity)
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func room(_ journal: CoverJournal, floor: Color) -> some View {
        if let cover = journal.cover {
            ZStack {
                floor
                SignedImage(url: cover) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    glow(journal, floor: floor)
                }
                .frame(width: size.width, height: size.height)
                .clipped()
                .blur(radius: CoverTone.backdropBlur, opaque: true)
                CoverTone.backdropVeil(colorScheme, floor: floor)
            }
        } else {
            glow(journal, floor: floor)
        }
    }

    private func glow(_ journal: CoverJournal, floor: Color) -> some View {
        let warmth = CoverTone.warmth(journal.id)
        let reach = max(size.width, size.height)
        return ZStack {
            floor
            RadialGradient(
                colors: [warmth.opacity(CoverTone.glowNear), warmth.opacity(0)],
                center: .topLeading, startRadius: 0, endRadius: reach * 0.85
            )
            RadialGradient(
                colors: [warmth.opacity(CoverTone.glowFar), warmth.opacity(0)],
                center: .bottomTrailing, startRadius: 0, endRadius: reach * 0.75
            )
        }
    }
}

/// How far through the deck the scroll is, journal by journal (iOS 18 and
/// up, where a scroll view says where it is).
private struct ScrollProgress: ViewModifier {
    let step: CGFloat
    let count: Int
    @Binding var progress: CGFloat?

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.x + geometry.contentInsets.leading
            } action: { _, x in
                guard step > 0 else { return }
                progress = min(max(x / step, 0), CGFloat(max(count - 1, 0)))
            }
        } else {
            content
        }
    }
}

/// Where the deck shows: the whole room across upright, its edge hard (the
/// screen's, or a dock's); on its side a window a little wider than the
/// card, centered, fading out at its edges.
private struct DeckWindow: View {
    let width: CGFloat
    /// Where the window is centered across the room.
    let center: CGFloat
    let window: CGFloat
    let height: CGFloat
    let soft: Bool

    var body: some View {
        if soft && window < width {
            let fade = min(32, window / 6)
            HStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                    .frame(width: fade)
                Rectangle()
                LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: fade)
            }
            .frame(width: window, height: height)
            .position(x: center, y: height / 2)
            .frame(width: width, height: height)
        } else {
            Rectangle().frame(width: width, height: height)
        }
    }
}

/// Which way Stanley may turn (build 58). Upright everywhere, as since the
/// QA audit (build 30), except while the journals' covers are on screen,
/// which may lie on their side: the brief asked for the covers in
/// landscape. Leaving them (opening a book, another tab) turns the app
/// upright again. The plist lists the landscape orientations so that the
/// app delegate's answer (`AppDelegate`, from `allowed`) can let them in.
@MainActor
enum Turning {
    private(set) static var covers = false

    static var allowed: UIInterfaceOrientationMask { covers ? .allButUpsideDown : .portrait }

    static func coversShowing(_ showing: Bool) {
        guard covers != showing else { return }
        covers = showing
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows {
                window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            }
            if !showing, scene.interfaceOrientation != .portrait {
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait)) { _ in }
            }
        }
    }
}
