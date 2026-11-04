import SwiftUI

// The circle's board (build 27): everyone can pin one sticky note a day, and
// the notes lie on the first page of Today the way notes lie on a corkboard,
// overlapping a little, each at its own slight angle, each held by a strip
// of tape and tinted with its author's own tone. You can change or take down
// only your own. They clear at the end of their author's day. Not a chat:
// no replies, no reactions, and never how many notes there are.

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
    /// How many lines the board shows; the sheet shows them all.
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
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
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
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
            .background { StickyPaper(color: NotePaper.blank(colorScheme)) }
            .overlay(alignment: .top) { Tape().offset(y: -10) }
            .rotationEffect(.degrees(-1.6))
            .accessibilityLabel("Leave a note for your circle")
    }
}

/// The edge of a note further down the pile: paper and tape, no words.
private struct PeekNote: View {
    @Environment(\.colorScheme) private var colorScheme
    let tone: Color

    var body: some View {
        StickyPaper(color: NotePaper.base(colorScheme), tone: tone)
            .accessibilityHidden(true)
    }
}

/// Where each thing on the board lies. Your note (or the blank one asking
/// for it) at the front left, the newest two of everyone else's beside it
/// and below, and the next two peeking out from underneath. Notes overlap
/// only where they're blank: the two side by side share a few points of
/// margin, and the one below is pinned just under them, its tape across
/// their bottom margins, so no word or name is ever covered.
private struct BoardLayout: Layout {
    enum Slot: Int { case peekA, peekB, a, b, c }
    struct SlotKey: LayoutValueKey { static let defaultValue: Slot = .a }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 360
        let bottom = frames(width: width, subviews: subviews).values.map(\.maxY).max() ?? 0
        return CGSize(width: width, height: bottom + 6)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let placed = frames(width: bounds.width, subviews: subviews)
        for index in subviews.indices {
            guard let frame = placed[index] else { continue }
            subviews[index].place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    private func frames(width: CGFloat, subviews: Subviews) -> [Int: CGRect] {
        let slots = subviews.indices.map { ($0, subviews[$0][SlotKey.self]) }
        let notes = slots.filter { $0.1.rawValue >= Slot.a.rawValue }.count
        // Two side by side meet with a strip of paper in common, narrower
        // than a note's own margin even when tilted; one alone is a single
        // square-ish sticky.
        let w = notes <= 1 ? min(width * 0.64, 280) : width * 0.5
        func height(_ index: Int) -> CGFloat {
            subviews[index].sizeThatFits(ProposedViewSize(width: w, height: nil)).height
        }
        var out: [Int: CGRect] = [:]
        // The tape rides 10pt above each note, so the board starts lower.
        if let a = slots.first(where: { $0.1 == .a })?.0 {
            out[a] = CGRect(x: 4, y: 14, width: w, height: height(a))
        }
        if let b = slots.first(where: { $0.1 == .b })?.0 {
            out[b] = CGRect(x: width - w - 2, y: 10, width: w, height: height(b))
        }
        if let c = slots.first(where: { $0.1 == .c })?.0 {
            let above = [slots.first { $0.1 == .a }?.0, slots.first { $0.1 == .b }?.0]
                .compactMap { $0.flatMap { out[$0]?.maxY } }.max() ?? 14
            out[c] = CGRect(x: (width - w) / 2 + 8, y: above + 4, width: w, height: height(c))
        }
        // Further down the pile, behind the front two, an edge of each.
        let front = out[slots.first { $0.1 == .a }?.0 ?? -1] ?? CGRect(x: 4, y: 14, width: w, height: 104)
        let side = out[slots.first { $0.1 == .b }?.0 ?? -1] ?? front
        if let p = slots.first(where: { $0.1 == .peekA })?.0 {
            out[p] = front.offsetBy(dx: 10, dy: -7)
        }
        if let p = slots.first(where: { $0.1 == .peekB })?.0 {
            out[p] = side.offsetBy(dx: -12, dy: 9)
        }
        return out
    }
}

/// The board at the top of Today: at most three notes in view, with the edges
/// of the next ones peeking out beneath, and "See all notes" when there are
/// more than fit. Until you've written yours, the board asks for it, and a
/// tap anywhere on it writes; after, a tap on yours changes it, and a tap on
/// anyone else's opens the whole board to read.
struct NoteBoard: View {
    @Environment(AppState.self) private var state
    let onWrite: () -> Void
    let onSeeAll: () -> Void

    private var mine: CommunityNote? { state.myNote }
    /// Everyone else's, newest first, as the server sent them.
    private var others: [CommunityNote] { state.notes.filter { !state.isMine($0) } }

    var body: some View {
        let shown = Array(others.prefix(2))
        let peeking = Array(others.dropFirst(2).prefix(2))
        VStack(alignment: .leading, spacing: 10) {
            BoardLayout {
                ForEach(Array(peeking.enumerated()), id: \.offset) { index, note in
                    PeekNote(tone: state.noteTone(note))
                        .rotationEffect(.degrees(NotePaper.tilt((note.id ?? note.text) + "peek")))
                        .layoutValue(key: BoardLayout.SlotKey.self, value: index == 0 ? .peekA : .peekB)
                }
                // Back to front: the one beside, yours, then the one below.
                if let side = shown.first {
                    other(side)
                        .layoutValue(key: BoardLayout.SlotKey.self, value: .b)
                }
                Group {
                    if let mine {
                        Button(action: onWrite) {
                            StickyNote(note: mine, tone: state.noteTone(mine), lines: 3)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Change or take down your note")
                    } else {
                        BlankNote()
                    }
                }
                .layoutValue(key: BoardLayout.SlotKey.self, value: .a)
                if shown.count > 1 {
                    other(shown[1])
                        .layoutValue(key: BoardLayout.SlotKey.self, value: .c)
                }
            }
            // Until yours is written, the whole board is the way to write it.
            .contentShape(Rectangle())
            .onTapGesture { if mine == nil { onWrite() } }
            if others.count > shown.count {
                Button(action: onSeeAll) {
                    HStack(spacing: 6) {
                        Text("See all notes")
                            .font(.hand(17, bold: true, relativeTo: .callout))
                        Image(systemName: "arrow.right")
                            .font(.caption.weight(.semibold))
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .padding(.leading, 6)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("The circle's notes")
    }

    /// Someone else's note on the board: there to read, and to report.
    @ViewBuilder
    private func other(_ note: CommunityNote) -> some View {
        let sticky = StickyNote(note: note, tone: state.noteTone(note), lines: 3)
            .noteMenu(note)
        if mine == nil {
            sticky
        } else {
            Button(action: onSeeAll) { sticky }
                .buttonStyle(.plain)
                .accessibilityHint("Shows every note on the board")
        }
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

/// Every note on the board today, laid out to read in full, two to a row,
/// each at its own angle. Yours opens to change.
struct AllNotesSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false

    private let columns = [GridItem(.flexible(), spacing: 18), GridItem(.flexible(), spacing: 18)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    Text(state.circle?.name ?? "Your circle")
                        .font(.hand(30, bold: true, relativeTo: .largeTitle))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text("Today's notes · they clear at the end of the day")
                        .smallCaps()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 22)
                LazyVGrid(columns: columns, alignment: .leading, spacing: 26) {
                    if state.myNote == nil {
                        Button { editing = true } label: { BlankNote() }
                            .buttonStyle(.plain)
                    }
                    ForEach(state.notes, id: \.boardId) { note in
                        if state.isMine(note) {
                            Button { editing = true } label: {
                                StickyNote(note: note, tone: state.noteTone(note))
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Change or take down your note")
                        } else {
                            StickyNote(note: note, tone: state.noteTone(note))
                                .noteMenu(note)
                        }
                    }
                }
                .padding(.top, 10)
            }
            .contentMargins(20, for: .scrollContent)
            .atmosphereWash()
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .sheet(isPresented: $editing) { NoteEditor() }
            .task { await state.loadNotes() }
        }
    }
}

/// Writing your note: one a day, yours alone to change or take down.
struct NoteEditor: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var confirmTakeDown = false

    static let limit = 200

    private var editing: Bool { state.myNote != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Leave a note for your circle…", text: $text, axis: .vertical)
                        .lineLimit(2...6)
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
                    Button(editing ? "Save" : "Post") {
                        let line = text.trimmedWords
                        // Sealed when it's on the board, not before: a note
                        // that didn't save gets no tap.
                        Task { if await state.setNote(line) { Haptics.noteSealed() } }
                        dismiss()
                    }
                    .disabled(!text.hasWords || text.trimmedWords == state.myNote?.text)
                }
            }
            .alert("Take down your note?", isPresented: $confirmTakeDown) {
                Button("Take Down", role: .destructive) {
                    Task { await state.deleteNote() }
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("It comes off the board for everyone. You can write another today.")
            }
            .onAppear { text = state.myNote?.text ?? "" }
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
