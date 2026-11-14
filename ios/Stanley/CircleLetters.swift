import SwiftUI

// Letters to the circle (build 42). Once a month each person may write the
// whole circle one letter, unsigned. It's sealed until the month is over
// and then every letter opens together, to be read for seven days and then
// gone, like everything else here.
//
// - In Today, where the week's question sits: an envelope that asks for
//   this month's letter (`LetterWritingCard`), and, for the week after a
//   month ends, one breaking open with last month's inside
//   (`OpenedLettersCard`).
// - Written on a sheet of its own (`LetterWritingSheet`), since a letter is
//   longer than a line and nobody should read it over a shoulder in Today.
// - Read on a sheet too (`OpenedLettersSheet`): each letter an envelope
//   that opens as it's scrolled to, on its own slip of paper, a little
//   crooked, as if a box of notes had been emptied onto a table.
//
// **Nothing here knows who wrote a letter**, because the server never says:
// a letter arrives as its id and its words. The slips' papers and leans
// come from the letter's id, which is random, never from a person, so the
// same person's letters don't look alike from month to month. The one
// thing the app knows is which letter is its own person's, because it
// asked for that one by itself, and it shows that only in that letter's
// long-press menu (take it back, where the others say report).
//
// No counts (not how many wrote, not how many letters), no replies, no
// reactions, no notification.

/// How a month and its days are said.
enum LetterMonth {
    private static let parser: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM"
        return f
    }()

    /// "2026-11" as "November" (with its year once it isn't this one).
    static func name(_ label: String) -> String {
        guard let date = parser.date(from: label) else { return "" }
        return Calendar.current.isDate(date, equalTo: .now, toGranularity: .year)
            ? date.formatted(.dateTime.month(.wide))
            : date.formatted(.dateTime.month(.wide).year())
    }

    /// When a month's letters open, in the reader's own time: "December 1",
    /// or with the hour when it isn't their midnight (someone else in the
    /// circle is further west).
    static func opens(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let day = date.formatted(.dateTime.month(.wide).day())
        if parts.hour == 0 && parts.minute == 0 { return day }
        let time = parts.minute == 0
            ? date.formatted(.dateTime.hour())
            : date.formatted(.dateTime.hour().minute())
        return "\(day) at \(time)"
    }

    /// The last day opened letters can be read: the day before they go.
    static func lastDay(_ fadesAt: Date) -> String {
        fadesAt.addingTimeInterval(-1).formatted(.dateTime.month(.wide).day())
    }

    /// How far a week of reading has faded the ink, 0 to 1, the way a photo
    /// fades in Today: nothing for the first third, then a smooth fall.
    static func fade(from revealedAt: Date, to fadesAt: Date, at now: Date = .now) -> Double {
        let whole = fadesAt.timeIntervalSince(revealedAt)
        guard whole > 0 else { return 0 }
        let progress = min(1, max(0, now.timeIntervalSince(revealedAt) / whole))
        let t = min(1, max(0, (progress - 1.0 / 3.0) / (2.0 / 3.0)))
        return t * t * (3 - 2 * t)
    }
}

/// The papers letters are written on: a handful of barely tinted stocks,
/// chosen by the letter's own id. Not the mention tones, and nothing to do
/// with who wrote it. Lamplit in the dark room, as a sticky note is.
enum CircleLetterPaper {
    private static let stocks: [(Double, Double, Double)] = [
        (1.00, 0.985, 0.94),  // cream
        (0.94, 0.965, 0.99),  // a little blue
        (0.99, 0.945, 0.94),  // a little rose
        (0.945, 0.975, 0.93), // a little green
        (0.965, 0.945, 0.99), // a little lilac
        (0.995, 0.965, 0.86), // butter
        (0.995, 0.945, 0.895), // peach
        (0.955, 0.955, 0.945), // gray
    ]

    static func seed(_ id: String) -> UInt32 {
        id.unicodeScalars.reduce(UInt32(5)) { $0 &* 37 &+ $1.value }
    }

    static func color(_ seed: UInt32, _ scheme: ColorScheme) -> Color {
        let stock = stocks[Int(seed % UInt32(stocks.count))]
        let light = scheme == .dark ? 0.8 : 1.0
        return Color(red: stock.0 * light, green: stock.1 * light, blue: stock.2 * light)
    }

    /// Between about -2.5° and +2.5°, the same every time it's drawn.
    static func tilt(_ seed: UInt32) -> Double {
        (Double((seed >> 3) % 51) - 25) / 10
    }

    /// How far off the middle of the page it landed.
    static func lean(_ seed: UInt32) -> CGFloat {
        CGFloat(Int((seed >> 9) % 5) - 2) * 6
    }
}

// MARK: - The envelope

/// An envelope's flap, as a line from its two top corners to a point: down
/// inside the envelope when it's closed (0), straight up above it when it's
/// open (1), and flat along the top edge on the way.
private struct EnvelopeFlap: Shape {
    var openness: CGFloat

    var animatableData: CGFloat {
        get { openness }
        set { openness = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let tip = rect.minY + rect.height * (0.52 - 0.98 * openness)
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: tip))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path
    }
}

/// The two folds on an envelope's front, from its bottom corners up to the
/// middle.
private struct EnvelopeFolds: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let meet = CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.56)
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: meet)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        return path
    }
}

/// An envelope drawn in pen, the way the app's bookmark is: closed, or with
/// its flap up and a slip of paper rising out of it. `wax` puts a seal on
/// the closed flap, in the atmosphere's accent; it breaks as the flap
/// lifts. Sized by its width; it keeps room above itself for the flap.
struct EnvelopeMark: View {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("stanley.atmosphere") private var raw = "auto"
    /// 0 closed, 1 open.
    var openness: CGFloat = 0
    /// 0 to 1: how far the slip has come out.
    var lifted: CGFloat = 0
    var wax = false

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = width * 0.64
            let dark = DarkRoom.isDark(colorScheme)
            // Cream paper in both rooms: an envelope keeps its materiality
            // on the black (build 44).
            let paper: Color = Cream.paper(colorScheme)
            let line = Cream.ink.opacity(0.72)
            let stroke = StrokeStyle(lineWidth: max(1, width / 56), lineCap: .round, lineJoin: .round)
            let pocket = RoundedRectangle(cornerRadius: width / 36, style: .continuous)
            ZStack(alignment: .bottom) {
                // The flap, up: behind the slip, above the envelope.
                EnvelopeFlap(openness: openness)
                    .fill(paper)
                    .overlay(EnvelopeFlap(openness: openness).stroke(line, style: stroke))
                    .frame(width: width, height: height)
                    .opacity(openness > 0.5 ? 1 : 0)
                // The slip inside, which rises.
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(NotePaper.base(colorScheme))
                    .overlay {
                        VStack(spacing: height * 0.11) {
                            ForEach(0..<3, id: \.self) { _ in
                                Capsule().fill(NotePaper.ink.opacity(0.28)).frame(height: max(1, width / 70))
                            }
                        }
                        .padding(.horizontal, width * 0.1)
                        .padding(.top, height * 0.12)
                        .frame(maxHeight: .infinity, alignment: .top)
                    }
                    .frame(width: width * 0.76, height: height * 0.84)
                    .offset(y: -height * 0.06 - lifted * height * 0.5)
                // The envelope's front, which the slip comes out from behind.
                pocket.fill(paper)
                    .overlay(EnvelopeFolds().stroke(line.opacity(0.55), style: stroke))
                    .overlay(pocket.stroke(line, style: stroke))
                    .frame(width: width, height: height)
                // The flap, down: over the front.
                EnvelopeFlap(openness: openness)
                    .stroke(line, style: stroke)
                    .frame(width: width, height: height)
                    .opacity(openness > 0.5 ? 0 : 1)
                if wax {
                    // The palette's own accent, not the tint: the tint
                    // doesn't follow the daylight this is drawn in.
                    Circle()
                        .fill(Atmosphere.resolve(raw).palette.accent)
                        .frame(width: width * 0.2, height: width * 0.2)
                        .offset(y: -height * 0.48 + width * 0.1)
                        // It breaks as the flap lifts: gone before the
                        // flap is flat.
                        .scaleEffect(1 + 0.3 * openness)
                        .opacity(Double(max(0, 1 - 3.2 * openness)))
                }
            }
            .frame(width: width, height: proxy.size.height, alignment: .bottom)
        }
        .aspectRatio(1 / 0.98, contentMode: .fit)
        // The seal is the accent as it is in daylight: on cream, the dark
        // room's warm white accent would vanish.
        .environment(\.colorScheme, .light)
        .accessibilityHidden(true)
    }
}

// MARK: - In Today

/// The letters' place in Today: last month's while they're open, and this
/// month's to write.
struct CircleLetterCards: View {
    let letters: CircleLetterState

    var body: some View {
        VStack(spacing: Spacing.section) {
            if let revealed = letters.revealed {
                OpenedLettersCard(revealed: revealed)
            }
            if letters.open {
                LetterWritingCard(letters: letters)
            }
        }
    }
}

/// A sealed envelope on the page, asking for this month's letter; once
/// yours is in, it says so behind a lock, and a tap opens it to change.
struct LetterWritingCard: View {
    let letters: CircleLetterState
    @State private var writing = false

    private var sealed: Bool { letters.letter != nil }

    var body: some View {
        Button { writing = true } label: {
            HStack(alignment: .center, spacing: 16) {
                EnvelopeMark(wax: sealed)
                    .frame(width: 58)
                VStack(alignment: .leading, spacing: 6) {
                    if sealed {
                        Label("Your letter is sealed", systemImage: "lock.fill")
                            .font(.system(.body, design: .rounded).weight(.medium))
                        Text("Opens \(LetterMonth.opens(letters.revealsAt)) · tap to change it")
                            .quietLabel()
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("Write something your circle should know")
                            .font(.system(.body, design: .rounded).weight(.medium))
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Anonymous. Revealed at the end of the month.")
                            .quietLabel()
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .card(h: 18, v: 14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            sealed
                ? "Your letter to the circle is sealed. It opens on \(LetterMonth.opens(letters.revealsAt))."
                : "Write something your circle should know. Anonymous. Revealed at the end of the month."
        )
        .accessibilityHint(sealed ? "Opens your letter to change it" : "Opens a page to write on")
        .accessibilityAddTraits(.isButton)
        .sheet(isPresented: $writing) {
            LetterWritingSheet(letters: letters)
        }
    }
}

/// Last month's letters, out: an envelope whose seal breaks and whose flap
/// lifts as the card comes onto the page. A tap reads them.
struct OpenedLettersCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let revealed: CircleLetterState.Revealed
    @State private var open = false
    @State private var reading = false

    var body: some View {
        Button { reading = true } label: {
            HStack(alignment: .center, spacing: 16) {
                EnvelopeMark(openness: open ? 1 : 0, lifted: open ? 1 : 0, wax: true)
                    .frame(width: 58)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Letters from your circle")
                        .font(.system(.body, design: .rounded).weight(.medium))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(LetterMonth.name(revealed.month)) · unsigned · here through \(LetterMonth.lastDay(revealed.fadesAt))")
                        .quietLabel()
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "arrow.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .card(h: 18, v: 14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Letters from your circle, from \(LetterMonth.name(revealed.month)). Unsigned. Here through \(LetterMonth.lastDay(revealed.fadesAt)).")
        .accessibilityHint("Opens the letters")
        .accessibilityAddTraits(.isButton)
        .onAppear {
            guard !open else { return }
            if reduceMotion {
                open = true
            } else {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85).delay(0.25)) { open = true }
            }
        }
        .sheet(isPresented: $reading) {
            OpenedLettersSheet(revealed: revealed)
        }
    }
}

// MARK: - Writing one

/// This month's letter, written or rewritten: a page of the journal with
/// the envelope it will go in, the prompt as the line to write on, and what
/// becomes of it said plainly beneath. Seal keeps it; a letter already in
/// can be taken back.
struct LetterWritingSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    let letters: CircleLetterState

    @State private var text = ""
    @State private var sealing = false
    @State private var confirmTakeBack = false
    @FocusState private var focused: Bool

    private var written: String? { letters.letter?.body }
    private var changed: Bool { text.hasWords && text.trimmedWords != written }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .center, spacing: 16) {
                        EnvelopeMark(wax: written != nil)
                            .frame(width: 66)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(state.circle.map { "To \($0.name)" } ?? "To your circle")
                                .font(.hand(26, bold: true, relativeTo: .title2))
                                .lineLimit(2)
                                .minimumScaleFactor(0.7)
                            Text("\(LetterMonth.name(letters.month)) · unsigned")
                                .quietLabel()
                        }
                        Spacer(minLength: 0)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        TextField(
                            "", text: $text,
                            prompt: Text("Write something your circle should know").foregroundColor(.secondary),
                            axis: .vertical
                        )
                        .font(.hand(20, relativeTo: .body))
                        .textFieldStyle(.plain)
                        .lineLimit(6...22)
                        .focused($focused)
                        .onChange(of: text) { _, new in
                            let clamped = WritingLimit.clamp(new, WritingLimit.circleLetter)
                            if clamped != new { text = clamped }
                        }
                        Rule(weight: 0.5)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Anonymous. Revealed at the end of the month.")
                            .font(.footnote.weight(.medium))
                        Text("No name goes on it, and nobody is told who has written one. It opens for the whole circle on \(LetterMonth.opens(letters.revealsAt)), with everyone else's, and stays a week. You can change it until then.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if written != nil {
                        Button("Take It Back", role: .destructive) { confirmTakeBack = true }
                            .destructiveInk()
                            .font(.callout)
                            .padding(.top, 4)
                    }
                }
                .padding(20)
                .frame(maxWidth: 600, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .atmosphereWash()
            .navigationTitle("A letter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(sealing ? "Sealing…" : "Seal") { seal() }
                        .disabled(sealing || !changed)
                }
            }
            // Unsent words don't go with a stray swipe; Cancel still leaves
            // on purpose (as the journal entry and the reflection do).
            .interactiveDismissDisabled(changed || sealing)
            .alert("Take your letter back?", isPresented: $confirmTakeBack) {
                Button("Take It Back", role: .destructive) {
                    Task { if await state.takeBackCircleLetter() { dismiss() } }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("It won't be among the letters when they open. You can still write another before then.")
            }
            .onAppear {
                text = written ?? ""
                if written == nil { focused = true }
            }
        }
    }

    private func seal() {
        sealing = true
        Task {
            if await state.sealCircleLetter(text.trimmedWords) {
                Haptics.circleLetterSealed()
                dismiss()
            }
            sealing = false
        }
    }
}

// MARK: - Reading them

/// A month's letters, opened: under a few words on what they are, each one
/// an envelope that opens as it's scrolled to. Unsigned, in an order that
/// says nothing, and nothing to do to any of them but read it (or report
/// it, or take back your own).
struct OpenedLettersSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    let revealed: CircleLetterState.Revealed

    @State private var opened: OpenedLetters?
    @State private var asked = false

    /// Yours among them, as the app last heard: nil once it's taken back.
    private var mine: String? { state.circleLetters?.revealed?.letter?.id }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(LetterMonth.name(revealed.month)) · unsigned")
                            .quietLabel()
                        Text("Letters from your circle")
                            .font(.system(.title, design: .rounded).weight(.medium))
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 4)
                            .accessibilityAddTraits(.isHeader)
                        Text("Nobody knows who wrote which, and they're in no order. They're here through \(LetterMonth.lastDay(revealed.fadesAt)), then gone.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let opened {
                        if opened.letters.isEmpty {
                            Text("There are none left to read.")
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }
                        let fade = LetterMonth.fade(from: opened.revealedAt, to: opened.fadesAt)
                        ForEach(Array(opened.letters.enumerated()), id: \.element.id) { index, letter in
                            LetterSlip(
                                letter: letter, month: opened.month, fade: fade, mine: letter.id == mine,
                                // The first few are on the page as it
                                // opens: one after another, not at once.
                                wait: index < 5 ? Double(index) * 0.28 : 0,
                                onTakenBack: { Task { await load() } }
                            )
                        }
                    } else if asked {
                        Text("The letters couldn't be opened just now.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    } else {
                        ProgressView().frame(maxWidth: .infinity).padding(.vertical, 30)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, Spacing.chapter)
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .atmosphereWash()
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .task { await load() }
        }
    }

    private func load() async {
        let loaded = await state.openedCircleLetters()
        if loaded != nil || opened == nil { opened = loaded }
        asked = true
    }
}

/// One letter: its words in a hand on a slip of barely tinted paper, torn
/// along the bottom, a little crooked and a little off the middle. It
/// starts as a sealed envelope and opens when it's scrolled to: the seal
/// breaks, the flap lifts, and the slip comes out and settles as the
/// envelope goes. Under Reduce Motion it only fades in.
struct LetterSlip: View {
    @Environment(AppState.self) private var state
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let letter: CircleLetter
    let month: String
    /// How far the week has faded the ink, 0 to 1.
    let fade: Double
    /// Whether it's this phone's own person's. Only its menu says so.
    let mine: Bool
    /// How long after it comes onto the page it waits to open.
    var wait: Double = 0
    var onTakenBack: () -> Void

    /// 0 sealed, 1 the flap up, 2 out on the table.
    @State private var stage = 0
    @State private var reporting = false
    @State private var confirmTakeBack = false

    var body: some View {
        let seed = CircleLetterPaper.seed(letter.id)
        let dark = DarkRoom.isDark(colorScheme)
        let edge = TornEdge(seed: seed)
        Text(letter.body)
            .font(.hand(19, relativeTo: .body))
            .lineSpacing(3)
            .foregroundStyle(NotePaper.ink.opacity(1 - 0.45 * fade))
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 22)
            .background {
                edge.fill(CircleLetterPaper.color(seed, colorScheme))
                    // Paper keeps its grain in the dark (it draws none there
                    // unless told it's daylight).
                    .overlay(PaperGrainView(strength: 0.35).environment(\.colorScheme, .light).clipShape(edge))
                    .shadow(color: .black.opacity(dark ? 0 : 0.06), radius: 8, x: 0, y: 4)
                    .shadow(color: .black.opacity(dark ? 0 : 0.10), radius: 2, x: 0.5, y: 1.5)
            }
            .rotationEffect(.degrees(CircleLetterPaper.tilt(seed)))
            .offset(x: CircleLetterPaper.lean(seed))
            .opacity(stage == 2 ? 1 : 0)
            .scaleEffect(stage == 2 ? 1 : 0.9, anchor: .top)
            .offset(y: stage == 2 || reduceMotion ? 0 : 26)
            .overlay(alignment: .top) {
                EnvelopeMark(openness: stage >= 1 ? 1 : 0, lifted: stage >= 1 ? 0.8 : 0, wax: true)
                    .frame(width: 104)
                    .offset(y: -8)
                    .opacity(stage == 2 ? 0 : 1)
                    .allowsHitTesting(false)
            }
            .padding(.horizontal, 14)
            .contentShape(Rectangle())
            .contextMenu {
                if mine {
                    Button(role: .destructive) { confirmTakeBack = true } label: {
                        Label("Take My Letter Back", systemImage: "trash")
                    }
                } else {
                    Button { reporting = true } label: {
                        Label("Report Letter", systemImage: "flag")
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("A letter. \(letter.body)")
            .onAppear(perform: open)
            .sheet(isPresented: $reporting) {
                ReportSheet(target: .circleLetter(letter))
            }
            .alert("Take your letter back?", isPresented: $confirmTakeBack) {
                Button("Take It Back", role: .destructive) {
                    Task { if await state.takeBackCircleLetter(month: month) { onTakenBack() } }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("It goes for everyone, for good. Nobody is told it was yours.")
            }
    }

    private func open() {
        guard stage == 0 else { return }
        if reduceMotion {
            withAnimation(.easeOut(duration: 0.25)) { stage = 2 }
        } else {
            withAnimation(.easeOut(duration: 0.25).delay(0.15 + wait)) { stage = 1 }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85).delay(0.45 + wait)) { stage = 2 }
        }
    }
}
