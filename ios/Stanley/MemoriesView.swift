import SwiftUI

/// The Journal tab (build 46): the journal's pages, and nothing in front of
/// them. It lands on today's page; everything before it is a swipe to the
/// right away (`BookView`). Build 45 opened to a cover, with Letters and
/// Prompts as cards under it; they're marks at the foot of the page
/// now (build 49; at its head in 48, paper tabs at its edge in 46),
/// and the journal's name is in Settings. It was a list until build 44
/// ("Held" before that); the internal names are unchanged.
struct MemoriesView: View {
    var body: some View {
        // A navigation stack for the toolbar's sake (the Duo brief): the
        // tab's Letters, Prompts and the week are the system's toolbar
        // items. The tab bar stays outside, as the tabs do.
        NavigationStack {
            BookView()
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}

/// Letters, behind the envelope at the foot of the journal's page (a sheet since
/// build 46): the ones written to you and still sealed, the ones you've
/// opened (each is a page of the journal, and a tap turns to it), and the
/// way to write one to someone.
struct LettersPage: View {
    @Environment(AppState.self) private var state
    @State private var reading: Letter?
    /// A letter a notice was about (build 59): once Letters has it, one
    /// whose day has come opens to be read; one still sealed is there with
    /// the others, waiting.
    var asked: String? = nil
    /// An opened letter was picked: turn the journal to its page.
    var onRead: (Letter) -> Void = { _ in }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.chapter) {
                LettersOnHeld { reading = $0 }
                LettersOpened(onRead: onRead)
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
        .task {
            await state.refreshLetters()
            // Letters written to you, come upon: the moment to offer to
            // notify you of the next (build 61), if it's the first.
            let mine = state.lettersReceived.sealed + state.lettersReceived.opened
            state.cameUponWrittenToYou(mine.map(\.id))
            guard let asked else { return }
            if let ready = state.lettersReceived.sealed.first(where: { $0.id == asked && $0.deliverable == true }) {
                reading = ready
            } else if let opened = state.lettersReceived.opened.first(where: { $0.id == asked }) {
                onRead(opened)
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
