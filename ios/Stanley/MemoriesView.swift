import SwiftUI

/// The kept archive, as a personal photo album (build 20): a page per
/// friend, headed with their name, and each memory a print slipped into
/// four black photo corners, laid by hand (staggered, a little crooked),
/// with its words written beneath it. Tombstones are honest: the corners
/// stay where the print was, around "a memory was here" (§8.2).
struct MemoriesView: View {
    @Environment(AppState.self) private var state
    @Environment(\.horizontalSizeClass) private var hSizeClass
    private var density: Density { Density(hSizeClass) }
    @State private var showRested = false

    var body: some View {
        NavigationStack {
          ScrollViewReader { proxy in
            Group {
                if density.isRoom { magazine(proxy) } else { column(proxy) }
            }
            .foldAnimated(hSizeClass)
            .journalPage()
            .navigationTitle("Held")
            .navigationDestination(isPresented: $showRested) { RestedView() }
            .refreshable {
                Haptics.refreshed()
                await state.refreshMemories()
            }
            .task { await state.refreshMemories() }
          }
        }
    }

    /// "Held", as the album's title page: the masthead, with Rested at its end.
    private var masthead: some View {
        JournalMasthead(title: "Held", line: "The one place nothing fades") {
            Button { showRested = true } label: {
                Label("Rested", systemImage: "moon.zzz")
                    .labelStyle(.iconOnly)
                    .font(.title3)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Rested")
        }
        .id("masthead")
    }

    /// Held has answered and holds nothing, or can't answer yet. Before the
    /// first answer an empty album would only be one still loading.
    private var showsEmpty: Bool {
        state.threads.isEmpty && (state.memoriesLoaded || state.offline)
    }

    /// An empty album: a page with a blank print waiting for its first
    /// picture, and what it's for, in a hand. Offline, an empty album may
    /// only be one that hasn't loaded yet, so it says that instead.
    private var emptyNote: some View {
        HStack(alignment: .top, spacing: 20) {
            Color.clear
                .aspectRatio(PhotoShape.aspect, contentMode: .fit)
                .frame(width: 72)
                .overlay(RoundedRectangle(cornerRadius: PrintStock.photoCorner, style: .continuous).fill(.quaternary))
                .asPrint(border: 6, tilt: -1.4)
                .padding(.top, 8)
                .padding(.leading, 4)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                if state.offline && !state.memoriesLoaded {
                    Text("Not here yet.")
                        .font(.hand(28, bold: true, relativeTo: .title2))
                    Text("What you've held comes back with the connection.")
                        .font(.hand(20, relativeTo: .body))
                        .foregroundStyle(.secondary)
                } else {
                    Text("Nothing held yet.")
                        .font(.hand(28, bold: true, relativeTo: .title2))
                    // Not "forever": the person in a photo can still take it
                    // back (the subject wins on deletion). Fading can't.
                    Text("When you press and hold someone's moment, it lives here, long after it fades.")
                        .font(.hand(20, relativeTo: .body))
                        .foregroundStyle(.secondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 26)
        .frame(maxWidth: .infinity, alignment: .leading)
        .paperInsert(tilt: 0.7)
        .accessibilityElement(children: .combine)
    }

    /// A friend's page in the album: whose, in a hand, with their face. Your
    /// own photos, kept by you, are "Me" (the polish pass): you know who you are.
    private func pageHead(_ thread: MemoryThread) -> some View {
        let isMe = state.myId != nil && thread.friend.id == state.myId
        return JournalSectionHead(label: "Kept from", title: isMe ? "Me" : thread.friend.displayName) {
            AvatarView(url: thread.friend.avatarUrl, name: thread.friend.displayName, size: 32)
        }
    }

    /// The outer display (and every ordinary iPhone): one print to a line,
    /// laid alternately toward the left and the right of the page the way
    /// an album is filled by hand. Swipe a print to rest it.
    private func column(_ proxy: ScrollViewProxy) -> some View {
        List {
            Group {
                masthead
                    .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 8, trailing: 20))
                if showsEmpty {
                    emptyNote
                        .listRowInsets(EdgeInsets(top: Spacing.section, leading: 22, bottom: 0, trailing: 22))
                }
                ForEach(state.threads) { thread in
                    pageHead(thread)
                        .listRowInsets(EdgeInsets(top: Spacing.chapter, leading: 20, bottom: 0, trailing: 20))
                    ForEach(Array(thread.memories.enumerated()), id: \.element.id) { position, memory in
                        MemoryCard(memory: memory, place: position)
                            .padding(.leading, position.isMultiple(of: 2) ? 0 : 44)
                            .padding(.trailing, position.isMultiple(of: 2) ? 44 : 0)
                            // A section's room either side: a print is the
                            // same distance from the next as a page head is
                            // from its first.
                            .listRowInsets(EdgeInsets(
                                top: Spacing.section, leading: 26, bottom: Spacing.section, trailing: 26
                            ))
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if !memory.isTombstone {
                                    Button {
                                        Task { await state.rest(photoId: memory.id) }
                                    } label: {
                                        Label("Rest this memory", systemImage: "moon.zzz")
                                    }
                                    .tint(.indigo)
                                }
                            }
                    }
                }
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        // The same room above the tab bar as every page.
        .contentMargins(.bottom, Spacing.chapter, for: .scrollContent)
        // A tap on the Held tab: back to the top, or at the top the pull's
        // own refresh (`TabTaps`).
        .onTabTap(state.tabTaps.held, scroll: proxy, to: "masthead") {
            await state.refreshMemories()
        }
    }

    /// The inner display: an open album, two prints to a line with room
    /// between them, the second set a little lower, as if pasted in by hand.
    /// Resting is a long press, because a print in a spread has no edge to
    /// swipe — the action itself is unchanged.
    private func magazine(_ proxy: ScrollViewProxy) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.chapter) {
                masthead
                if showsEmpty {
                    emptyNote
                }
                ForEach(state.threads) { thread in
                    VStack(alignment: .leading, spacing: Spacing.section) {
                        pageHead(thread)
                        LazyVGrid(
                            columns: Array(
                                repeating: GridItem(.flexible(), spacing: Spacing.chapter),
                                count: density.heldColumns
                            ),
                            alignment: .leading,
                            spacing: Spacing.chapter
                        ) {
                            ForEach(Array(thread.memories.enumerated()), id: \.element.id) { position, memory in
                                MemoryCard(memory: memory, place: position)
                                    .padding(.top, position % density.heldColumns == 1 ? 24 : 0)
                                    .contextMenu { restMenu(memory) }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, Spacing.chapter)
        }
        .onTabTap(state.tabTaps.held, scroll: proxy, to: "masthead") {
            await state.refreshMemories()
        }
    }

    @ViewBuilder
    private func restMenu(_ memory: Memory) -> some View {
        if !memory.isTombstone {
            Button {
                Task { await state.rest(photoId: memory.id) }
            } label: {
                Label("Rest this memory", systemImage: "moon.zzz")
            }
        }
    }
}

/// Rested memories (§14): set never to resurface, but not deleted — still here,
/// each with a gentle "let it return" undo.
struct RestedView: View {
    @Environment(AppState.self) private var state
    @State private var memories: [Memory] = []
    @State private var loaded = false

    var body: some View {
        List {
            if loaded && memories.isEmpty {
                Text("Nothing rested. Memories you rest stay in Held but never resurface on their own.")
                    .font(.hand(19, relativeTo: .body))
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            }
            ForEach(memories) { memory in
                HStack(spacing: 12) {
                    MemoryRow(memory: memory)
                    Button("Let it return") {
                        Task {
                            await state.unrest(photoId: memory.id)
                            await reload()
                        }
                    }
                    .font(.caption)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.tint)
                }
                .atmosphereRows()
            }
        }
        .atmosphereWash()
        .navigationTitle("Rested")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: state.reloads) { await reload() }
    }

    private func reload() async {
        memories = await state.loadRested()
        loaded = true
    }
}

/// A kept memory on the album page (Held tab): the print at full saturation,
/// on its photo paper as in Today, laid a little crooked, with its words
/// written beneath it. A tombstone is a blank print with the words on it,
/// where the picture was. (Builds 20 to 23 slipped each print into four
/// photo corners; pilot users called them cringe.)
struct MemoryCard: View {
    @Environment(AppState.self) private var state
    @Environment(\.horizontalSizeClass) private var hSizeClass
    private var density: Density { Density(hSizeClass) }
    let memory: Memory
    /// Where it comes on its page, counting from 0: the album lays prints
    /// alternately toward the left and the right, and each leans with its
    /// side.
    var place: Int = 0

    /// Held gathers every circle. Which one a memory is from is worth saying
    /// once there's more than one to tell apart.
    private var showsCircle: Bool {
        state.circles.count > 1 || Set(state.threads.flatMap(\.memories).compactMap(\.circleName)).count > 1
    }

    private var heldTrace: String? {
        guard let taken = memory.takenAt else { return nil }
        return "held · \(taken.formatted(date: .abbreviated, time: .omitted))"
    }

    /// Laid by hand: a Today print's slight lean, by its own amount, and
    /// alternating with the side it's laid toward, so the page reads as
    /// filled left, right, left.
    private var tilt: Double {
        let lean = max(0.35, abs(PrintTilt.degrees(memory.id)))
        return place.isMultiple(of: 2) ? -lean : lean
    }

    /// "Collins · held · 20 Jul 2026": where, then when it was kept.
    private var whereAndWhen: String? {
        let place = memory.location.flatMap { $0.isEmpty ? nil : $0 }
        let parts = [place, heldTrace].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var body: some View {
        if memory.isTombstone {
            // An honest absence: a blank print still on the page where the
            // picture was, with the words written on it. A marker, not a
            // monument, so it's smaller than a print.
            VStack(spacing: 4) {
                Text("A memory was here")
                    .font(.hand(18, relativeTo: .body))
                    .foregroundStyle(.secondary)
                if let date = memory.date {
                    Text(date).smallCaps()
                }
            }
            .frame(maxWidth: .infinity, minHeight: 92)
            .asPrint(border: 8, tilt: tilt)
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                if let urls = memory.urls, let url = state.api.absoluteURL(urls.image) {
                    Color.clear
                        .frame(height: density.heldPhotoHeight)
                        .overlay {
                            SignedImage(url: url) { image in
                                image.resizable().aspectRatio(contentMode: .fill)
                            } placeholder: {
                                Rectangle().fill(.quaternary)
                            }
                        }
                        // Held is the one place nothing fades, so it should feel
                        // physically different from the feed: a faint sheen,
                        // the way a print catches the light.
                        .overlay {
                            LinearGradient(
                                colors: [
                                    .white.opacity(0.10),
                                    .clear,
                                    .clear,
                                    .black.opacity(0.06),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            .blendMode(.softLight)
                            .allowsHitTesting(false)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: PrintStock.photoCorner, style: .continuous))
                        .asPrint(border: 8, tilt: tilt)
                        .padding(.vertical, 4)
                }
                // Written on the page beneath the print, the way an album is
                // annotated: what it was, then where and when, in smaller ink.
                VStack(alignment: .leading, spacing: 3) {
                    if let caption = memory.caption, !caption.isEmpty {
                        Text(caption)
                            .font(.hand(19, relativeTo: .body))
                    } else if let takenAt = memory.takenAt {
                        Text(takenAt, style: .date)
                            .font(.hand(19, relativeTo: .body))
                    }
                    if let line = whereAndWhen {
                        Text(line).smallCaps()
                    }
                    if showsCircle, let circleName = memory.circleName {
                        CircleTag(name: circleName)
                            .padding(.top, 2)
                    }
                    if let note = memory.note, !note.isEmpty {
                        Text(note)
                            .font(.hand(16, relativeTo: .callout))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    // Your own photo: what you wrote about the day, beneath
                    // it, yours alone (build 26).
                    if let journal = memory.journal, !journal.isEmpty {
                        HeldJournalNote(memory: memory, words: journal)
                            .padding(.top, 6)
                    }
                }
                .padding(.horizontal, 4)
            }
        }
    }
}

/// Which circle a held memory is from: its name, in small capitals, after a
/// dotted circle.
struct CircleTag: View {
    let name: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "circle.dotted")
            Text(name)
        }
        .smallCaps()
        .lineLimit(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("From \(name)")
    }
}

struct MemoryRow: View {
    @Environment(AppState.self) private var state
    let memory: Memory

    private var heldTrace: String? {
        guard let taken = memory.takenAt else { return nil }
        return "held · \(taken.formatted(date: .abbreviated, time: .omitted))"
    }

    var body: some View {
        HStack(spacing: 14) {
            if memory.isTombstone {
                Color.clear
                    .frame(width: 48, height: 56)
                    .asPrint(border: 3, tilt: PrintTilt.degrees(memory.id) * 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text("A memory was here")
                        .font(.hand(17, relativeTo: .callout))
                        .foregroundStyle(.secondary)
                    if let date = memory.date {
                        Text(date).smallCaps()
                    }
                }
            } else {
                if let urls = memory.urls, let url = state.api.absoluteURL(urls.thumb) {
                    SignedImage(url: url) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Rectangle().fill(.quaternary)
                    }
                    .frame(width: 48, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: PrintStock.photoCorner))
                    .asPrint(border: 3, tilt: PrintTilt.degrees(memory.id) * 2)
                }
                VStack(alignment: .leading, spacing: 2) {
                    if let caption = memory.caption, !caption.isEmpty {
                        Text(caption).font(.hand(17, relativeTo: .callout)).lineLimit(1)
                    } else if let takenAt = memory.takenAt {
                        Text(takenAt, style: .date).font(.hand(17, relativeTo: .callout))
                    }
                    if let location = memory.location, !location.isEmpty {
                        Text(location)
                            .smallCaps()
                            .lineLimit(1)
                    }
                    if let note = memory.note, !note.isEmpty {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if let heldTrace {
                        Text(heldTrace)
                            .smallCaps(9)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}
