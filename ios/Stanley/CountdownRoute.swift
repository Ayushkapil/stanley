import SwiftUI

/// One circle's countdown under Today's dateline (build 35): a route sketched
/// on a paper map. A dotted path edge to edge, a dot where it starts, a ring
/// where it ends, and a small plane along it by how much of the wait has
/// passed; once landed, a house where the route was. Under it, in a hand,
/// where things stand, and while the day is still ahead, a flip clock
/// counting down to it (build 36). Thin strokes in the page's secondary ink,
/// a nod rather than a banner, and not a control: nothing here can be tapped.
/// No emoji anywhere: the plane and the house are drawn.
///
/// Drawn only for the circle the server flagged (`CircleInfo.countdown`);
/// every other circle never sees it.
struct CountdownRoute: View {
    let countdown: Countdown

    var body: some View {
        // Each second while the clock is counting, each minute after (a page
        // left open still crosses midnight into the next phase on its own).
        // Ticks fall on whole seconds, from the start of the day, so the
        // clock turns over with the phone's own clock.
        let counting = countdown.phase(at: .now)?.until != nil
        TimelineView(.periodic(from: Calendar.current.startOfDay(for: .now), by: counting ? 1 : 60)) { context in
            if let phase = countdown.phase(at: context.date) {
                VStack(spacing: 4) {
                    if let reminder = phase.reminder {
                        ReminderSlip(words: reminder)
                            .padding(.top, 10)
                            // Clear of the plane where the arc runs highest.
                            .padding(.bottom, 8)
                    }
                    switch phase.mark {
                    case .plane(let progress):
                        RouteSketch(progress: progress)
                    case .home:
                        Image(systemName: "house")
                            .font(.system(size: 14, weight: .light))
                            .foregroundStyle(.secondary)
                            .frame(height: RouteSketch.height)
                    }
                    Text(phase.text)
                        .font(.hand(16, relativeTo: .subheadline))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    if let until = phase.until {
                        FlipClock(remaining: until.timeIntervalSince(context.date))
                            .padding(.top, 6)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 2)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Self.spoken(phase, at: context.date))
            }
        }
    }

    /// The day's note, the words, and what's left to the minute: VoiceOver
    /// isn't read a new number every second.
    private static func spoken(_ phase: Countdown.Phase, at now: Date) -> String {
        let words = [phase.reminder, phase.text].compactMap { $0 }.joined(separator: ". ")
        guard let until = phase.until else { return words }
        let left = Countdown.clock(until.timeIntervalSince(now))
        var parts = DateComponents()
        parts.day = left.days
        parts.hour = left.hours
        parts.minute = left.minutes
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.allowedUnits = [.day, .hour, .minute]
        guard let rest = formatter.string(from: parts) else { return words }
        return "\(words). \(rest) to go."
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

// MARK: - The flip clock

/// 16 Days : 05 Hours : 23 Min : 51 Sec, each a little card of the
/// atmosphere's card color split by a hairline, the way a flip clock's are.
/// The numbers are set to be read (SF Rounded, semibold, even-width digits),
/// not written; the labels beneath are in the journal's hand. Each digit
/// flips on its own as it changes, the old one tipping down and away while
/// the new one comes up, about 0.3s, silent. The countdown's centerpiece
/// (build 38): the digits are 20pt, a quarter up from build 36's 16, and the
/// labels stay as they were.
private struct FlipClock: View {
    let remaining: TimeInterval
    @ScaledMetric(relativeTo: .subheadline) private var scaled: CGFloat = 20

    /// Grows with Dynamic Type, up to where four cards and their colons still
    /// fit across a 375pt phone's page.
    private var digit: CGFloat { min(scaled, 24) }

    var body: some View {
        let left = Countdown.clock(remaining)
        let cardHeight = (digit * 1.6).rounded()
        HStack(alignment: .top, spacing: 4) {
            FlipUnit(value: left.days, label: "Days", digit: digit, height: cardHeight)
            Colon(digit: digit, height: cardHeight)
            FlipUnit(value: left.hours, label: "Hours", digit: digit, height: cardHeight)
            Colon(digit: digit, height: cardHeight)
            FlipUnit(value: left.minutes, label: "Min", digit: digit, height: cardHeight)
            Colon(digit: digit, height: cardHeight)
            FlipUnit(value: left.seconds, label: "Sec", digit: digit, height: cardHeight)
        }
        .accessibilityHidden(true)
    }
}

private struct Colon: View {
    let digit: CGFloat
    let height: CGFloat

    var body: some View {
        Text(":")
            .font(.system(size: digit * 0.9, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
            .frame(height: height)
            .offset(y: -1)
    }
}

/// One card and its label. Its digits are told apart by place (ones, tens,
/// hundreds), so when one turns over only that one flips.
private struct FlipUnit: View {
    let value: Int
    let label: String
    let digit: CGFloat
    let height: CGFloat

    var body: some View {
        let digits = Array(String(format: "%02d", value))
        VStack(spacing: 3) {
            HStack(spacing: 0) {
                ForEach((0..<digits.count).reversed(), id: \.self) { place in
                    FlipDigit(digit: digits[digits.count - 1 - place], size: digit)
                }
            }
            .padding(.horizontal, digit * 0.3)
            .frame(height: height)
            .background(FlipCard())
            Text(label)
                .font(.hand(10, bold: true, relativeTo: .caption2))
                .textCase(.uppercase)
                .tracking(0.8)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
        }
        // Every unit as wide as the widest label, so the cards and colons
        // are evenly spaced whatever the word under them.
        .frame(width: digit * 3)
    }
}

private struct FlipDigit: View {
    let digit: Character
    let size: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Text(String(digit))
                .font(.system(size: size, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(DarkRoom.ink)
                .id(digit)
                // Under Reduce Motion, the new digit only fades in.
                .transition(reduceMotion ? .opacity : .flip)
        }
        .frame(width: size * 0.64)
        .animation(.easeInOut(duration: 0.3), value: digit)
    }
}

/// A flip clock's card: the atmosphere's card color on the page, a hairline
/// round it and a hairline across the middle where the card would split. In
/// the dark room, black boxed in the room's rule gray, like everything else.
private struct FlipCard: View {
    @AppStorage("stanley.atmosphere") private var raw = "auto"
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
        let dark = DarkRoom.isDark(colorScheme)
        let palette = Atmosphere.resolve(raw).palette
        let line = dark ? DarkRoom.line(1) : DarkRoom.line(0.12)
        ZStack {
            shape.fill(dark ? Color.clear : palette.floor)
            shape.fill(dark ? Color.clear : palette.card)
        }
        .overlay(shape.strokeBorder(line, lineWidth: 0.5))
        .overlay(Rectangle().fill(line).frame(height: 0.5))
    }
}

/// A digit tipping over on its middle: the old one rolls down and away and
/// fades, the new one rolls up into place, a little smaller while it turns.
private struct FlipTurn: ViewModifier {
    /// -1 still to come, 0 in place, 1 gone.
    let turn: Double

    func body(content: Content) -> some View {
        content
            .rotation3DEffect(.degrees(turn * 90), axis: (x: 1, y: 0, z: 0), anchor: .center, perspective: 0.5)
            .scaleEffect(1 - abs(turn) * 0.15)
            .opacity(1 - abs(turn))
    }
}

private extension AnyTransition {
    static var flip: AnyTransition {
        .asymmetric(
            insertion: .modifier(active: FlipTurn(turn: -1), identity: FlipTurn(turn: 0)),
            removal: .modifier(active: FlipTurn(turn: 1), identity: FlipTurn(turn: 0))
        )
    }
}

// MARK: - The route

/// The route itself: a shallow, slightly uneven arc, the way a flight path is
/// drawn on a map by hand.
private struct RouteSketch: View {
    static let height: CGFloat = 24
    let progress: Double

    var body: some View {
        GeometryReader { geo in
            let route = Route(width: geo.size.width, height: geo.size.height)
            let t = min(1, max(0, progress))
            ZStack {
                Path { path in
                    path.move(to: route.start)
                    path.addCurve(to: route.end, control1: route.c1, control2: route.c2)
                }
                .stroke(style: StrokeStyle(lineWidth: 1.1, lineCap: .round, dash: [0.1, 4.5]))
                Circle()
                    .frame(width: 4, height: 4)
                    .position(route.start)
                Circle()
                    .stroke(lineWidth: 1)
                    .frame(width: 7, height: 7)
                    .position(route.end)
                Image(systemName: "airplane")
                    .font(.system(size: 13, weight: .light))
                    .rotationEffect(route.heading(at: t))
                    .position(route.point(at: t))
            }
            .foregroundStyle(.secondary)
        }
        .frame(height: Self.height)
        .accessibilityHidden(true)
    }
}

/// A cubic from the origin dot to the destination, rising a little and
/// falling a little less, so it reads as drawn rather than plotted.
private struct Route {
    let start, c1, c2, end: CGPoint

    init(width: CGFloat, height: CGFloat) {
        start = CGPoint(x: 4, y: height - 5)
        c1 = CGPoint(x: width * 0.32, y: 0)
        c2 = CGPoint(x: width * 0.7, y: height * 0.12)
        end = CGPoint(x: width - 5, y: height - 7)
    }

    func point(at t: CGFloat) -> CGPoint {
        let u = 1 - t
        let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
        return CGPoint(
            x: a * start.x + b * c1.x + c * c2.x + d * end.x,
            y: a * start.y + b * c1.y + c * c2.y + d * end.y
        )
    }

    /// Which way the plane faces: along the route at `t`.
    func heading(at t: CGFloat) -> Angle {
        let u = 1 - t
        let dx = 3 * u * u * (c1.x - start.x) + 6 * u * t * (c2.x - c1.x) + 3 * t * t * (end.x - c2.x)
        let dy = 3 * u * u * (c1.y - start.y) + 6 * u * t * (c2.y - c1.y) + 3 * t * t * (end.y - c2.y)
        return .radians(atan2(dy, dx))
    }
}
