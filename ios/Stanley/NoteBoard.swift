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
            // Two shadows, the way paper sits on a page (build 39): a tight
            // one where it touches, and a soft one where its edge lifts.
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.12), radius: 1.5, x: 0, y: 1)
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.5 : 0.17), radius: 8, x: 1, y: 5)
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
///
/// **Writing is on the note itself** (build 39; it was a sheet with a form's
/// text field). A tap on yours, or on the blank one, and the note straightens
/// and takes a cursor: the words go down in the hand, on its paper, under
/// its tape, with Cancel and Done written along its foot. Done pins it once
/// the server has it; a note that didn't pin stays open with its words.
/// Clearing your note's words and tapping Take Down takes it off the board
/// (asked first), and so does a long press on it.
struct NoteBoard: View {
    @Environment(AppState.self) private var state
    @AppStorage("stanley.atmosphere") private var raw = "auto"
    @State private var current: String?
    /// The words being written on your note; nil when nobody's writing.
    @State private var draft: String?
    @State private var saving = false
    @State private var confirmTakeDown = false
    @FocusState private var typing: Bool

    static let limit = 200

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
                .padding(.bottom, 12)
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $current)
            .scrollClipDisabled()
            // Held still while you write, so the note can't slide away
            // from under the cursor.
            .scrollDisabled(!many || draft != nil)
            if many {
                dots(cards)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("The circle's notes")
        .alert("Take down your note?", isPresented: $confirmTakeDown) {
            Button("Take Down", role: .destructive) {
                Task { await state.deleteNote() }
                finish()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It comes off the board for everyone. You can write another today.")
        }
        // Another circle's board has its own note: nothing half-written
        // follows you there.
        .onChange(of: state.circle?.id) { finish() }
    }

    private func begin() {
        guard draft == nil else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            draft = state.myNote?.text ?? ""
            current = cards.first?.id
        }
    }

    private func finish() {
        typing = false
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { draft = nil }
    }

    /// Done: pin what's written. The note stays open until the server has
    /// it, so words that didn't go through are still there to send again.
    private func done() {
        guard let draft, !saving else { return }
        let words = draft.trimmedWords
        if words.isEmpty {
            // Nothing on it: taking your note down, or never mind.
            if state.myNote != nil { confirmTakeDown = true } else { finish() }
            return
        }
        if words == state.myNote?.text {
            finish()
            return
        }
        saving = true
        Task {
            let pinned = await state.setNote(words)
            saving = false
            if pinned {
                Haptics.noteSealed()
                finish()
            }
        }
    }

    @ViewBuilder
    private func view(_ card: Card) -> some View {
        switch card {
        case .blank where draft != nil:
            writingNote(mine: nil)
        case .note(let note) where state.isMine(note) && draft != nil:
            writingNote(mine: note)
        case .blank:
            Button(action: begin) { BlankNote() }
                .buttonStyle(.plain)
                .accessibilityHint("Write your note for the circle")
        case .note(let note) where state.isMine(note):
            Button(action: begin) { StickyNote(note: note, tone: state.noteTone(note)) }
                .buttonStyle(.plain)
                .accessibilityHint("Change or take down your note")
                .contextMenu {
                    Button(action: begin) { Label("Edit Note", systemImage: "pencil") }
                    Button(role: .destructive) { confirmTakeDown = true } label: {
                        Label("Take Down Note", systemImage: "trash")
                    }
                }
        case .note(let note):
            StickyNote(note: note, tone: state.noteTone(note))
                .noteMenu(note)
        }
    }

    /// Your note while you write on it: the same paper it has on the board
    /// (the blank one's yellow until there's a note), straight, with the
    /// cursor in it.
    private func writingNote(mine: CommunityNote?) -> some View {
        WritingNote(
            // Only while writing: a field on its way out writes its last
            // (empty) text back, which mustn't open the note again.
            text: Binding(
                get: { draft ?? "" },
                set: { if draft != nil { draft = WritingLimit.clamp($0, Self.limit) } }
            ),
            typing: $typing,
            tone: mine.map { state.noteTone($0) },
            takesDown: mine != nil && (draft ?? "").trimmedWords.isEmpty,
            saving: saving,
            onCancel: finish,
            onDone: done
        )
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

/// Your note, being written: sticky paper, tape and all, with the words
/// going down in the hand where they'll stay. Cancel and Done are written
/// along its foot, where a signature goes; Done reads Take Down once your
/// note's words are all rubbed out.
private struct WritingNote: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var text: String
    var typing: FocusState<Bool>.Binding
    /// The note's own tint; nil for one not on the board yet, which is
    /// still the blank's yellow.
    let tone: Color?
    let takesDown: Bool
    let saving: Bool
    let onCancel: () -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(
                "", text: $text,
                prompt: Text("Leave a note for your circle…").foregroundColor(NotePaper.ink.opacity(0.45)),
                axis: .vertical
            )
            .font(.hand(18, bold: true, relativeTo: .body))
            .foregroundStyle(NotePaper.ink)
            .tint(NotePaper.ink)
            .textFieldStyle(.plain)
            .lineLimit(2...7)
            .focused(typing)
            .accessibilityLabel("Your note")
            Spacer(minLength: 0)
            HStack(spacing: 18) {
                Button("Cancel", action: onCancel)
                    .font(.hand(15, relativeTo: .footnote))
                    .opacity(0.7)
                    .disabled(saving)
                Spacer(minLength: 0)
                Button(saving ? "Pinning…" : takesDown ? "Take Down" : "Done", action: onDone)
                    .font(.hand(16, bold: true, relativeTo: .footnote))
                    .disabled(saving)
            }
            .buttonStyle(.plain)
            .foregroundStyle(NotePaper.ink)
            // A thumb's height each, though they're written small.
            .frame(minHeight: 30)
        }
        .padding(.horizontal, 16)
        .padding(.top, 22)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, minHeight: 112, maxHeight: .infinity, alignment: .topLeading)
        .background {
            StickyPaper(color: tone == nil ? NotePaper.blank(colorScheme) : NotePaper.base(colorScheme), tone: tone ?? .clear)
        }
        .overlay(alignment: .top) { Tape().offset(y: -10) }
        // Lifted a little toward you while you write.
        .scaleEffect(1.01, anchor: .top)
        .contentShape(Rectangle())
        .onTapGesture { typing.wrappedValue = true }
        .task {
            // After the note is on the page, or the cursor doesn't take.
            try? await Task.sleep(for: .milliseconds(60))
            typing.wrappedValue = true
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
