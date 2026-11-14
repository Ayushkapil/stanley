import SwiftUI

/// The Journal tab (build 44; "Held" until then): the person's own space.
/// What they've kept, a page per friend, each photo cut as in Today but
/// laid a little crooked, the album's way; the letters written to them;
/// the pages of their own journal (the weekly reflections, which were at
/// the foot of the You tab); and the circle's questions. Its headings are
/// in a hand, because this page is theirs. Tombstones are honest: "a
/// memory was here" where the photo was (§8.2). Resting a memory was
/// removed in build 44.
struct MemoriesView: View {
    @Environment(AppState.self) private var state
    @Environment(\.horizontalSizeClass) private var hSizeClass
    private var density: Density { Density(hSizeClass) }
    @State private var readingQuestions = false
    /// The held photo opened to the whole screen (build 39), and whether
    /// it's open. The album's prints are where it grows from and goes back to.
    @State private var opened = ""
    @State private var viewing = false
    @Namespace private var album

    private func open(_ memory: Memory) {
        opened = memory.id
        viewing = true
    }

    var body: some View {
        NavigationStack {
          ScrollViewReader { proxy in
            Group {
                if density.isRoom { magazine(proxy) } else { column(proxy) }
            }
            .foldAnimated(hSizeClass)
            .journalPage()
            .navigationTitle("Journal")
            .navigationDestination(isPresented: $readingQuestions) { CircleJournalView() }
            .fullScreenCover(isPresented: $viewing) {
                HeldViewer(current: $opened)
                    .heroZoom(from: opened, in: album)
            }
            .sunRefreshable {
                Haptics.refreshed()
                await Task {
                    await state.refreshMemories()
                    await state.loadThisWeek()
                    await state.loadReflections()
                }.value
            }
            .task {
                await state.refreshMemories()
                await state.loadThisWeek()
                await state.loadReflections()
            }
          }
        }
    }

    /// The page's name, in a hand: this one is the person's own.
    private var masthead: some View {
        JournalMasthead(title: "Journal", line: "Kept, written, and yours", hand: true)
            .id("masthead")
    }

    /// Sunday evening: "How was your week?", until midnight or until it's
    /// written (it sat atop the You tab until build 44).
    @ViewBuilder
    private var sundayCard: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            if ReflectionWindow.isOpen(context.date), let week = state.thisWeek, week.reflection == nil {
                ReflectionCard(week: week)
            }
        }
    }

    /// The pages of your own journal: each week's reflection, newest
    /// first, on cream paper in your hand.
    @ViewBuilder
    private var pages: some View {
        if !state.reflections.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.section) {
                JournalSectionHead(label: "Only you see this", title: "Pages", hand: true)
                if density.isRoom {
                    LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: Spacing.section), GridItem(.flexible())],
                        alignment: .leading, spacing: Spacing.section
                    ) {
                        ForEach(state.reflections) { ReflectionPage(reflection: $0) }
                    }
                } else {
                    ForEach(state.reflections) { ReflectionPage(reflection: $0) }
                }
                if state.reflectionsCursor != nil {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .task(id: state.reflectionsCursor) { await state.loadMoreReflections() }
                }
            }
        }
    }

    /// The circle's questions: this week's in serif, and the way to every
    /// week whose answers are out (the circle journal).
    @ViewBuilder
    private var questions: some View {
        if state.circle != nil {
            VStack(alignment: .leading, spacing: Spacing.section) {
                JournalSectionHead(label: state.circle?.name, title: "Questions", hand: true)
                Button { readingQuestions = true } label: {
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            if let question = state.question {
                                Text(question.prompt.text)
                                    .questionType(.body)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                                if let mine = question.response {
                                    Text(mine.body)
                                        .font(.hand(17, relativeTo: .callout))
                                        .multilineTextAlignment(.leading)
                                        .lineLimit(3)
                                }
                            }
                            Text("Every week's question, and what everyone said")
                                .quietLabel()
                                .multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .card()
                .accessibilityHint("Opens the circle journal")
            }
        }
    }

    /// Held has answered and holds nothing, or can't answer yet. Before the
    /// first answer an empty album would only be one still loading.
    private var showsEmpty: Bool {
        state.threads.isEmpty && (state.memoriesLoaded || state.offline)
    }

    /// Nothing kept yet: what this page is for. Offline, an empty album
    /// may only be one that hasn't loaded yet, so it says that instead.
    private var emptyNote: some View {
        VStack(alignment: .leading, spacing: 6) {
            if state.offline && !state.memoriesLoaded {
                Text("Not here yet.")
                    .font(.hand(24, bold: true, relativeTo: .title2))
                Text("What you've held comes back with the connection.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("Nothing held yet.")
                    .font(.hand(24, bold: true, relativeTo: .title2))
                // Not "forever": the person in a photo can still take it
                // back (the subject wins on deletion). Fading can't.
                Text("When you press and hold someone's moment, or tap its bookmark, it lives here, long after it fades.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(h: 20, v: 20)
        .accessibilityElement(children: .combine)
    }

    /// A friend's page in the album: whose, in a hand, with their face. Your
    /// own photos, kept by you, are "Me" (the polish pass): you know who you are.
    private func pageHead(_ thread: MemoryThread) -> some View {
        let isMe = state.myId != nil && thread.friend.id == state.myId
        return JournalSectionHead(label: "Kept from", title: isMe ? "Me" : thread.friend.displayName, hand: true) {
            AvatarView(url: thread.friend.avatarUrl, name: thread.friend.displayName, size: 32)
        }
    }

    /// The outer display (and every ordinary iPhone): one photo to a line,
    /// laid alternately toward the left and the right of the page the way
    /// an album is filled by hand.
    private func column(_ proxy: ScrollViewProxy) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                masthead
                sundayCard
                    .padding(.top, Spacing.section)
                // Letters to you (build 42): sealed envelopes, then opened
                // ones, at the top of the page.
                if !state.lettersReceived.sealed.isEmpty || !state.lettersReceived.opened.isEmpty {
                    LettersOnHeld()
                        .padding(.top, Spacing.chapter)
                }
                if showsEmpty {
                    emptyNote
                        .padding(.top, Spacing.section)
                }
                ForEach(state.threads) { thread in
                    pageHead(thread)
                        .padding(.top, Spacing.chapter)
                    let mine = state.myId != nil && thread.friend.id == state.myId
                    ForEach(Array(thread.memories.enumerated()), id: \.element.id) { position, memory in
                        MemoryCard(memory: memory, place: position, mine: mine, album: album) { open(memory) }
                            .padding(.leading, position.isMultiple(of: 2) ? 0 : 36)
                            .padding(.trailing, position.isMultiple(of: 2) ? 36 : 0)
                            .padding(.horizontal, 6)
                            .padding(.vertical, Spacing.section)
                    }
                }
                pages
                    .padding(.top, Spacing.chapter)
                questions
                    .padding(.top, Spacing.chapter)
            }
            .padding(.horizontal, 20)
            // The same room above the tab bar as every page.
            .padding(.bottom, Spacing.chapter)
        }
        // A tap on the Journal tab: back to the top, or at the top the
        // pull's own refresh (`TabTaps`).
        .onTabTap(state.tabTaps.held, scroll: proxy, to: "masthead") {
            await state.refreshMemories()
            await state.loadReflections()
        }
    }

    /// The inner display: an open album, two photos to a line with room
    /// between them, the second set a little lower, as if pasted in by
    /// hand; the journal's pages two to a line as well.
    private func magazine(_ proxy: ScrollViewProxy) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.chapter) {
                masthead
                sundayCard
                if !state.lettersReceived.sealed.isEmpty || !state.lettersReceived.opened.isEmpty {
                    LettersOnHeld()
                }
                if showsEmpty {
                    emptyNote
                }
                ForEach(state.threads) { thread in
                    let mine = state.myId != nil && thread.friend.id == state.myId
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
                                MemoryCard(memory: memory, place: position, mine: mine, album: album) { open(memory) }
                                    .padding(.top, position % density.heldColumns == 1 ? 24 : 0)
                            }
                        }
                    }
                }
                pages
                questions
            }
            .padding(.horizontal, 28)
            .padding(.bottom, Spacing.chapter)
        }
        .onTabTap(state.tabTaps.held, scroll: proxy, to: "masthead") {
            await state.refreshMemories()
            await state.loadReflections()
        }
    }
}

/// A kept memory in the Journal tab: the photo at full saturation, cut as
/// in Today, laid a little crooked in daylight (the album's way), with its
/// words beneath it: the caption in a hand on your own photo, plain on
/// anyone else's. A tombstone is an empty frame with the words in it,
/// where the picture was.
struct MemoryCard: View {
    @Environment(AppState.self) private var state
    @Environment(\.horizontalSizeClass) private var hSizeClass
    private var density: Density { Density(hSizeClass) }
    let memory: Memory
    /// Where it comes on its page, counting from 0: the album lays prints
    /// alternately toward the left and the right, and each leans with its
    /// side.
    var place: Int = 0
    /// Your own photo, kept by you: its caption is your own words.
    var mine = false
    /// The album it lies in, so it can lift out of its place; and what a
    /// tap on the print does (build 39: open it to the whole screen).
    var album: Namespace.ID?
    var onOpen: (() -> Void)?

    /// Held gathers every circle. Which one a memory is from is worth saying
    /// once there's more than one to tell apart.
    private var showsCircle: Bool {
        state.circles.count > 1 || Set(state.threads.flatMap(\.memories).compactMap(\.circleName)).count > 1
    }

    private var heldTrace: String? {
        guard let taken = memory.takenAt else { return nil }
        return "Held · \(taken.formatted(date: .abbreviated, time: .omitted))"
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
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let date = memory.date {
                    Text(date).font(.caption).foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 92)
            .overlay {
                RoundedRectangle(cornerRadius: PhotoCut.corner, style: .continuous)
                    .strokeBorder(DarkRoom.line(0.14), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
            .rotationEffect(.degrees(tilt * 0.5))
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                if let urls = memory.urls, let url = state.api.absoluteURL(urls.image) {
                  Button { onOpen?() } label: {
                    Color.clear
                        .frame(height: density.heldPhotoHeight)
                        .overlay {
                            SignedImage(url: url) { image in
                                image.resizable().aspectRatio(contentMode: .fill)
                            } placeholder: {
                                Shimmer()
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
                        .clipShape(RoundedRectangle(cornerRadius: PhotoCut.corner, style: .continuous))
                        .heroSource(memory.id, in: album)
                        .asPrint(tilt: tilt)
                        .padding(.vertical, 4)
                  }
                  // Gives a little under the thumb, then lifts (build 39).
                  .buttonStyle(PressedPrint())
                  .disabled(onOpen == nil)
                  .accessibilityLabel(memory.caption.flatMap { $0.isEmpty ? nil : "Held photo: \($0)" } ?? "Held photo")
                  .accessibilityHint("Opens it large")
                }
                // Beneath the photo: what it was, then where and when, small.
                VStack(alignment: .leading, spacing: 3) {
                    if let caption = memory.caption, !caption.isEmpty {
                        Text(caption)
                            .font(mine ? .hand(18, relativeTo: .body) : .body)
                    } else if let takenAt = memory.takenAt {
                        Text(takenAt, style: .date)
                            .font(.body)
                    }
                    if let line = whereAndWhen {
                        Text(line).quietLabel()
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
            }
        }
    }
}

/// Which circle a held memory is from: its name, small, after a dotted
/// circle.
struct CircleTag: View {
    let name: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "circle.dotted")
            Text(name)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("From \(name)")
    }
}
