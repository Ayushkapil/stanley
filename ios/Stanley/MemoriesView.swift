import SwiftUI

/// The Journal tab (build 45): a book. It opens to the cover, not a list;
/// a tap opens the book (`BookView`, over the whole app), and inside are
/// the pages you've written, the photos you've kept, the letters opened
/// and your weekly reflections, in the order they happened. Under the
/// cover are the things that aren't pages yet, or aren't only yours:
/// letters still sealed and the way to write one, and the circle's
/// questions. It was a list of all of it until build 44 ("Held" before
/// that); the internal names are unchanged.
struct MemoriesView: View {
    @Environment(AppState.self) private var state
    @Environment(\.horizontalSizeClass) private var hSizeClass
    private var density: Density { Density(hSizeClass) }
    @State private var readingQuestions = false
    @State private var readingLetters = false
    @State private var writing: WritingTarget?
    @State private var renaming = false
    @State private var newTitle = ""
    /// Where the cover lies on the screen, for the book to grow from.
    @State private var coverFrame = CGRect.zero
    /// How far the page has been pulled down past its top.
    @State private var pull: CGFloat = 0

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        head
                            .id("masthead")
                        cover
                            .padding(.top, Spacing.section)
                        sundayCard
                            .padding(.top, Spacing.chapter)
                        shelf
                            .padding(.top, Spacing.chapter)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, Spacing.chapter)
                    .readableWidth(density)
                }
                .pullToWrite(enabled: state.journalWritable, depth: $pull) { writing = .today }
                // A tap on the Journal tab: back to the cover, and
                // everything fetched again. Both at once: the page is
                // about a screen tall, so it's nearly always at its top
                // already (and a page that never scrolls never says so,
                // which is what `onTabTap` waits to hear).
                .onChange(of: state.tabTaps.held) {
                    withAnimation(.easeInOut(duration: 0.28)) { proxy.scrollTo("masthead", anchor: .top) }
                    Haptics.refreshed()
                    Task { await load() }
                }
                .journalPage()
                .navigationTitle("Journal")
                .navigationDestination(isPresented: $readingQuestions) { CircleJournalView() }
                .navigationDestination(isPresented: $readingLetters) { LettersPage() }
                .fullScreenCover(item: $writing) { BookWritingView(target: $0) }
                .alert("Name your journal", isPresented: $renaming) {
                    TextField(BookCover.defaultTitle, text: $newTitle)
                    Button("Save") {
                        let title = String(newTitle.trimmingCharacters(in: .whitespacesAndNewlines).prefix(BookCover.titleLimit))
                        Task { await state.renameJournal(title) }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("It's written on the cover. Leave it empty for “\(BookCover.defaultTitle)”.")
                }
                .task { await load() }
                .onChange(of: state.reloads) { Task { await load() } }
            }
        }
    }

    private func load() async {
        await state.loadBook()
        await state.loadThisWeek()
    }

    /// The day, small, and the way to write: where Today has its circle's
    /// name and its "+".
    private var head: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center) {
                Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day().year()))
                    .smallCaps()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 12)
                if state.journalWritable {
                    NewPageButton { writing = .today }
                } else {
                    Color.clear.frame(width: 44, height: 44)
                }
            }
            OfflineLine()
        }
        .padding(.top, 8)
        // Pulled down far enough, the page says what letting it go on does.
        .overlay(alignment: .top) {
            if state.journalWritable {
                Text("Pull to write today's page")
                    .quietLabel()
                    .opacity(min(1, max(0, (pull - 16) / 50)))
                    .offset(y: -30)
                    .accessibilityHidden(true)
            }
        }
    }

    /// The book, shut. A tap opens it; a long press on its name renames it.
    private var cover: some View {
        BookCoverFace(
            title: state.journalTitle, name: state.profile?.displayName, span: BookBuilder.span(state),
            onRename: state.journalWritable ? { rename() } : nil
        )
        .aspectRatio(1 / BookCover.shape, contentMode: .fit)
        .frame(maxWidth: 300)
        .padding(.horizontal, 28)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { coverFrame = $0 }
        // While the book is open the cover is up there, not lying here.
        .opacity(state.book?.cover == nil ? 1 : 0)
        .contentShape(Rectangle())
        .onTapGesture { state.book = BookOpening(start: .today, cover: coverFrame) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(state.journalTitle ?? BookCover.defaultTitle), your journal")
        .accessibilityHint("Opens the book")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Rename") { rename() }
    }

    private func rename() {
        newTitle = state.journalTitle ?? ""
        renaming = true
    }

    /// Sunday evening: "How was your week?", until midnight or until it's
    /// written. What's written becomes a page of the book.
    @ViewBuilder
    private var sundayCard: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            if ReflectionWindow.isOpen(context.date), let week = state.thisWeek, week.reflection == nil {
                ReflectionCard(week: week)
            }
        }
    }

    /// Beside the book: what isn't a page of it. Letters still sealed and
    /// the way to write one; the circle's questions, which are the circle's.
    private var shelf: some View {
        HStack(alignment: .top, spacing: 12) {
            ShelfCard(symbol: "envelope", title: "Letters", line: lettersLine) { readingLetters = true }
            if state.circle != nil {
                ShelfCard(symbol: "text.bubble", title: "Prompts", line: promptsLine) { readingQuestions = true }
            }
        }
    }

    /// In words, never how many.
    private var lettersLine: String {
        let sealed = state.lettersReceived.sealed
        if sealed.contains(where: { $0.deliverable == true }) { return "A letter is ready to open" }
        if !sealed.isEmpty { return "Sealed, waiting for their day" }
        return "Write to someone"
    }

    private var promptsLine: String {
        state.question?.prompt.text ?? "Your circle's questions"
    }
}

/// The "+" at the head of the Journal tab, where Today has its own: a new
/// page, today's.
private struct NewPageButton: View {
    @AppStorage("stanley.atmosphere") private var raw = "auto"
    @ScaledMetric(relativeTo: .title2) private var glyph: CGFloat = 22
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: glyph, weight: .light))
                .foregroundStyle(Atmosphere.resolve(raw).palette.accent)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Write today's page")
    }
}

/// A small card under the cover: a mark, a name, a line.
private struct ShelfCard: View {
    @AppStorage("stanley.atmosphere") private var raw = "auto"
    let symbol: String
    let title: String
    let line: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 19, weight: .light))
                    .foregroundStyle(Atmosphere.resolve(raw).palette.accent)
                    .frame(height: 24)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.system(.body, design: .rounded).weight(.semibold))
                Text(line)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    // Two lines' room either way, so the cards are a pair.
                    .lineLimit(2, reservesSpace: true)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .card(h: 14, v: 14)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// Letters that aren't pages yet: the ones written to you and still
/// sealed, and the way to write one to someone. Once a letter is opened it
/// becomes a page of the book.
struct LettersPage: View {
    @Environment(AppState.self) private var state
    @State private var reading: Letter?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.chapter) {
                LettersOnHeld { reading = $0 }
                LettersOnYou()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, Spacing.section)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .atmosphereWash()
        .navigationTitle("Letters")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $reading) { LetterReaderSheet(letter: $0) }
        .task { await state.refreshLetters() }
    }
}

extension View {
    /// Pulling the page down past its top writes today's page (iOS 18 and
    /// up, where a scroll view says how far it's been pulled; before that
    /// there's the "+").
    @ViewBuilder
    fileprivate func pullToWrite(enabled: Bool, depth: Binding<CGFloat>, write: @escaping () -> Void) -> some View {
        if #available(iOS 18, *) {
            modifier(PullToWrite(enabled: enabled, depth: depth, write: write))
        } else {
            self
        }
    }
}

@available(iOS 18, *)
private struct PullToWrite: ViewModifier {
    let enabled: Bool
    @Binding var depth: CGFloat
    let write: () -> Void
    /// The pull has already opened the page; it has to be let go before it
    /// can again.
    @State private var spent = false
    /// A finger is on the page: a pull, not the bounce after a fling.
    @State private var dragging = false

    func body(content: Content) -> some View {
        content
            .onScrollPhaseChange { _, phase in dragging = phase == .interacting }
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                -(geometry.contentOffset.y + geometry.contentInsets.top)
            } action: { _, pulled in
                depth = max(0, pulled)
                guard enabled else { return }
                if pulled > 88, dragging, !spent {
                    spent = true
                    Haptics.refreshed()
                    write()
                } else if pulled < 6 {
                    spent = false
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
