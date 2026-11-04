import SwiftUI

// The circle's board (build 27): everyone can pin one sticky note a day, each
// at its own slight angle, held by a strip of tape and tinted with its
// author's own tone. Since the polish pass (build 28) they're a row you
// swipe through, one note in view with the edge of the next, because the
// corkboard of overlapping notes took too much of a phone's screen. You can
// change or take down only your own. They clear at the end of their
// author's day. Not a chat: no replies and no reactions.

/// What a note's paper looks like: a pale paper with its author's tone in it
/// (about 15%), so everyone's note is a slightly different pastel. In the
/// dark the paper is lamplit, as the sticky note always was, never black: a
/// note is paper on the board, and the ink stays dark on it.
enum NotePaper {
    static func base(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.80, green: 0.77, blue: 0.70) : Color(red: 1.0, green: 0.985, blue: 0.94)
    }

    /// The blank note that asks for yours: sticky-note yellow.
    static func blank(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.80, green: 0.72, blue: 0.40) : Color(red: 0.99, green: 0.93, blue: 0.62)
    }

    static let ink = Color(red: 0.22, green: 0.18, blue: 0.10)
    static let tint = 0.15

    /// Between -3° and +3°, and the same every time it's drawn: from the
    /// note's own id.
    static func tilt(_ key: String) -> Double {
        let seed = key.unicodeScalars.reduce(UInt32(11)) { $0 &* 33 &+ $1.value }
        return (Double(seed % 61) - 30) / 10
    }
}

/// One sticky note: the words in a hand, "— Ruby" under them, a strip of
/// tape across the top. When its words change while it's on screen it lifts
/// off the board and settles back (not on first load, not under Reduce
/// Motion).
struct StickyNote: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let note: CommunityNote
    let tone: Color
    /// How many lines to show; all of them unless said.
    var lines: Int?
    @State private var lifts = 0
    @State private var settled = false

    private var tilt: Double { NotePaper.tilt(note.id ?? note.text) }

    /// Signed the way a note is, with a first name.
    private var signature: String {
        let full = note.author.displayName
        return full.split(separator: " ").first.map(String.init) ?? full
    }

    var body: some View {
        let tilt = self.tilt
        VStack(alignment: .leading, spacing: 8) {
            Text(note.text)
                .font(.hand(18, bold: true, relativeTo: .body))
                .lineLimit(lines)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Text("— \(signature)")
                .font(.hand(14, relativeTo: .footnote))
                .opacity(0.7)
                .lineLimit(1)
        }
        .foregroundStyle(NotePaper.ink)
        .padding(.horizontal, 16)
        .padding(.top, 22)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, minHeight: 96, maxHeight: .infinity, alignment: .topLeading)
        .background { StickyPaper(color: NotePaper.base(colorScheme), tone: tone) }
        .overlay(alignment: .top) { Tape().offset(y: -10) }
        .keyframeAnimator(initialValue: 0.0, trigger: lifts) { content, lift in
            content
                .scaleEffect(1 + 0.035 * lift, anchor: .top)
                .rotationEffect(.degrees(tilt * (1 - 0.6 * lift)), anchor: .top)
                .offset(y: -5 * lift)
        } keyframes: { _ in
            // Up off the board, then back down with a little give.
            KeyframeTrack {
                CubicKeyframe(1, duration: 0.22)
                SpringKeyframe(0, duration: 0.7, spring: .init(duration: 0.6, bounce: 0.35))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Note from \(note.author.displayName): \(note.text)")
        .onChange(of: note.text) { _, _ in
            if settled, !reduceMotion { lifts += 1 }
        }
        .task {
            try? await Task.sleep(for: .seconds(1.5))
            settled = true
        }
    }
}

/// A note's paper: its color with its author's tone in it, lighter where the
/// light falls and deeper at the curl, with a grain and a soft shadow.
private struct StickyPaper: View {
    @Environment(\.colorScheme) private var colorScheme
    let color: Color
    var tone: Color = .clear

    var body: some View {
        Rectangle()
            .fill(color)
            .overlay(Rectangle().fill(tone.opacity(NotePaper.tint)))
            .overlay(
                LinearGradient(
                    colors: [.white.opacity(0.10), .clear, .black.opacity(0.05)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            )
            .overlay(PaperGrainView(strength: 0.55).clipped())
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.5 : 0.16), radius: 6, x: 1, y: 3)
    }
}

/// The blank note that stands in for yours until you write it: "Leave a
/// note for your circle…", on sticky-note yellow.
private struct BlankNote: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text("Leave a note for your circle…")
            .font(.hand(18, relativeTo: .body))
            .foregroundStyle(NotePaper.ink)
            .opacity(0.55)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16)
            .padding(.top, 22)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, minHeight: 96, maxHeight: .infinity, alignment: .topLeading)
            .background { StickyPaper(color: NotePaper.blank(colorScheme)) }
            .overlay(alignment: .top) { Tape().offset(y: -10) }
            .rotationEffect(.degrees(-1.6))
            .accessibilityLabel("Leave a note for your circle")
    }
}

/// The board at the top of Today: one note in view at a time, full width,
/// with the edge of the next showing on the right to say there's more, and
/// a quiet row of dots beneath. Swipe through them. Yours comes first, or,
/// until it's written, the blank one asking for it; then everyone else's,
/// newest first. A tap on yours (or the blank) writes; anyone else's is
/// there to read, and a long press reports it. With one note alone there's
/// nothing to swipe: no peek and no dots.
struct NoteBoard: View {
    @Environment(AppState.self) private var state
    @AppStorage("stanley.atmosphere") private var raw = "auto"
    let onWrite: () -> Void
    @State private var current: String?

    /// How much of the next note shows at the right edge.
    private static let peek: CGFloat = 20
    private static let gap: CGFloat = 12
    /// Past this many, the dots slide with the note in view rather than
    /// running off the page.
    private static let maxDots = 9

    private enum Card: Identifiable {
        case blank
        case note(CommunityNote)
        var id: String {
            switch self {
            case .blank: "blank"
            case .note(let note): note.boardId
            }
        }
    }

    private var cards: [Card] {
        let others = state.notes.filter { !state.isMine($0) }.map(Card.note)
        return [state.myNote.map(Card.note) ?? .blank] + others
    }

    var body: some View {
        let cards = self.cards
        let many = cards.count > 1
        VStack(spacing: Spacing.tight) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: Self.gap) {
                    ForEach(cards) { card in
                        view(card)
                            .containerRelativeFrame(.horizontal) { length, _ in
                                many ? length - Self.peek - Self.gap : length
                            }
                            .id(card.id)
                    }
                }
                // Every note in the row as tall as the tallest, so they line
                // up. Room above for the tape, and below for the shadow.
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
                .padding(.bottom, 6)
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $current)
            .scrollClipDisabled()
            .scrollDisabled(!many)
            if many {
                dots(cards)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("The circle's notes")
    }

    @ViewBuilder
    private func view(_ card: Card) -> some View {
        switch card {
        case .blank:
            Button(action: onWrite) { BlankNote() }
                .buttonStyle(.plain)
                .accessibilityHint("Write your note for the circle")
        case .note(let note) where state.isMine(note):
            Button(action: onWrite) { StickyNote(note: note, tone: state.noteTone(note)) }
                .buttonStyle(.plain)
                .accessibilityHint("Change or take down your note")
        case .note(let note):
            StickyNote(note: note, tone: state.noteTone(note))
                .noteMenu(note)
        }
    }

    /// Where you are in the row, the way a page control says it: the one in
    /// view in the atmosphere's accent, the rest faint. Past nine they slide
    /// with you, the ones at the window's edges smaller.
    private func dots(_ cards: [Card]) -> some View {
        let accent = Atmosphere.resolve(raw).palette.accent
        let index = cards.firstIndex { $0.id == current } ?? 0
        let first = max(0, min(index - Self.maxDots / 2, cards.count - Self.maxDots))
        let shown = Array(cards.indices.dropFirst(first).prefix(Self.maxDots))
        return HStack(spacing: 6) {
            ForEach(shown, id: \.self) { i in
                let edge = cards.count > Self.maxDots
                    && ((i == shown.first && i > 0) || (i == shown.last && i < cards.count - 1))
                Circle()
                    .fill(accent.opacity(i == index ? 0.9 : 0.25))
                    .frame(width: edge ? 4 : 6, height: edge ? 4 : 6)
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.easeInOut(duration: 0.2), value: index)
        .accessibilityHidden(true)
    }
}

extension AppState {
    /// A note's tint: its author's own tone in this circle, as their name
    /// is when a story mentions them.
    func noteTone(_ note: CommunityNote) -> Color {
        guard let id = note.author.id, let circle else { return .clear }
        return MentionInk.color(MentionTones.index(for: id, in: circle))
    }
}

extension View {
    /// A note's long-press menu: Report, on anyone's note but your own.
    func noteMenu(_ note: CommunityNote) -> some View { modifier(NoteMenu(note: note)) }
}

private struct NoteMenu: ViewModifier {
    @Environment(AppState.self) private var state
    let note: CommunityNote
    @State private var reporting = false

    func body(content: Content) -> some View {
        if state.isMine(note) || note.id == nil {
            content
        } else {
            content
                .contextMenu {
                    Button { reporting = true } label: {
                        Label("Report Note", systemImage: "flag")
                    }
                }
                .sheet(isPresented: $reporting) {
                    ReportSheet(target: .note(note))
                }
        }
    }
}

/// Writing your note: one a day, yours alone to change or take down.
struct NoteEditor: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var confirmTakeDown = false
    @State private var saving = false
    @FocusState private var writing: Bool

    static let limit = 200

    private var editing: Bool { state.myNote != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Leave a note for your circle…", text: $text, axis: .vertical)
                        .lineLimit(2...6)
                        .focused($writing)
                        .onChange(of: text) { _, new in
                            let clamped = WritingLimit.clamp(new, Self.limit)
                            if clamped != new { text = clamped }
                        }
                } footer: {
                    Text("Everyone in the circle sees your note on the board, and only you can change it or take it down. It clears at the end of your day. It's a sticky note, not a chat.")
                }
                if editing {
                    Section {
                        Button("Take Down Note", role: .destructive) { confirmTakeDown = true }
                            .destructiveInk()
                    }
                }
            }
            .atmosphereRows()
            .atmosphereWash()
            .navigationTitle(editing ? "Your note" : "A note for today")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Pinning…" : editing ? "Save" : "Post") {
                        let line = text.trimmedWords
                        // Sealed when it's on the board, not before: a note
                        // that didn't save gets no tap. The sheet stays until
                        // the server has it (the HCI audit, build 32): it used
                        // to close at once, and a note that failed took its
                        // words with it, where a story's come back.
                        saving = true
                        Task {
                            let pinned = await state.setNote(line)
                            saving = false
                            if pinned {
                                Haptics.noteSealed()
                                dismiss()
                            }
                        }
                    }
                    .disabled(saving || !text.hasWords || text.trimmedWords == state.myNote?.text)
                }
            }
            .interactiveDismissDisabled(saving || (text.hasWords && text.trimmedWords != state.myNote?.text))
            .alert("Take down your note?", isPresented: $confirmTakeDown) {
                Button("Take Down", role: .destructive) {
                    Task { await state.deleteNote() }
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("It comes off the board for everyone. You can write another today.")
            }
            .onAppear {
                text = state.myNote?.text ?? ""
                // Opened to write, so the keyboard is up (the HCI audit,
                // build 32): it took a second tap on the field before.
                writing = true
            }
        }
    }
}

/// A strip of tape over the top edge of a note, holding it to the page
/// (build 22; a red pushpin from build 19 to 21): translucent cream, so the
/// note's paper and the page both show through, a little crooked, catching
/// the light along its length, with the faintest shadow at its edges.
struct Tape: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 1.5, style: .continuous)
        shape
            .fill(Color(red: 0.98, green: 0.96, blue: 0.90).opacity(colorScheme == .dark ? 0.55 : 0.62))
            .overlay(
                LinearGradient(
                    colors: [.white.opacity(0.35), .clear, .white.opacity(0.15)],
                    startPoint: .leading, endPoint: .trailing
                )
                .clipShape(shape)
            )
            .overlay(shape.strokeBorder(.white.opacity(0.4), lineWidth: 0.5))
            .frame(width: 66, height: 22)
            .shadow(color: .black.opacity(0.14), radius: 2, y: 1)
            .rotationEffect(.degrees(-6))
            .accessibilityHidden(true)
    }
}
