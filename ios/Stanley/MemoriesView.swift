import SwiftUI

/// The Journal tab (build 46): the journal's pages, and nothing in front of
/// them. It lands on today's page; everything before it is a swipe to the
/// right away (`BookView`). Build 45 opened to a cover, with Letters and
/// Prompts as cards under it; they're marks on the bar at the head of the
/// page now (build 48; paper tabs at its edge in build 46),
/// and the journal's name is in Settings. It was a list until build 44
/// ("Held" before that); the internal names are unchanged.
struct MemoriesView: View {
    var body: some View {
        BookView()
    }
}

/// Letters, behind the envelope on the journal's bar (a sheet since
/// build 46): the ones written to you and still sealed, the ones you've
/// opened (each is a page of the journal, and a tap turns to it), and the
/// way to write one to someone.
struct LettersPage: View {
    @Environment(AppState.self) private var state
    @State private var reading: Letter?
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
        .task { await state.refreshLetters() }
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
