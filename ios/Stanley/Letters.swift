import SwiftUI

// Letters to your circle (build 42).
//
// A sealed letter from one person in a circle to another, held closed until
// a day the sender chose. The envelope sits among held photos the way a
// real letter would be tucked into a photo album. The seal is broken on
// the day — never before — and the letter is a page of the journal
// afterwards (build 45; an opened envelope in Held until then).
//
// The sender writes from a "Write to someone" slip on the You tab, picks a
// recipient from the circle's roster, chooses a date between a week and a
// year out, writes a line for the front of the envelope (or leaves it
// blank), and the body itself. Sealing hands the words to Stanley; the
// sender can take back a letter still sealed but cannot reread one.

// MARK: - Shared shape

/// What the UI needs to know about a letter without deciding where to show
/// it: the sender's or recipient's face and words, the day, the state.
struct LetterFace {
    let letter: Letter
    /// Formatted "Open on June 10" style for the envelope.
    var dateLabel: String {
        guard let d = letter.deliveryDay else { return letter.deliverAt }
        return d.formatted(.dateTime.month(.wide).day())
    }
    /// What goes on the envelope: the sender's own words if they wrote
    /// them, otherwise the date spelled out. Neither counts anyone.
    var inscription: String {
        if let occasion = letter.occasion, !occasion.isEmpty { return occasion }
        return "Open on \(dateLabel)"
    }
}

// MARK: - The Letters page: "Write to someone"

/// On the Letters page, reached from under the journal's cover (it was on
/// the You tab until build 45): the "Write to someone" slip, and a short
/// list of sealed letters on their way (so the sender knows what's out
/// there and can take one back).
struct LettersOnYou: View {
    @Environment(AppState.self) private var state
    @State private var composing = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.section) {
            JournalSectionHead(label: "From you", title: "Yours to send", hand: true)
            Text("Write a letter now; Stanley holds it closed until the day you choose.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button { composing = true } label: {
                writeSlip
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the compose sheet for a sealed letter.")

            if !state.lettersSent.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("On their way").quietLabel()
                    ForEach(state.lettersSent) { letter in
                        SentLetterRow(letter: letter)
                    }
                }
                .padding(.top, Spacing.section)
            }
        }
        .sheet(isPresented: $composing) { ComposeLetterSheet() }
    }

    /// The slip itself: a scrap of paper with "Write to someone" in the
    /// hand, an inkwell pen, a line to remind you what this is.
    private var writeSlip: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "pencil.and.scribble")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(.tint)
                .frame(width: 40, height: 40)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Write to someone")
                    .font(.system(.body, design: .rounded).weight(.medium))
                Text("A letter for one day in the future.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(h: 18, v: 14)
    }
}

/// One of your sent letters, sealed status only (the server doesn't send
/// the body back). A long press gives withdraw while it's still sealed;
/// an opened letter is gone from the sender's hands.
private struct SentLetterRow: View {
    @Environment(AppState.self) private var state
    let letter: Letter
    @State private var confirmWithdraw = false

    var body: some View {
        let face = LetterFace(letter: letter)
        HStack(alignment: .top, spacing: 12) {
            MiniEnvelope()
            VStack(alignment: .leading, spacing: 3) {
                Text("For \(letter.recipient?.displayName ?? "someone")")
                    .font(.subheadline.weight(.medium))
                Text(face.inscription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text(letter.sealed ? "Sealed · opens \(face.dateLabel)" : "Opened")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .contextMenu {
            if letter.senderCanDelete == true {
                Button(role: .destructive) { confirmWithdraw = true } label: {
                    Label("Withdraw letter", systemImage: "trash")
                }
            }
        }
        .confirmationDialog(
            "Take this letter back?",
            isPresented: $confirmWithdraw,
            titleVisibility: .visible
        ) {
            Button("Withdraw", role: .destructive) {
                Task { await state.deleteLetter(letter.id) }
            }
            Button("Keep it sealed", role: .cancel) {}
        } message: {
            Text("The envelope will disappear from their Held. You'll never see the words again.")
        }
    }
}

/// A small envelope icon for list rows: the paper, a wax dot.
private struct MiniEnvelope: View {
    @AppStorage("stanley.atmosphere") private var raw = "auto"
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let dark = DarkRoom.isDark(colorScheme)
        let accent = Atmosphere.resolve(raw).palette.accent
        return ZStack {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Cream.paper(colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .stroke(Cream.ink.opacity(0.28), lineWidth: 0.5)
                )
            Path { p in
                p.move(to: CGPoint(x: 1, y: 2))
                p.addLine(to: CGPoint(x: 20, y: 14))
                p.addLine(to: CGPoint(x: 39, y: 2))
            }
            .stroke(Cream.ink.opacity(0.28), lineWidth: 0.5)
            Circle()
                .fill(accent)
                .frame(width: 8, height: 8)
                .offset(x: 10, y: 6)
        }
        .frame(width: 40, height: 28)
        .onCream()
        .accessibilityHidden(true)
    }
}

// MARK: - The Letters page: sealed envelopes

/// The letters written to you that are still sealed, on the Letters page
/// under the journal's cover. Each envelope is a tap target; before its
/// day the tap says "Not yet", on the day it opens the reader with the
/// seal-break animation. Once opened, a letter is a page of the book
/// (build 45; opened ones lay here too until then).
struct LettersOnHeld: View {
    @Environment(AppState.self) private var state
    @Environment(\.horizontalSizeClass) private var hSizeClass
    /// A letter whose day has come was tapped. The page it's on shows the
    /// reader, not this section: once the last sealed letter is opened this
    /// section is gone, and a sheet of its own went with it mid-reading.
    let onOpen: (Letter) -> Void

    var body: some View {
        let sealed = state.lettersReceived.sealed
        if sealed.isEmpty { EmptyView() }
        else {
            VStack(alignment: .leading, spacing: Spacing.section) {
                JournalSectionHead(label: "Written to you", title: "Waiting", hand: true)
                // One to a line on a phone; side by side on the Duo's
                // inner display.
                LazyVGrid(
                    columns: Array(
                        repeating: GridItem(.flexible(), spacing: Spacing.chapter),
                        count: Density(hSizeClass).isRoom ? 2 : 1
                    ),
                    alignment: .leading, spacing: Spacing.section
                ) {
                    ForEach(sealed) { letter in
                        SealedEnvelopeView(letter: letter) { onOpen(letter) }
                    }
                }
            }
        }
    }
}

// MARK: - The sealed envelope

/// A sealed letter laid among the photos like a real envelope tucked into
/// an album: cream paper (or black in the dark room), a handwritten "From
/// [name]" on the front, the date or occasion, and a wax seal in the
/// atmosphere's accent. Tapping before the date says "Not yet" with a
/// gentle haptic; on the day it opens the reader.
struct SealedEnvelopeView: View {
    @AppStorage("stanley.atmosphere") private var raw = "auto"
    @Environment(\.colorScheme) private var colorScheme
    let letter: Letter
    var onTap: () -> Void = {}
    @State private var nudging = false

    var body: some View {
        let dark = DarkRoom.isDark(colorScheme)
        let accent = Atmosphere.resolve(raw).palette.accent
        let face = LetterFace(letter: letter)
        let deliverable = letter.deliverable == true
        let sender = letter.sender?.displayName ?? "someone"

        Button(action: tap) {
            ZStack {
                // The whole front, filled: filling the shape itself left
                // the flap's V as a hole the page showed through.
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Cream.paper(colorScheme))
                    .overlay(
                        EnvelopeShape(flapOpen: 0, flapAngle: 0)
                            .stroke(Cream.ink.opacity(0.28), lineWidth: 0.6)
                    )
                    .shadow(color: .black.opacity(dark ? 0 : 0.14), radius: 5, x: 0.5, y: 3)

                // The handwritten address and inscription.
                VStack(alignment: .leading, spacing: 6) {
                    Spacer(minLength: 32)
                    Text("From \(sender)")
                        .font(.hand(22, bold: true, relativeTo: .title3))
                        .foregroundStyle(.primary)
                    Text(face.inscription)
                        .font(.hand(17, relativeTo: .callout))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Spacer()
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 18)
                .frame(maxWidth: .infinity, alignment: .leading)

                // The wax seal: a small disc in the accent, centered toward
                // the lower middle the way a seal holds the flap down.
                WaxSeal(color: accent, cracking: false)
                    .frame(width: 56, height: 56)
                    .offset(y: 46)
                    .accessibilityHidden(true)
            }
            .aspectRatio(1.55, contentMode: .fit)
            .onCream()
            .rotationEffect(.degrees(nudging ? -1.2 : 0))
            .rotationEffect(.degrees(PrintTilt.degrees(letter.id) * 0.4))
            .animation(.spring(response: 0.25, dampingFraction: 0.85), value: nudging)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "Sealed letter from \(sender), \(face.inscription), " +
            (deliverable ? "ready to open." : "cannot be opened until \(face.dateLabel).")
        )
        .accessibilityAddTraits(deliverable ? .isButton : [])
    }

    private func tap() {
        if letter.deliverable == true {
            onTap()
        } else {
            // A gentle nudge: the envelope leans a hair and the phone
            // taps softly, with "Not yet" spoken over whatever's on top
            // (an alert the HCI audit asked for, not a sheet that would
            // close the album under it).
            Haptics.liked()
            nudging = true
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 220_000_000)
                nudging = false
            }
            let date = LetterFace(letter: letter).dateLabel
            Spoken.alert("Not yet. Opens \(date).") {}
        }
    }
}

// MARK: - The envelope shape

/// An envelope, rounded, with a flap at the top that can be closed (0)
/// or open (1), tipping back by `flapAngle` degrees. One shape so the
/// crack animation can slide a letter up out of it.
struct EnvelopeShape: Shape {
    /// 0 sealed, 1 fully open.
    var flapOpen: Double
    var flapAngle: Double

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(flapOpen, flapAngle) }
        set { flapOpen = newValue.first; flapAngle = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let radius: CGFloat = 4
        // The body (no top edge — the flap draws it).
        p.addRoundedRect(in: rect, cornerSize: CGSize(width: radius, height: radius))
        // The front "V" where the flap would fold, drawn lightly.
        let apexY = rect.minY + rect.height * 0.55 * (1 - flapOpen * 0.4)
        p.move(to: CGPoint(x: rect.minX + radius, y: rect.minY + 1))
        p.addLine(to: CGPoint(x: rect.midX, y: apexY))
        p.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY + 1))
        return p
    }
}

/// A wax seal: a disc in the atmosphere's accent, with faint cracks if
/// it's being broken. Flat, drawn, no textures that would look like a sticker.
struct WaxSeal: View {
    let color: Color
    /// When true, draw the crack lines splitting outward.
    var cracking: Bool

    var body: some View {
        ZStack {
            Circle().fill(color)
            Circle()
                .fill(
                    RadialGradient(colors: [.white.opacity(0.14), .clear], center: .init(x: 0.35, y: 0.35), startRadius: 1, endRadius: 24)
                )
            Circle()
                .stroke(.black.opacity(0.18), lineWidth: 0.5)
                .blur(radius: 0.3)
            // Six fine cracks when the seal is breaking.
            if cracking {
                ForEach(0..<6, id: \.self) { i in
                    Rectangle()
                        .fill(.black.opacity(0.35))
                        .frame(width: 0.8, height: 44)
                        .offset(y: -8)
                        .rotationEffect(.degrees(Double(i) * 60 + 7))
                        .mask(Circle())
                        .transition(.opacity)
                }
            }
        }
    }
}

// MARK: - The reader sheet (break-the-seal animation + letter on paper)

/// The sheet the recipient reads the letter in. If the letter arrives
/// sealed (first time), the seal breaks on appear: a small crack
/// animation, a medium haptic, the flap lifts, the letter slides up out
/// of the envelope and comes to rest on the paper. An already-opened
/// letter is shown immediately.
struct LetterReaderSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var state
    @AppStorage("stanley.atmosphere") private var raw = "auto"
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let letter: Letter
    @State private var opened: Letter?
    @State private var phase: Phase = .sealed

    private enum Phase {
        case sealed, breaking, revealed
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    headerArea
                        .padding(.horizontal, 20)
                    if phase != .sealed {
                        VStack(spacing: 18) {
                            LetterPaper(letter: opened ?? letter)
                            // Opened, it's kept where everything of yours is.
                            Text("It's a page of your journal now.")
                                .quietLabel()
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 40)
                        .transition(.asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .opacity
                        ))
                    }
                }
                .padding(.vertical, 24)
            }
            .atmosphereWash()
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task { await begin() }
    }

    /// The sealed envelope, animating as it opens; or just the envelope
    /// quietly once the letter is already open.
    private var headerArea: some View {
        let dark = DarkRoom.isDark(colorScheme)
        let accent = Atmosphere.resolve(raw).palette.accent
        let face = LetterFace(letter: letter)
        let sender = letter.sender?.displayName ?? "someone"
        let flapOpen = phase == .sealed ? 0.0 : 1.0
        let flapAngle = phase == .sealed ? 0.0 : 26.0

        return ZStack {
            // The whole front, filled: filling the shape itself left the
            // flap's V as a hole the page showed through.
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Cream.paper(colorScheme))
                .overlay(
                    EnvelopeShape(flapOpen: flapOpen, flapAngle: flapAngle)
                        .stroke(Cream.ink.opacity(0.28), lineWidth: 0.7)
                )
                .shadow(color: .black.opacity(dark ? 0 : 0.12), radius: 5, x: 0.5, y: 3)
            VStack(alignment: .leading, spacing: 6) {
                Spacer(minLength: 36)
                Text("From \(sender)")
                    .font(.hand(24, bold: true, relativeTo: .title3))
                Text(face.inscription)
                    .font(.hand(17, relativeTo: .callout))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 22)
            .frame(maxWidth: .infinity, alignment: .leading)

            if phase != .revealed {
                WaxSeal(color: accent, cracking: phase == .breaking)
                    .frame(width: 60, height: 60)
                    .offset(y: 52)
                    .opacity(phase == .breaking ? 0.25 : 1)
                    .scaleEffect(phase == .breaking ? 1.25 : 1)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: phase)
            }
        }
        .aspectRatio(1.55, contentMode: .fit)
        .onCream()
    }

    private func begin() async {
        // If already opened (second viewing, or a letter that arrived
        // in the opened list), just show the paper.
        if letter.sealed == false {
            opened = letter
            phase = .revealed
            return
        }
        // The seal breaks as the sheet comes up.
        if reduceMotion {
            opened = await state.openLetter(letter.id)
            Haptics.held()
            phase = .revealed
            return
        }
        try? await Task.sleep(nanoseconds: 250_000_000)
        withAnimation(.easeOut(duration: 0.25)) { phase = .breaking }
        Haptics.held()
        // The server call runs while the seal cracks.
        async let served = state.openLetter(letter.id)
        try? await Task.sleep(nanoseconds: 300_000_000)
        let got = await served
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            opened = got
            phase = .revealed
        }
    }
}

/// The letter itself on paper: a sheet of writing paper with the words in
/// a hand, the sender's name signed at the bottom, and the date it was
/// written in small capitals beneath the signature.
struct LetterPaper: View {
    let letter: Letter
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let dark = DarkRoom.isDark(colorScheme)
        let sender = letter.sender?.displayName ?? "someone"
        let body = letter.body ?? ""
        let written: String? = letter.createdAt.map {
            $0.formatted(date: .long, time: .omitted)
        }

        VStack(alignment: .leading, spacing: 18) {
            Text(body)
                .font(.hand(21, relativeTo: .body))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            Rule(weight: 0.5)
            VStack(alignment: .trailing, spacing: 4) {
                Text("— \(sender)")
                    .font(.hand(22, bold: true, relativeTo: .title3))
                if let written {
                    Text("Written on \(written)").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 26)
        .creamPaper()
    }
}

// MARK: - Compose

/// The compose sheet. Recipient from the circle's roster, a date between
/// seven days and a year away, an optional occasion label, the body (up
/// to 2000). Nothing uploads until Seal it.
struct ComposeLetterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var state

    @State private var recipientId: String = ""
    @State private var words: String = ""
    @State private var occasion: String = ""
    @State private var deliverAt: Date = Calendar.current.date(byAdding: .day, value: 7, to: Date.now) ?? Date.now
    @State private var sealing = false
    @State private var confirmCancel = false

    private var members: [CircleMember] {
        let myId = state.myId
        return (state.circle?.members ?? [])
            .filter { $0.id != myId }
            .sorted { ($0.displayName ?? "") < ($1.displayName ?? "") }
    }

    private var earliest: Date {
        Calendar.current.date(byAdding: .day, value: 7, to: Date.now) ?? Date.now
    }

    private var latest: Date {
        Calendar.current.date(byAdding: .day, value: 365, to: Date.now) ?? Date.now
    }

    private var canSeal: Bool {
        !recipientId.isEmpty && !words.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("For") {
                    if members.isEmpty {
                        Text("Nobody in this circle yet. Invite someone, then try again.")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Recipient", selection: $recipientId) {
                            Text("Choose someone").tag("")
                            ForEach(members) { m in
                                Text(m.displayName ?? "New member").tag(m.id)
                            }
                        }
                    }
                }
                Section("Opens on") {
                    DatePicker(
                        "Delivery date",
                        selection: $deliverAt,
                        in: earliest...latest,
                        displayedComponents: .date
                    )
                    Text("At least a week from now, at most a year.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("Occasion (optional)") {
                    TextField("e.g. Open on graduation day", text: $occasion, axis: .vertical)
                        .lineLimit(1...2)
                    Text("Left blank, the envelope just carries the date.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("Letter") {
                    TextEditor(text: $words)
                        .frame(minHeight: 180)
                        .font(.hand(19, relativeTo: .body))
                        .accessibilityLabel("Letter body")
                    Text("\(words.count) / 2000")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .atmosphereRows()
            .atmosphereWash()
            .navigationTitle("A letter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        if canSeal { confirmCancel = true } else { dismiss() }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(sealing ? "Sealing…" : "Seal it") { Task { await seal() } }
                        .disabled(!canSeal || sealing || words.count > 2000)
                        .bold()
                }
            }
            .confirmationDialog(
                "Discard this letter?",
                isPresented: $confirmCancel,
                titleVisibility: .visible
            ) {
                Button("Discard", role: .destructive) { dismiss() }
                Button("Keep writing", role: .cancel) {}
            } message: {
                Text("Nothing has been sent yet.")
            }
            .interactiveDismissDisabled(canSeal)
        }
    }

    private func seal() async {
        sealing = true
        defer { sealing = false }
        let trimmed = words.trimmingCharacters(in: .whitespacesAndNewlines)
        let occ = occasion.trimmingCharacters(in: .whitespacesAndNewlines)
        let ok = await state.sendLetter(
            recipientId: recipientId,
            body: trimmed,
            occasion: occ.isEmpty ? nil : occ,
            deliverAt: deliverAt
        )
        if ok {
            Haptics.held()
            dismiss()
        }
    }
}
