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
            Group {
                if density.isRoom { magazine } else { column }
            }
            .foldAnimated(hSizeClass)
            .journalPage()
            .navigationTitle("Held")
            .navigationDestination(isPresented: $showRested) { RestedView() }
            .refreshable { await state.refreshMemories() }
            .task { await state.refreshMemories() }
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
    }

    /// Held has answered and holds nothing, or can't answer yet. Before the
    /// first answer an empty album would only be one still loading.
    private var showsEmpty: Bool {
        state.threads.isEmpty && (state.memoriesLoaded || state.offline)
    }

    /// An empty album: a page with four photo corners waiting for the first
    /// print, and what goes in them, in a hand. Offline, an empty album may
    /// only be one that hasn't loaded yet, so it says that instead.
    private var emptyNote: some View {
        HStack(alignment: .top, spacing: 20) {
            Color.clear
                .aspectRatio(PhotoShape.aspect, contentMode: .fit)
                .frame(width: 78)
                .overlay { PhotoCorners(size: 13) }
                .padding(.top, 6)
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

    /// A friend's page in the album: whose, in a hand, with their face.
    private func pageHead(_ thread: MemoryThread) -> some View {
        JournalSectionHead(label: "Kept from", title: thread.friend.displayName) {
            AvatarView(url: thread.friend.avatarUrl, name: thread.friend.displayName, size: 32)
        }
    }

    /// The outer display (and every ordinary iPhone): one print to a line,
    /// laid alternately toward the left and the right of the page the way
    /// an album is filled by hand. Swipe a print to rest it.
    private var column: some View {
        List {
            Group {
                masthead
                    .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 8, trailing: 20))
                if showsEmpty {
                    emptyNote
                        .listRowInsets(EdgeInsets(top: 22, leading: 22, bottom: 0, trailing: 22))
                }
                ForEach(state.threads) { thread in
                    pageHead(thread)
                        .listRowInsets(EdgeInsets(top: 26, leading: 20, bottom: 14, trailing: 20))
                    ForEach(Array(thread.memories.enumerated()), id: \.element.id) { position, memory in
                        MemoryCard(memory: memory)
                            .padding(.leading, position.isMultiple(of: 2) ? 0 : 44)
                            .padding(.trailing, position.isMultiple(of: 2) ? 44 : 0)
                            .listRowInsets(EdgeInsets(top: 12, leading: 26, bottom: 18, trailing: 26))
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
    }

    /// The inner display: an open album, two prints to a line with room
    /// between them, the second set a little lower, as if pasted in by hand.
    /// Resting is a long press, because a print in a spread has no edge to
    /// swipe — the action itself is unchanged.
    private var magazine: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 34) {
                masthead
                if showsEmpty {
                    emptyNote.padding(.top, 10)
                }
                ForEach(state.threads) { thread in
                    VStack(alignment: .leading, spacing: 22) {
                        pageHead(thread)
                        LazyVGrid(
                            columns: Array(
                                repeating: GridItem(.flexible(), spacing: 34),
                                count: density.heldColumns
                            ),
                            alignment: .leading,
                            spacing: 30
                        ) {
                            ForEach(Array(thread.memories.enumerated()), id: \.element.id) { position, memory in
                                MemoryCard(memory: memory)
                                    .padding(.top, position % density.heldColumns == 1 ? 24 : 0)
                                    .contextMenu { restMenu(memory) }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 30)
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
/// slipped into four photo corners and laid a little crooked, with its
/// words written beneath it. A tombstone keeps only the corners, around
/// where the print was.
struct MemoryCard: View {
    @Environment(AppState.self) private var state
    @Environment(\.horizontalSizeClass) private var hSizeClass
    private var density: Density { Density(hSizeClass) }
    let memory: Memory

    /// Held gathers every circle. Which one a memory is from is worth saying
    /// once there's more than one to tell apart.
    private var showsCircle: Bool {
        state.circles.count > 1 || Set(state.threads.flatMap(\.memories).compactMap(\.circleName)).count > 1
    }

    private var heldTrace: String? {
        guard let taken = memory.takenAt else { return nil }
        return "held · \(taken.formatted(date: .abbreviated, time: .omitted))"
    }

    /// Laid by hand: twice a Today print's lean, the way an album is filled.
    private var tilt: Double { PrintTilt.degrees(memory.id) * 2 }

    /// "Collins · held · 20 Jul 2026": where, then when it was kept.
    private var whereAndWhen: String? {
        let place = memory.location.flatMap { $0.isEmpty ? nil : $0 }
        let parts = [place, heldTrace].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var body: some View {
        if memory.isTombstone {
            // An honest absence: the corners are still on the page where the
            // print was, and the words say what was there. A marker, not a
            // monument, so it's smaller than a print.
            VStack(alignment: .leading, spacing: 4) {
                Text("A memory was here")
                    .font(.hand(18, relativeTo: .body))
                    .foregroundStyle(.secondary)
                if let date = memory.date {
                    Text(date).smallCaps()
                }
            }
            .frame(maxWidth: .infinity, minHeight: 92)
            .overlay { PhotoCorners(size: 14) }
            .padding(10)
            .rotationEffect(.degrees(tilt))
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
                        .asPrint(border: 8)
                        .overlay { PhotoCorners() }
                        .rotationEffect(.degrees(tilt))
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
                    .frame(width: 52, height: 60)
                    .overlay { PhotoCorners(size: 9) }
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
