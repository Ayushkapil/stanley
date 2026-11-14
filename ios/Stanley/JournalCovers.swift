import SwiftUI

// The covers (build 53, from the brief of 2026-11-14; it replaces build
// 52's cloth books). The Journal tab opens here: one journal to a page,
// paged sideways, yours first and then one for each circle you're in. Each
// is its cover photo, full bleed under a dark scrim, with a slab of glass
// laid over it: where it's kept and its title in a hand, and at its foot
// the dates it covers and its volume. The next journal's slab shows at the
// right edge, so it's plain there's more. Under the slab, the journal's
// name and a line, the pips that say which journal this is, and the arrow
// that opens it (as a tap on the slab does).
//
// The cover photo is your own newest keep in that journal, worked out on
// the server for you alone (`cover_photo_id`). The brief asked for the
// most-kept photo; that ranks by keeps and would let a circle see which was
// kept most, so it's your own newest keep instead (a product decision,
// 2026-11-14). Nothing kept yet: a flat warm field.

/// One journal on the table.
struct CoverJournal: Identifiable, Hashable {
    /// "mine", or the circle's id.
    let id: String
    let circleId: String?
    /// Small, at the slab's head: whose it is or where it's kept.
    let place: String
    /// In the hand, under that.
    let title: String
    /// Under the slab.
    let name: String
    let subtitle: String
    let cover: URL?
    let since: Date?
}

struct JournalCovers: View {
    @Environment(AppState.self) private var state
    @Environment(\.horizontalSizeClass) private var sizeClass
    let layout: BookLayout
    /// The whole screen the covers fill, under the bars too; and how much
    /// of it, from the top, is above the tab bar.
    let screen: CGSize
    let contentHeight: CGFloat
    /// Where the top bar's marks go: Letters, the week, Prompts.
    let bar: AnyView
    let open: (CoverJournal) -> Void
    @Binding var page: String
    @State private var renaming = false
    @State private var name = ""

    private var journals: [CoverJournal] {
        var all = [mine]
        if state.sharedAvailable {
            for circle in state.circles {
                all.append(CoverJournal(
                    id: circle.id, circleId: circle.id,
                    place: circle.name, title: "Ours",
                    name: circle.name, subtitle: "Shared with your circle",
                    cover: state.coverURL(circle.coverPhotoId),
                    since: circle.since.flatMap(WeekRange.day)
                ))
            }
        }
        return all
    }

    private var mine: CoverJournal {
        // The volume begins with the first thing in the book.
        let calendar = Calendar.current
        var earliest: [Date] = state.journalPages.compactMap { WeekRange.day($0.day) }
        earliest += state.reflections.map { calendar.startOfDay(for: $0.createdAt) }
        earliest += state.threads.flatMap(\.memories).compactMap { $0.anchoredAt }
        return CoverJournal(
            id: "mine", circleId: nil,
            place: state.profile?.displayName ?? "Yours",
            title: JournalName.shown(state.journalTitle),
            name: "Mine", subtitle: "Only you read it",
            cover: state.coverURL(state.journalCover),
            since: earliest.min()
        )
    }

    var body: some View {
        let journals = self.journals
        ZStack(alignment: .topLeading) {
            TabView(selection: $page) {
                ForEach(Array(journals.enumerated()), id: \.element.id) { at, journal in
                    CoverPage(
                        journal: journal, at: at, of: journals.count,
                        layout: layout, screen: screen, contentHeight: contentHeight, grows: sizeClass == .regular,
                        open: { open(journal) },
                        rename: journal.circleId == nil ? {
                            name = state.journalTitle ?? ""
                            renaming = true
                        } : nil
                    )
                    .tag(journal.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(width: screen.width, height: screen.height)
            .ignoresSafeArea()
            bar
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
}

/// One journal's cover, a page of the pager.
private struct CoverPage: View {
    @Environment(\.colorScheme) private var colorScheme
    let journal: CoverJournal
    let at: Int
    let of: Int
    let layout: BookLayout
    let screen: CGSize
    let contentHeight: CGFloat
    /// The Duo's inner display: the slab grows, the margins don't.
    let grows: Bool
    let open: () -> Void
    let rename: (() -> Void)?

    private static let peek: CGFloat = 56
    private static let gap: CGFloat = 14
    /// The flat field under a journal with nothing kept yet.
    private static let field = Color(red: 0x2B / 255, green: 0x34 / 255, blue: 0x30 / 255)

    var body: some View {
        // The slab: 290 by 416, larger on a large screen, smaller only if
        // the screen is too short to hold it and what's under it.
        let base = CGSize(width: 290, height: 416)
        let room = contentHeight - layout.safeTop - 70 - 190
        let scale = min(grows ? 1.35 : 1, max(0.7, room / base.height))
        let slab = CGSize(width: (base.width * scale).rounded(), height: (base.height * scale).rounded())
        // The slab sits so the next one's edge is flush with the screen's.
        let leading = max(16, layout.safeLeading + (layout.width + BookLayout.edge - layout.safeLeading
            - slab.width - Self.gap - Self.peek))
        ZStack(alignment: .topLeading) {
            background
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: layout.safeTop + 56)
                HStack(spacing: Self.gap) {
                    CoverSlab(journal: journal, size: slab, open: open, rename: rename)
                    if at < of - 1 {
                        // The next journal's slab, its edge showing.
                        SlabShape()
                            .fill(.clear)
                            .frame(width: slab.width, height: slab.height)
                            .background { SlabGlass() }
                            .frame(width: Self.peek, height: slab.height, alignment: .leading)
                            .clipped()
                            .accessibilityHidden(true)
                    }
                }
                underneath(width: slab.width)
                    .padding(.top, 22)
                Spacer(minLength: 20)
            }
            .padding(.leading, leading)
            .frame(width: screen.width, height: contentHeight, alignment: .topLeading)
        }
        .frame(width: screen.width, height: screen.height)
        .clipped()
        // Under the status bar too: the photo is full bleed, and what's on
        // it is placed from the screen's top (`layout.safeTop`).
        .ignoresSafeArea()
    }

    /// The cover photo full bleed, under a scrim dark at the foot, light in
    /// the middle and a little dark again at the top; or the flat field.
    @ViewBuilder
    private var background: some View {
        ZStack {
            Self.field
            if let cover = journal.cover {
                SignedImage(url: cover) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Self.field
                }
                .frame(width: screen.width, height: screen.height)
                .clipped()
            }
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.28), location: 0),
                    .init(color: .black.opacity(0.1), location: 0.45),
                    .init(color: .black.opacity(0.72), location: 1),
                ],
                startPoint: .top, endPoint: .bottom
            )
        }
        .frame(width: screen.width, height: screen.height)
        .accessibilityHidden(true)
    }

    /// Under the slab: the journal's name and a line, the pips, and the
    /// arrow that opens it.
    private func underneath(width: CGFloat) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(journal.name)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(journal.subtitle)
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(1)
                Pips(at: at, of: of)
                    .padding(.top, 8)
            }
            Spacer(minLength: 8)
            Button(action: open) {
                GlassCircle(size: 44) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open \(journal.name)")
        }
        .frame(width: width)
        .shadow(color: .black.opacity(0.35), radius: 6, y: 1)
    }
}

/// Which journal this is: a pip each, this one's full.
private struct Pips: View {
    let at: Int
    let of: Int

    var body: some View {
        HStack(spacing: 7) {
            ForEach(0..<max(of, 1), id: \.self) { index in
                Circle()
                    .fill(.white.opacity(index == at ? 0.95 : 0.35))
                    .frame(width: 6, height: 6)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Journal \(at + 1) of \(of)")
    }
}

/// The slab's outline: corners of 30.
private func SlabShape() -> RoundedRectangle {
    RoundedRectangle(cornerRadius: 30, style: .continuous)
}

/// The slab's glass: material in daylight, a little white in the dark
/// (where material over black goes muddy), a thin white edge, a shine
/// across its top left corner, and a soft shadow down and to the right.
private struct SlabGlass: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let dark = colorScheme == .dark
        ZStack {
            if dark {
                SlabShape().fill(Color.white.opacity(0.08))
            } else {
                SlabShape().fill(.ultraThinMaterial)
            }
            SlabShape()
                .fill(LinearGradient(
                    colors: [.white.opacity(0.4), .white.opacity(0)],
                    startPoint: .topLeading, endPoint: UnitPoint(x: 0.45, y: 0.35)
                ))
            SlabShape().strokeBorder(Color.white.opacity(0.55), lineWidth: 0.5)
        }
        .compositingGroup()
        .shadow(color: .black.opacity(0.3), radius: 18, x: 8, y: 12)
    }
}

/// The slab itself: where it's kept, small; its title in the hand; and at
/// its foot, under a hairline, the dates it covers and its volume.
private struct CoverSlab: View {
    let journal: CoverJournal
    let size: CGSize
    let open: () -> Void
    let rename: (() -> Void)?

    var body: some View {
        let inset = 26 * size.width / 290
        VStack(alignment: .leading, spacing: 0) {
            Text(journal.place)
                .font(.system(size: 8.5, weight: .semibold))
                .tracking(2.6)
                .textCase(.uppercase)
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
            Text(journal.title)
                .font(.custom(BookHand.font(44, bold: true).fontName, fixedSize: 44 * size.width / 290).leading(.tight))
                .foregroundStyle(.white)
                .lineLimit(3)
                .minimumScaleFactor(0.5)
                .padding(.top, 10)
                .onLongPressGesture(minimumDuration: 0.45) { rename?() }
            Spacer(minLength: 12)
            Rectangle()
                .fill(.white.opacity(0.45))
                .frame(height: 0.5)
            HStack {
                Text(dates)
                Spacer()
                Text("Vol. I")
            }
            .font(.system(size: 8.5, weight: .semibold))
            .tracking(2.6)
            .textCase(.uppercase)
            .foregroundStyle(.white.opacity(0.85))
            .padding(.top, 12)
        }
        .padding(inset)
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .background { SlabGlass() }
        .contentShape(SlabShape())
        .onTapGesture(perform: open)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(journal.title), \(journal.place). \(dates), volume one")
        .accessibilityHint("Opens it")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { open() }
        .accessibilityActions {
            if let rename { Button("Rename", action: rename) }
        }
    }

    /// "Oct 2026 – now", or this month alone.
    private var dates: String {
        guard let since = journal.since else { return "Since now" }
        let start = since.formatted(.dateTime.month(.abbreviated).year())
        if Calendar.current.isDate(since, equalTo: .now, toGranularity: .month) { return start }
        return start + " – now"
    }
}
