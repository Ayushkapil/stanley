import SwiftUI

/// One circle's countdown under Today's dateline (build 35; a flight path
/// since build 74). A thin hairline across the page with a small drawn
/// plane where the trip stands today: solid behind it, dotted ahead, the
/// journey's legs marked along its last part. Under it, the words: "India
/// in 9 days" while it's more than a week off, plain; a week or less, the
/// number in the hand and the strip warming as it comes; the last day in
/// hours; then the leg it's on ("Chicago", "In the air"), and "Landed",
/// which holds a day before the strip goes on its own. Never a negative
/// number. A tap opens the journey as a card (`JourneyCard`). The day's
/// note a friend tucked in (build 36) sits above it on its day. No emoji
/// anywhere: the plane is drawn.
///
/// Drawn only for the circle the server flagged (`CircleInfo.countdown`);
/// every other circle never sees it. The journey lives in the config
/// (`Countdown.legs`), the rules in `CountdownJourney.swift`.
struct CountdownRoute: View {
    let countdown: Countdown
    @State private var reading = false
    /// Read by the body so the strip is drawn again each tick.
    @State private var tick = Date.now

    /// Twice a minute: nothing on the strip is finer than an hour, and a
    /// page left open still crosses into the next leg, or away, on its own.
    private static let ticks = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        // Not a TimelineView: one stays in the masthead's stack with nothing
        // in it and keeps a spacing's worth of room once the strip has gone.
        // With the strip gone this view is empty, and the masthead closes up.
        let _ = tick
        let now = CountdownClock.now()
        if let journey = countdown.journey(at: now) {
            let reminder = countdown.phase(at: now)?.reminder
            Button {
                Haptics.journeyOpened()
                reading = true
            } label: {
                strip(journey, reminder: reminder)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(journey.spoken(reminder: reminder))
            .accessibilityHint("Opens the journey")
            .accessibilityAddTraits(.isButton)
            .onReceive(Self.ticks) { tick = $0 }
            .sheet(isPresented: $reading) {
                JourneyCard(countdown: countdown)
            }
        }
    }

    private func strip(_ journey: Countdown.Journey, reminder: String?) -> some View {
        let ink = CountdownTone.ink(journey.warmth)
        return VStack(spacing: 5) {
            if let reminder {
                ReminderSlip(words: reminder)
                    .padding(.top, 10)
                    .padding(.bottom, 6)
            }
            FlightPath(journey: journey, ink: ink)
            JourneyWords(journey: journey, size: 20)
                .font(.system(.subheadline, design: .rounded).weight(.medium))
                .foregroundStyle(ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}

/// The words, with the number apart: in the hand, larger, once the trip is
/// a week off or less; set like the rest before then.
private struct JourneyWords: View {
    let journey: Countdown.Journey
    let size: CGFloat

    var body: some View {
        let parts = journey.words
        var line = AttributedString(parts.lead)
        if let number = parts.number {
            var figure = AttributedString(number)
            if journey.close { figure.font = .hand(size, bold: true, relativeTo: .title3) }
            line += figure
        }
        line += AttributedString(parts.tail)
        return Text(line)
    }
}

// MARK: - The strip

/// The flight path: a hairline from the left edge to the destination, solid
/// where the plane has been and dotted where it's going, a small dot where
/// it began, the journey's stops along its last part (filled once passed),
/// a ring at the end, and the plane between, the line stopping short of it
/// either side so it reads as flying, not crossed out. Decorative: the
/// strip's words say it all.
private struct FlightPath: View {
    static let height: CGFloat = 16
    let journey: Countdown.Journey
    let ink: Color

    var body: some View {
        GeometryReader { geo in
            let inset: CGFloat = 4
            let width = max(1, geo.size.width - inset * 2)
            let y = geo.size.height / 2
            let x = { (t: Double) in inset + width * CGFloat(t) }
            let plane = x(journey.progress)
            let gap: CGFloat = 10
            ZStack {
                if plane - gap > x(0) {
                    Path { path in
                        path.move(to: CGPoint(x: x(0), y: y))
                        path.addLine(to: CGPoint(x: plane - gap, y: y))
                    }
                    .stroke(ink, style: StrokeStyle(lineWidth: 1, lineCap: .round))
                }
                if plane + gap < x(1) {
                    Path { path in
                        path.move(to: CGPoint(x: plane + gap, y: y))
                        path.addLine(to: CGPoint(x: x(1), y: y))
                    }
                    .stroke(ink, style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [0.1, 4]))
                }
                Circle()
                    .fill(ink)
                    .frame(width: 3, height: 3)
                    .position(x: x(0), y: y)
                ForEach(Array(journey.marks.enumerated()), id: \.offset) { index, mark in
                    let last = index == journey.marks.count - 1
                    let passed = journey.progress >= mark
                    // A stop under the plane is left for the plane.
                    if abs(x(mark) - plane) > gap {
                        Group {
                            if passed && !last {
                                Circle().fill(ink)
                            } else {
                                Circle().strokeBorder(ink, lineWidth: 1)
                            }
                        }
                        .frame(width: last ? 7 : 4, height: last ? 7 : 4)
                        .position(x: x(mark), y: y)
                    }
                }
                Image(systemName: "airplane")
                    .font(.system(size: 12, weight: .light))
                    .foregroundStyle(ink)
                    .position(x: plane, y: y)
            }
        }
        .frame(height: Self.height)
        .accessibilityHidden(true)
    }
}

// MARK: - The card

/// The journey as a small card, from a tap on the strip: the trip's name,
/// where it stands, the legs down a line with the plane on it (solid behind,
/// dotted ahead), each leg's moment in the viewer's own time, the one it's
/// on named, and when it arrives.
private struct JourneyCard: View {
    let countdown: Countdown
    @AppStorage("stanley.atmosphere") private var raw = "auto"
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        TimelineView(.periodic(from: Calendar.current.startOfDay(for: .now), by: 30)) { context in
            // The moment itself, not the tick's, which can be a half minute
            // behind it.
            let now = CountdownClock.now(max(context.date, .now))
            ScrollView {
                if let journey = countdown.journey(at: now) {
                    content(journey)
                } else {
                    // The strip has gone while the card was open.
                    Text(countdown.label)
                        .font(.pageTitle)
                        .foregroundStyle(TextTone.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(24)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Atmosphere.resolve(raw).palette.floor)
    }

    private func content(_ journey: Countdown.Journey) -> some View {
        let ink = CountdownTone.ink(journey.warmth)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(countdown.label)
                    .font(.pageTitle)
                    .foregroundStyle(TextTone.primary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button("Done") { dismiss() }
                    .font(.system(.body, design: .rounded).weight(.medium))
                    .foregroundStyle(TextTone.primary)
            }
            JourneyWords(journey: journey, size: 26)
                .font(.system(.title3, design: .rounded).weight(.medium))
                .foregroundStyle(ink)
                .padding(.top, 2)
                .accessibilityLabel(journey.current == nil ? journey.text : "Now: \(journey.text)")
            Legs(journey: journey, ink: ink)
                .padding(.top, 22)
            if let landing = journey.stops.last {
                Rule(weight: 0.5)
                    .padding(.top, 18)
                Text(Self.arrival(landing.at, landed: journey.landed))
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(TextTone.secondary)
                    .padding(.top, 10)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 16)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity)
    }

    /// "Arrives Tuesday 24 November, 3:00 PM", in the viewer's own time.
    static func arrival(_ at: Date, landed: Bool) -> String {
        let when = at.formatted(.dateTime.weekday(.wide).day().month(.wide))
        let time = at.formatted(.dateTime.hour().minute())
        return "\(landed ? "Arrived" : "Arrives") \(when), \(time)"
    }
}

/// The legs down a line, a row each at an even pitch: the line between two
/// stops solid once flown and dotted ahead, the plane where the trip is
/// (between the two, by how much of the leg has passed), a stop filled
/// once reached, and the leg it's on in the warm ink.
private struct Legs: View {
    let journey: Countdown.Journey
    let ink: Color
    @ScaledMetric(relativeTo: .body) private var pitch: CGFloat = 54
    private let rail: CGFloat = 28

    var body: some View {
        let stops = journey.stops
        let current = journey.current
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(stops.enumerated()), id: \.offset) { index, stop in
                HStack(alignment: .center, spacing: 12) {
                    Color.clear.frame(width: rail)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(stop.words)
                            .font(.system(.body, design: .rounded).weight(index == current ? .semibold : .regular))
                            .foregroundStyle(index == current ? ink : reached(index) ? TextTone.primary : TextTone.secondary)
                        Text(stop.at.formatted(.dateTime.weekday(.wide).day().month(.abbreviated).hour().minute()))
                            .font(.footnote)
                            .foregroundStyle(TextTone.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .frame(height: pitch)
                .accessibilityElement(children: .combine)
                .accessibilityValue(index == current ? "Now" : reached(index) ? "Done" : "Ahead")
            }
        }
        .background(alignment: .topLeading) {
            line(stops.count)
        }
    }

    private func reached(_ index: Int) -> Bool {
        guard let current = journey.current else { return false }
        return index <= current
    }

    /// Where the plane is down the line, in rows: on the first stop before
    /// it begins, between two while a leg is flown, on the last landed.
    private var place: CGFloat {
        guard let current = journey.current else { return 0 }
        let stops = journey.stops
        guard current < stops.count - 1, journey.marks.count == stops.count else { return CGFloat(current) }
        let from = journey.marks[current], to = journey.marks[current + 1]
        let within = to > from ? (journey.progress - from) / (to - from) : 0
        return CGFloat(current) + CGFloat(min(1, max(0, within)))
    }

    private func line(_ count: Int) -> some View {
        let x = rail / 2
        let center = { (row: CGFloat) in self.pitch * (row + 0.5) }
        let plane = center(place)
        let gap: CGFloat = 12
        return ZStack(alignment: .topLeading) {
            if count > 1 {
                if plane - gap > center(0) {
                    Path { path in
                        path.move(to: CGPoint(x: x, y: center(0)))
                        path.addLine(to: CGPoint(x: x, y: plane - gap))
                    }
                    .stroke(ink, style: StrokeStyle(lineWidth: 1, lineCap: .round))
                }
                if plane + gap < center(CGFloat(count - 1)) {
                    Path { path in
                        path.move(to: CGPoint(x: x, y: plane + gap))
                        path.addLine(to: CGPoint(x: x, y: center(CGFloat(count - 1))))
                    }
                    .stroke(ink, style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [0.1, 4.5]))
                }
            }
            ForEach(0..<count, id: \.self) { index in
                let y = center(CGFloat(index))
                if abs(y - plane) > gap {
                    Group {
                        if reached(index) {
                            Circle().fill(ink)
                        } else {
                            Circle().strokeBorder(ink, lineWidth: 1)
                        }
                    }
                    .frame(width: 7, height: 7)
                    .position(x: x, y: y)
                }
            }
            Image(systemName: "airplane")
                .font(.system(size: 15, weight: .light))
                .rotationEffect(.degrees(90))
                .foregroundStyle(ink)
                .position(x: x, y: plane)
        }
        .frame(width: rail, height: pitch * CGFloat(count), alignment: .topLeading)
        .accessibilityHidden(true)
    }
}

// MARK: - The clock

/// The moment the countdown reads. In a Debug build,
/// `STANLEY_COUNTDOWN_NOW` (ISO 8601 with its offset) moves it to then at
/// launch and lets it run on from there, to see each leg on a simulator.
enum CountdownClock {
    #if DEBUG
    private static let shift: TimeInterval = {
        guard let text = ProcessInfo.processInfo.environment["STANLEY_COUNTDOWN_NOW"],
              let then = Countdown.moment(text)
        else { return 0 }
        return then.timeIntervalSinceNow
    }()
    #endif

    static func now(_ date: Date? = nil) -> Date {
        #if DEBUG
        // The shift first: worked out on first use, against a moment that
        // must not come before it, or a clock set to a leg's very minute
        // reads a hair before it.
        let shift = shift
        return (date ?? .now).addingTimeInterval(shift)
        #else
        return date ?? .now
        #endif
    }
}

// MARK: - The day's note

/// A note a friend tucked into the page (build 36; one for every day since
/// build 38): a small slip torn from something, a little crooked, held by a
/// bit of tape, the words in a hand a size under the countdown's. The sticky
/// note's paper and ink, smaller and more casual. It's there on its day, and
/// the next day brings another; nothing to dismiss, nothing that asks for
/// anything. It arrives the way a note would: fading in as it settles down
/// onto the page, once each time the page shows it (only the fade under
/// Reduce Motion).
private struct ReminderSlip: View {
    let words: String
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stuck = false

    /// The note's own: from its words, so it lies the same way every time it's
    /// drawn and differently from the next one.
    private var seed: UInt32 {
        words.unicodeScalars.reduce(UInt32(7)) { $0 &* 31 &+ $1.value }
    }

    /// Between 2° and 4° off square, either way.
    private var tilt: Double {
        let degrees = 2 + Double(seed % 21) / 10
        return seed & 0x100 == 0 ? degrees : -degrees
    }

    var body: some View {
        let line = Text(words)
            .font(.hand(14, relativeTo: .footnote))
            .foregroundStyle(NotePaper.ink)
            .multilineTextAlignment(.center)
        // As wide as its words, the way a scrap is torn to fit a note, up to
        // a small slip's width: a longer note ("What's the first thing you're
        // eating when you land?") wraps onto a second line rather than
        // stretching into a banner across the page.
        ViewThatFits(in: .horizontal) {
            scrap(line.fixedSize())
            scrap(line.fixedSize(horizontal: false, vertical: true).frame(maxWidth: 180))
        }
            .frame(maxWidth: 250)
            .rotationEffect(.degrees(tilt))
            .opacity(stuck ? 1 : 0)
            .offset(y: stuck || reduceMotion ? 0 : -8)
            .onAppear {
                withAnimation(.easeOut(duration: 0.5).delay(0.25)) { stuck = true }
            }
            .onDisappear { stuck = false }
    }

    /// The words on their torn scrap, under their bit of tape.
    private func scrap(_ words: some View) -> some View {
        let edge = TornEdge(seed: seed)
        return words
            .padding(.horizontal, 14)
            .padding(.top, 9)
            .padding(.bottom, 11)
            .background {
                edge.fill(NotePaper.base(colorScheme))
                    .overlay(PaperGrainView(strength: 0.5).clipShape(edge))
                    .shadow(color: .black.opacity(colorScheme == .dark ? 0.45 : 0.13), radius: 3, x: 0.5, y: 1.5)
            }
            .overlay(alignment: .top) {
                Tape()
                    .scaleEffect(0.62)
                    .offset(y: -9)
            }
    }
}
