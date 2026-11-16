import SwiftUI

// The covers (build 54; redrawn in build 56; laid out to Apple's iPhone
// Duo guidance in build 62). The Journal tab opens here: one journal to a
// card, paged sideways, yours first and then one for each circle you're
// in. Each card is its cover photo with a slab of glass laid over it:
// where it's kept and its title in the hand, and at its foot the dates it
// covers and its volume. The card in view is centered with a sliver of
// each neighbour. Beside or under the cards, the journal's name and a
// line, the pips (which follow the scroll) and the arrow that opens it, as
// a tap on the card does.
//
// The two parts are an `ArrangementView` (iOS 27.1): side by side or one
// over the other as the room is, the fold between them; a small layout
// does the same before 27.1. The card is sized from the deck's own room
// and the size class, never from a device, and kept clear of reserved
// regions (a fold, the outer camera). Letters and the week are the system's
// toolbar (`JournalToolbar`), not drawn here; the date is content.
//
// The room behind everything is the cover photo, blurred, or the
// journal's own warm glow (build 58, `CoverBackdrop`), cross-faded as the
// deck pages.
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
    /// Not a journal: the card at the end of the deck for your days, which
    /// opens the month's answer sheet (build 72).
    var days = false

    /// The one card for your days.
    static let daysID = "days"
}

struct JournalCovers: View {
    @Environment(AppState.self) private var state
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var sizeClass
    @AppStorage("stanley.atmosphere") private var raw = "auto"
    /// The safe area the covers' content keeps inside: the status bar, the
    /// navigation bar or the toolbar's rail, the island. The room behind
    /// the cards runs on under all of it.
    let insets: EdgeInsets
    let open: (CoverJournal) -> Void
    /// Your own book at a day's page (build 73): a row of the answer sheet.
    let openDay: (String) -> Void
    @Binding var page: String
    /// The month's answer sheet, over the covers (build 72).
    @State private var readingDays = false
    /// The day a row of the sheet asked for, opened once the sheet's gone.
    @State private var dayAsked: String?
    #if DEBUG
    private static var daysOpenedOnce = false
    #endif
    @State private var shown: String?
    @State private var renaming = false
    @State private var name = ""
    /// How far through the journals the deck is, as it moves: 0 at the
    /// first, 1 at the second, and between while paging (iOS 18 and up;
    /// nil before, and the room changes as each card settles).
    @State private var progress: CGFloat?
    /// The card's width, as the deck worked it out from its own room: what
    /// the words under it are measured and scaled by.
    @State private var cardWidth: CGFloat = 290

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
        // Last, your days: in no journal, since there are several books and
        // one set of days (build 72).
        if state.moodsAvailable {
            all.append(CoverJournal(
                id: CoverJournal.daysID, circleId: nil,
                place: "", title: Date.now.formatted(.dateTime.month(.wide)),
                name: MarkSheet.daysName, subtitle: MarkSheet.daysLine,
                cover: nil, since: nil, days: true
            ))
        }
        return all
    }

    /// The day you joined, as far back as the sheet turns: when the account
    /// was made, or, before the profile has come, the first day marked.
    private var joined: Date? {
        let first = state.moods.keys.compactMap(WeekRange.day).min()
        return [state.profile?.createdAt, first].compactMap { $0 }.min()
    }

    /// A journal opens its book; your days open the sheet.
    private func go(_ journal: CoverJournal) {
        if journal.days { readingDays = true } else { open(journal) }
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

    /// The page's side margin, as every other page has it.
    private static let margin: CGFloat = 20

    var body: some View {
        let journals = self.journals
        let current = journals.first { $0.id == (shown ?? page) } ?? journals[0]
        let at = journals.firstIndex(of: current) ?? 0

        GeometryReader { room in
            ZStack(alignment: .topLeading) {
                // The room behind everything, under the bars and the rail.
                CoverBackdrop(
                    journals: journals, progress: progress ?? CGFloat(at),
                    size: CGSize(width: room.size.width, height: room.size.height + 160)
                )
                .animation(progress == nil ? .easeInOut(duration: 0.35) : nil, value: at)
                .ignoresSafeArea()
                VStack(alignment: .leading, spacing: 0) {
                    // The day, as content: the toolbar holds Letters and
                    // the week, never this.
                    // (The ink on the text itself: set outside the small
                    // capitals, it was their `.secondary` of it, dimmer
                    // than the secondary, which the audit failed.)
                    Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                        .foregroundStyle(TextTone.label)
                        .smallCaps()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, Self.margin)
                        .padding(.top, 8)
                    arranged(journals: journals, current: current, at: at, room: room.size.width)
                }
                .padding(.top, insets.top)
                .padding(.leading, insets.leading)
                .padding(.trailing, insets.trailing)
                .frame(width: room.size.width, height: room.size.height, alignment: .topLeading)
            }
        }
        .onAppear {
            shown = page
            Turning.coversShowing(true)
            #if DEBUG
            // STANLEY_OPEN_DAYS=1: the answer sheet at once, for a
            // simulator with nothing to tap (the accessibility walk).
            if ProcessInfo.processInfo.environment["STANLEY_OPEN_DAYS"] == "1", state.moodsAvailable, !Self.daysOpenedOnce {
                Self.daysOpenedOnce = true
                readingDays = true
            }
            #endif
        }
        .onDisappear { Turning.coversShowing(false) }
        .onChange(of: shown) { _, now in if let now { page = now } }
        // Whichever way the phone is held: the sheet's rows scroll where
        // the room can't hold them (build 73; build 72 turned the screen
        // upright, which nobody asked for).
        .sheet(isPresented: $readingDays, onDismiss: {
            guard let day = dayAsked else { return }
            dayAsked = nil
            openDay(day)
        }) {
            MarkSheetScreen(joined: joined) { day in
                dayAsked = day
                readingDays = false
            }
        }
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

    /// The deck and what's under it, arranged by the system (build 59 of
    /// the Duo brief, "Rework the Journal cover screen to Apple's iPhone Duo
    /// guidance"): side by side when the room is wider than it's tall, one
    /// over the other when it's taller, the fold between them when there is
    /// one. One layout for every pose; nothing here asks which.
    @ViewBuilder
    private func arranged(journals: [CoverJournal], current: CoverJournal, at: Int, room: CGFloat) -> some View {
        GeometryReader { container in
            let deck = GeometryReader { proxy in
                // Where the arrangement keeps only its first part (the outer
                // display on its side: it splits only where both halves have
                // room), the deck is given everything; it then makes room
                // for the rest itself, so the name and the arrow never go.
                if proxy.size.width >= container.size.width - 1 && proxy.size.height >= container.size.height - 1 {
                    CoverArrangement {
                        GeometryReader { inner in self.deck(journals: journals, in: inner, room: room) }
                        GeometryReader { inner in self.secondary(current, at: at, of: journals.count, in: inner) }
                    }
                } else {
                    self.deck(journals: journals, in: proxy, room: room)
                }
            }
            // What each part needs, so the arrangement can tell whether both
            // fit side by side or one goes over the other: a card and its
            // neighbours' edges; a name, a line, the pips and the arrow.
            .frame(minWidth: 200, idealWidth: 320, minHeight: 200, idealHeight: 420)
            let secondary = GeometryReader { proxy in
                self.secondary(current, at: at, of: journals.count, in: proxy)
            }
            .frame(minWidth: 220, idealWidth: 280, minHeight: 96, idealHeight: 140)
            if #available(iOS 27.1, *) {
                ArrangementView {
                    deck.splitArrangementLayoutRatio(0.62)
                } secondary: {
                    secondary
                }
                .arrangementViewStyle(.split.axes([.horizontal, .vertical]))
            } else {
                CoverArrangement {
                    deck
                    secondary
                }
            }
        }
    }

    /// The paged deck, sized from the room it was given: three quarters of
    /// it across in a compact width, a little over half in a regular one,
    /// held to a cover's proportions, and no taller than the room. Kept
    /// clear of anything reserved over it (a camera); where a fold runs
    /// down through it, two cards show, one either side.
    private func deck(journals: [CoverJournal], in proxy: GeometryProxy, room: CGFloat) -> some View {
        let reserved = Reserved.read(proxy)
        let region = CGRect(origin: .zero, size: proxy.size)
        let clear = reserved.clearing(region)
        let fold = reserved.fold(across: clear)
        let shadow: CGFloat = 24
        // A fold standing through the deck with room for a card either side
        // of it: one card each side. Nearer an edge than that, or lying
        // across, the deck keeps to the larger side.
        let standing: Bool = {
            guard let fold, fold.height > fold.width else { return false }
            let before = fold.minX - clear.minX
            let after = clear.maxX - fold.maxX
            return min(before, after) >= 0.6 * max(before, after)
        }()
        let usable = standing ? clear : reserved.side(of: clear)
        // Each card's share of the width: one card centered, or with a fold
        // standing through the deck, one in each half.
        let share = standing ? min(fold!.minX - usable.minX, usable.maxX - fold!.maxX) : usable.width
        let fraction: CGFloat = standing ? 0.84 : (sizeClass == .regular ? 0.56 : 0.74)
        var width = (share * fraction).rounded()
        if !standing { width = min(width, usable.width - 2 * 38) }
        var height = (width * 416 / 290).rounded()
        if height > usable.height - shadow {
            height = max(120, usable.height - shadow)
            width = (height * 290 / 416).rounded()
        }
        let card = CGSize(width: max(80, width), height: height)
        let scale = card.width / 290
        let leading: CGFloat
        let gap: CGFloat
        if standing, let fold {
            // The fold falls in the gap: the card in view is centered in the
            // half before it, the next in the half after.
            let first = (fold.minX + usable.minX) / 2
            let second = (fold.maxX + usable.maxX) / 2
            leading = (first - card.width / 2).rounded()
            gap = (second - first - card.width).rounded()
        } else {
            // The card in view centered, an equal sliver of each neighbour.
            leading = (usable.midX - card.width / 2).rounded()
            gap = (14 * scale).rounded()
        }
        let global = proxy.frame(in: .global)
        return ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: gap) {
                ForEach(journals) { journal in
                    Group {
                        if journal.days {
                            DaysCard(size: card) { go(journal) }
                        } else {
                            CoverCard(
                                journal: journal, size: card,
                                open: { open(journal) },
                                rename: journal.circleId == nil ? {
                                    name = state.journalTitle ?? ""
                                    renaming = true
                                } : nil
                            )
                        }
                    }
                    // The journal's own settings: its notices, muted or
                    // not (build 57).
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
                        Button { go(journal) } label: {
                            Label("Open", systemImage: journal.days ? "square.grid.3x3" : "book")
                        }
                    }
                    .id(journal.id)
                }
            }
            .scrollTargetLayout()
        }
        .contentMargins(.leading, leading, for: .scrollContent)
        .contentMargins(.trailing, max(0, proxy.size.width - leading - card.width), for: .scrollContent)
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $shown)
        .modifier(ScrollProgress(step: card.width + gap, count: journals.count, progress: $progress))
        .frame(width: proxy.size.width, height: card.height + shadow)
        .position(x: proxy.size.width / 2, y: usable.midY)
        // A turn, a fold or any new room keeps the journal in view where
        // it was: the scroll would otherwise keep its old offset, with the
        // cards somewhere off to the side.
        .onChange(of: card, initial: true) { _, now in
            cardWidth = now.width
            let id = shown ?? page
            shown = nil
            DispatchQueue.main.async { shown = id }
        }
        .onChange(of: gap) { _, _ in
            let id = shown ?? page
            shown = nil
            DispatchQueue.main.async { shown = id }
        }
        // Shadows run on up and down; sideways the cards stop at the deck's
        // own edges, softly where those aren't the screen's.
        .scrollClipDisabled()
        .mask {
            DeckWindow(
                size: proxy.size, card: card.height + 140, y: usable.midY,
                softLeading: global.minX > 1, softTrailing: global.maxX < room - 1
            )
        }
    }

    /// Under or beside the deck: the journal in view, its name and a line,
    /// the pips and the arrow that opens it, measured by the card and
    /// scaled with it, and kept clear of anything reserved over it.
    private func secondary(_ journal: CoverJournal, at: Int, of: Int, in proxy: GeometryProxy) -> some View {
        let reserved = Reserved.read(proxy)
        // Clear of a camera at an edge, and of a fold through the middle:
        // the row keeps to the roomier side of it, the arrow with it.
        let clear = reserved.side(of: reserved.clearing(CGRect(origin: .zero, size: proxy.size)))
        let scale = min(max(cardWidth / 290, 0.8), 1.3)
        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4 * scale) {
                Text(journal.name)
                    .font(.system(size: 22 * scale, weight: .semibold, design: .rounded))
                    .foregroundStyle(TextTone.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(journal.subtitle)
                    .font(.system(size: 14 * scale))
                    .foregroundStyle(TextTone.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                // Your own journal: your last few days as five bubbles, each
                // in as much ink as its mark (build 65). Never on a circle's.
                if journal.circleId == nil, !journal.days, state.moodsAvailable {
                    Button { readingDays = true } label: {
                        LastFiveDays(levels: MarkSheet.lastFive(marks: state.moods), ink: TextTone.primary, size: 11 * scale)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2 * scale)
                }
                Pips(at: at, of: of, ink: TextTone.primary)
                    .padding(.top, 8 * scale)
            }
            Spacer(minLength: 8)
            Button { go(journal) } label: {
                GlassCircle(size: 44) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(palette.accent)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open \(journal.name)")
        }
        .frame(width: max(120, min(max(cardWidth, 220), clear.width - 2 * Self.margin)))
        // In the middle of its own room, beside the deck or under it.
        .position(x: clear.midX, y: clear.midY)
    }
}

/// Before iOS 27.1, which has no `ArrangementView`: the same two parts,
/// side by side when the room is wider than it's tall and one over the
/// other when it's taller, the deck taking the larger share.
private struct CoverArrangement: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        if bounds.width > bounds.height {
            let first = bounds.width * 0.6
            subviews[0].place(at: bounds.origin, proposal: ProposedViewSize(width: first, height: bounds.height))
            subviews[1].place(
                at: CGPoint(x: bounds.minX + first, y: bounds.minY),
                proposal: ProposedViewSize(width: bounds.width - first, height: bounds.height)
            )
        } else {
            let first = bounds.height * 0.72
            subviews[0].place(at: bounds.origin, proposal: ProposedViewSize(width: bounds.width, height: first))
            subviews[1].place(
                at: CGPoint(x: bounds.minX, y: bounds.minY + first),
                proposal: ProposedViewSize(width: bounds.width, height: bounds.height - first)
            )
        }
    }
}

/// What's reserved over a part of the screen (iOS 27.1): a fold the
/// content should divide around, and anything covering the screen (the
/// outer camera), with their margins for things that are pressed, in the
/// part's own coordinates. Empty before 27.1, and wherever nothing is.
struct Reserved {
    var folds: [CGRect] = []
    var covered: [CGRect] = []

    static func read(_ proxy: GeometryProxy) -> Reserved {
        var reserved = Reserved()
        if #available(iOS 27.1, *) {
            reserved.folds = proxy.reservedRegions(kind: .division).filter(\.isActive).map(\.frame)
            reserved.covered = proxy.reservedRegions(kind: .occlusion).filter(\.isActive).map(\.frame)
        }
        #if DEBUG
        // STANLEY_FAKE_FOLD=standing|lying: a fold down (or across) the
        // middle of the screen, 24pt with 12 either side, for seeing on a
        // simulator what only a folding device reports. Debug only.
        if let fake = ProcessInfo.processInfo.environment["STANLEY_FAKE_FOLD"], !fake.isEmpty {
            let screen = proxy.frame(in: .global)
            let bounds = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.screen.bounds ?? screen
            let band: CGRect = fake == "lying"
                ? CGRect(x: 0, y: bounds.midY - 24, width: bounds.width, height: 48)
                : CGRect(x: bounds.midX - 24, y: 0, width: 48, height: bounds.height)
            reserved.folds.append(band.offsetBy(dx: -screen.minX, dy: -screen.minY))
        }
        #endif
        return reserved
    }

    /// The part of `region` clear of what covers it at an edge: a camera
    /// over the top of it pushes it down, one at a side pushes it in. A
    /// fold running through the middle isn't an edge; `fold(across:)`.
    func clearing(_ region: CGRect) -> CGRect {
        var clear = region
        for cover in covered + folds where cover.intersects(clear) {
            let overlap = cover.intersection(clear)
            let touchesTop = overlap.minY <= clear.minY + 1
            let touchesBottom = overlap.maxY >= clear.maxY - 1
            let touchesLeading = overlap.minX <= clear.minX + 1
            let touchesTrailing = overlap.maxX >= clear.maxX - 1
            if touchesTop && !touchesBottom && overlap.height < clear.height / 2 {
                clear = CGRect(x: clear.minX, y: overlap.maxY, width: clear.width, height: clear.maxY - overlap.maxY)
            } else if touchesBottom && !touchesTop && overlap.height < clear.height / 2 {
                clear.size.height = overlap.minY - clear.minY
            } else if touchesLeading && !touchesTrailing && overlap.width < clear.width / 2 {
                clear = CGRect(x: overlap.maxX, y: clear.minY, width: clear.maxX - overlap.maxX, height: clear.height)
            } else if touchesTrailing && !touchesLeading && overlap.width < clear.width / 2 {
                clear.size.width = overlap.minX - clear.minX
            }
        }
        return clear
    }

    /// The roomier side of `region` where a fold runs through it; all of
    /// it where none does.
    func side(of region: CGRect) -> CGRect {
        guard let fold = fold(across: region) else { return region }
        if fold.height > fold.width {
            let before = CGRect(x: region.minX, y: region.minY, width: fold.minX - region.minX, height: region.height)
            let after = CGRect(x: fold.maxX, y: region.minY, width: region.maxX - fold.maxX, height: region.height)
            return before.width >= after.width ? before : after
        }
        let above = CGRect(x: region.minX, y: region.minY, width: region.width, height: fold.minY - region.minY)
        let below = CGRect(x: region.minX, y: fold.maxY, width: region.width, height: region.maxY - fold.maxY)
        return above.height >= below.height ? above : below
    }

    /// A fold running through `region`, from one side of it to the other,
    /// not at its edge: the deck divides around it.
    func fold(across region: CGRect) -> CGRect? {
        folds.first { fold in
            let overlap = fold.intersection(region)
            guard !overlap.isNull else { return false }
            let standing = overlap.height >= region.height - 1 && overlap.minX > region.minX + 40 && overlap.maxX < region.maxX - 40
            let lying = overlap.width >= region.width - 1 && overlap.minY > region.minY + 40 && overlap.maxY < region.maxY - 40
            return standing || lying
        }.map { $0.intersection(region) }
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

    /// The words' ink (build 69): on a photo always the off-white; on the
    /// warm field, whichever the field's light asks for (`CoverField.ink`),
    /// near-black on a light one.
    private var ink: CoverField.Ink {
        journal.cover == nil ? CoverField.ink(for: journal.id, dark: colorScheme == .dark) : .light
    }

    var body: some View {
        let shape = cardShape(scale)
        ZStack(alignment: .topLeading) {
            picture
            // Dark only where words in the off-white sit on the picture:
            // under the head and under the foot. Near-black words on a
            // light field have none (it would only darken what they need
            // light).
            if ink == .light {
                VStack(spacing: 0) {
                    LinearGradient(colors: [CoverTone.scrimHead, .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: size.height * CoverField.scrimHeadReach)
                    Spacer(minLength: 0)
                    LinearGradient(colors: [.clear, CoverTone.scrimFoot], startPoint: .top, endPoint: .bottom)
                        .frame(height: size.height * CoverField.scrimFootReach)
                }
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
        let light = ink == .light
        // The off-white's small capitals are at full strength (build 71; they
        // were at 70% on a shade of their own) and edged in a shadow round
        // each letter; the near-black's need neither.
        let shade = light
        return VStack(alignment: .leading, spacing: 0) {
            Text(journal.place)
                .font(label)
                .tracking(2.6 * scale)
                .textCase(.uppercase)
                .foregroundStyle(light ? TextTone.onPhoto : CoverTone.fieldLabel)
                .lineLimit(1)
                .shadedCapitals(scale, when: shade)
            Text(journal.title)
                .font(.custom(BookHand.font(44, bold: true).fontName, fixedSize: 44 * scale).leading(.tight))
                .foregroundStyle(light ? TextTone.onPhoto : CoverTone.fieldInk)
                .lineLimit(3)
                .minimumScaleFactor(0.5)
                .padding(.top, 10 * scale)
                .onLongPressGesture(minimumDuration: 0.45) { rename?() }
            Spacer(minLength: 12)
            Rectangle()
                .fill(light ? CoverTone.hairline : CoverTone.fieldHairline)
                .frame(height: max(0.5, 0.5 * scale))
            HStack {
                // Only once there's a first entry: an empty journal says
                // nothing about when it began.
                Text(dates)
                    .shadedCapitals(scale, when: shade && !dates.isEmpty)
                Spacer()
                Text("Vol. I")
                    .shadedCapitals(scale, when: shade)
            }
            .font(label)
            .tracking(2.6 * scale)
            .textCase(.uppercase)
            .foregroundStyle(light ? TextTone.onPhoto : CoverTone.fieldLabel)
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

extension View {
    /// The slab's small capitals, each letter edged in a tight shadow
    /// (build 71), so they read over a bright photo with no box behind
    /// them. Two passes: one close for the edge, one a little wider.
    @ViewBuilder
    func shadedCapitals(_ scale: CGFloat, when shown: Bool = true) -> some View {
        if shown {
            self
                .shadow(color: CoverTone.capitalsShadow, radius: 1.5 * scale)
                .shadow(color: CoverTone.capitalsShadow.opacity(0.75), radius: 4 * scale)
        } else {
            self
        }
    }
}

/// The room behind the cards (build 58, from the brief of 2026-11-14,
/// "Three fixes to the Journal cover screen"): the glass needs something
/// behind it. A journal with a cover photo lays it under everything, filling
/// the room, blurred heavily and veiled evenly (build 71: at night to 22% of
/// its brightness, by day to a tint under the card; `CoverTone.backdropVeil`),
/// so the words in the room need no shadow of their own. A journal with no
/// photo glows with its own warm colour, top left and bottom right, over the
/// floor at night and the card by day: never flat black or gray. Paging cross-fades from one journal's
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
        if journal.days {
            // Your days: the plain floor, no journal's photo or warmth.
            floor
        } else if let cover = journal.cover {
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
                CoverTone.backdropVeil(colorScheme, card: Atmosphere.resolve(raw).palette.card)
            }
        } else {
            glow(journal, floor: floor)
        }
    }

    private func glow(_ journal: CoverJournal, floor: Color) -> some View {
        let warmth = CoverTone.warmth(journal.id)
        let reach = max(size.width, size.height)
        return ZStack {
            // By day the card's light under it, so the words keep 4.5:1.
            colorScheme == .dark ? floor : Atmosphere.resolve(raw).palette.card
            RadialGradient(
                colors: [warmth.opacity(CoverTone.glowNear(colorScheme)), warmth.opacity(0)],
                center: .topLeading, startRadius: 0, endRadius: reach * 0.85
            )
            RadialGradient(
                colors: [warmth.opacity(CoverTone.glowFar(colorScheme)), warmth.opacity(0)],
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

/// Where the deck shows: its own room across, with the cards' shadows
/// running on up and down; softly at an edge that isn't the screen's (the
/// deck beside what's under it, or beside a rail).
private struct DeckWindow: View {
    let size: CGSize
    let card: CGFloat
    let y: CGFloat
    let softLeading: Bool
    let softTrailing: Bool

    var body: some View {
        let fade = min(28, size.width / 8)
        HStack(spacing: 0) {
            if softLeading {
                LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                    .frame(width: fade)
            }
            Rectangle()
            if softTrailing {
                LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: fade)
            }
        }
        .frame(width: size.width, height: card)
        .position(x: size.width / 2, y: y)
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
