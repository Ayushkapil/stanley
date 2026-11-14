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
    /// The date's line along the top, with Letters and Prompts at its
    /// right: drawn for a left edge, a right edge and a middle (the card's
    /// edges, so the three line up).
    let bar: (_ left: CGFloat, _ right: CGFloat, _ y: CGFloat) -> AnyView
    let open: (CoverJournal) -> Void
    @Binding var page: String
    @State private var shown: String?
    @State private var renaming = false
    @State private var name = ""

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

    /// The card: about three quarters of the room across, held at 290 by
    /// 416, never over 420 wide, and no taller than the room leaves under
    /// the bar and above what's written under it.
    private var card: CGSize {
        let below: CGFloat = 150
        let tallest = height - layout.safeTop - 76 - below - 16
        let across = min(420, (width * 0.74).rounded())
        let down = (across * 416 / 290).rounded()
        guard down > tallest else { return CGSize(width: across, height: down) }
        let fitted = max(240, tallest)
        return CGSize(width: (fitted * 290 / 416).rounded(), height: fitted)
    }

    var body: some View {
        let journals = self.journals
        let card = self.card
        let gap = (14 * card.width / 290).rounded()
        let peek = (56 * card.width / 290).rounded()
        // The card's leading edge: so the next one's edge shows at least
        // `peek` wide at the room's right (which stops short of a side
        // dock), and centered once there's room for that.
        let leading = max(16, min(((width - card.width) / 2).rounded(), width - card.width - gap - peek))
        let current = journals.first { $0.id == (shown ?? page) } ?? journals[0]
        let at = journals.firstIndex(of: current) ?? 0

        ZStack(alignment: .topLeading) {
            palette.floor
                .frame(width: width, height: height)
                .ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: layout.safeTop + 72)
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
                                            ? Label("Unmute This Journal", systemImage: "bell")
                                            : Label("Mute This Journal", systemImage: "bell.slash")
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
                .contentMargins(.trailing, max(16, width - leading - card.width), for: .scrollContent)
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $shown)
                .frame(width: width, height: card.height + 24)
                // Shadows run on up and down; sideways the cards stop at the
                // room's edge, which stops short of a side dock (the Duo's
                // cover), so the next card's edge is never under the dock.
                .scrollClipDisabled()
                .mask {
                    Rectangle()
                        .frame(width: width, height: card.height + 140)
                }
                underneath(current, at: at, of: journals.count, width: card.width, scale: card.width / 290)
                    .padding(.leading, leading)
                    .padding(.top, 14)
                Spacer(minLength: 16)
            }
            .frame(width: width, height: height, alignment: .topLeading)
            bar(leading, leading + card.width, layout.safeTop + 30)
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .onAppear { shown = page }
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

    /// The atmosphere's accent warmed and graded: a field, never flat gray.
    private var field: some View {
        let accent = Atmosphere.resolve(raw).palette.accent
        return ZStack {
            // A warm ground, the palette's accent laid lightly over it, and
            // light coming in from the top left (`CoverTone`).
            CoverTone.ground(colorScheme)
            accent.opacity(CoverTone.accentWash(colorScheme))
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
