import SwiftUI
import UIKit

// The polish pass of build 39: small things that make the app feel made by
// hand. Each is quick (under a third of a second, or a slow idle), silent,
// and still under Reduce Motion. None changes what anything does.

// MARK: - Shimmer

/// A photo that hasn't arrived yet: its shape in the atmosphere's card
/// color, with a soft band of light sweeping across it, the way a print
/// catches a lamp. Still under Reduce Motion.
struct Shimmer: View {
    @AppStorage("stanley.atmosphere") private var raw = "auto"
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sweep = false

    var body: some View {
        let palette = Atmosphere.resolve(raw).palette
        let dark = colorScheme == .dark
        // The card's own color, a step off the page so the shape reads: a
        // little ink in daylight, a little light in the dark room.
        let base = dark ? Color.white.opacity(0.07) : Color.black.opacity(0.055)
        let glint = dark ? Color.white.opacity(0.10) : Color.white.opacity(0.65)
        GeometryReader { geo in
            ZStack {
                palette.card
                base
                if !reduceMotion {
                    LinearGradient(
                        colors: [.clear, glint, .clear],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 0.6)
                    .rotationEffect(.degrees(12))
                    .offset(x: (sweep ? 1 : -1) * geo.size.width * 0.9)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 1.25).repeatForever(autoreverses: false)) { sweep = true }
        }
        .accessibilityHidden(true)
    }
}

/// Today before its first answer: the shapes of a day's page, shimmering,
/// where the prints will be. Two prints and their lines, no words.
struct TodaySkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.section) {
            ForEach(0..<2, id: \.self) { index in
                VStack(alignment: .leading, spacing: 10) {
                    Color.clear
                        .aspectRatio(PhotoShape.aspect, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .overlay { Shimmer() }
                        .clipShape(RoundedRectangle(cornerRadius: PrintStock.photoCorner, style: .continuous))
                        .asPrint(tilt: index == 0 ? -0.5 : 0.6)
                    Shimmer()
                        .frame(width: 150, height: 14)
                        .clipShape(Capsule())
                    Shimmer()
                        .frame(width: 230, height: 12)
                        .clipShape(Capsule())
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading today's photos")
    }
}

// MARK: - The heart's burst

/// Four small hearts thrown out from the middle of a photo as the big one
/// blooms: up and outward, turning a little, gone in half a second. Played
/// once each time `trigger` changes. Nothing under Reduce Motion.
struct HeartBurst: View {
    let trigger: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Where each goes: an angle (up is -90°), how far, how big, and its turn.
    private static let hearts: [(angle: Double, reach: CGFloat, size: CGFloat, turn: Double)] = [
        (-142, 96, 22, -18),
        (-104, 118, 17, 10),
        (-68, 108, 20, 16),
        (-30, 92, 15, -12),
    ]

    var body: some View {
        if !reduceMotion {
            ZStack {
                ForEach(Array(Self.hearts.enumerated()), id: \.offset) { index, heart in
                    Image(systemName: "heart.fill")
                        .font(.system(size: heart.size))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.2), radius: 3)
                        .keyframeAnimator(initialValue: 0.0, trigger: trigger) { content, flight in
                            let angle = heart.angle * .pi / 180
                            content
                                .scaleEffect(0.5 + 0.6 * flight)
                                .rotationEffect(.degrees(heart.turn * flight))
                                .offset(
                                    x: cos(angle) * heart.reach * flight,
                                    y: sin(angle) * heart.reach * flight
                                )
                                // Nothing at rest, there at the start, gone by the end.
                                .opacity(flight <= 0 ? 0 : min(1, (1 - flight) * 2.2))
                        } keyframes: { _ in
                            KeyframeTrack {
                                // A beat behind the big heart, each a little
                                // after the last.
                                LinearKeyframe(0.001, duration: 0.06 + 0.03 * Double(index))
                                CubicKeyframe(1, duration: 0.46)
                            }
                        }
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

// MARK: - The sun that turns while a page refreshes

/// A small sun, sketched in one pen line like the app's icon: a ring a
/// little off true, and eight short rays of uneven length.
struct SketchedSun: View {
    var color: Color

    var body: some View {
        Canvas { context, size in
            let side = min(size.width, size.height)
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = side * 0.21
            let pen = StrokeStyle(lineWidth: max(1.3, side * 0.058), lineCap: .round, lineJoin: .round)
            // The ring, drawn by hand: its radius wavers, and the pen
            // overshoots where it meets itself.
            var ring = Path()
            let steps = 40
            for step in 0...(steps + 3) {
                let turn = Double(step) / Double(steps) * 2 * .pi - 0.4
                let wobble = 1 + 0.07 * sin(turn * 3 + 0.8) + 0.03 * cos(turn * 5)
                let point = CGPoint(
                    x: center.x + cos(turn) * radius * wobble,
                    y: center.y + sin(turn) * radius * wobble
                )
                if step == 0 { ring.move(to: point) } else { ring.addLine(to: point) }
            }
            context.stroke(ring, with: .color(color), style: pen)
            // Eight rays, none quite the same.
            let lengths: [CGFloat] = [0.15, 0.11, 0.16, 0.12, 0.14, 0.10, 0.16, 0.12]
            for (index, length) in lengths.enumerated() {
                let turn = Double(index) / 8 * 2 * .pi + 0.12 * sin(Double(index) * 2.1)
                let from = radius + side * 0.09
                var ray = Path()
                ray.move(to: CGPoint(x: center.x + cos(turn) * from, y: center.y + sin(turn) * from))
                ray.addLine(to: CGPoint(
                    x: center.x + cos(turn) * (from + side * length),
                    y: center.y + sin(turn) * (from + side * length)
                ))
                context.stroke(ray, with: .color(color), style: pen)
            }
        }
        .accessibilityHidden(true)
    }
}

enum SunRefresh {
    /// Whether the sun stands in for the system's spinner: where a pull can
    /// be followed (iOS 18 and up). Before that the spinner stays.
    static var replacesSpinner: Bool {
        if #available(iOS 18, *) { return true }
        return false
    }

    /// Called once at launch: where the sun turns instead, the system's
    /// spinner is drawn in no color at all.
    @MainActor
    static func prepare() {
        if replacesSpinner {
            UIRefreshControl.appearance().tintColor = .clear
        }
    }
}

extension View {
    /// Pull to refresh, with a small sketched sun that turns as you pull
    /// and keeps turning while the page reloads, in place of the system's
    /// spinner. The pull itself is the system's own (`refreshable`).
    func sunRefreshable(_ action: @escaping @MainActor @Sendable () async -> Void) -> some View {
        modifier(SunRefreshable(action: action))
    }
}

private struct SunRefreshable: ViewModifier {
    @AppStorage("stanley.atmosphere") private var raw = "auto"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let action: @MainActor @Sendable () async -> Void
    @State private var pull: CGFloat = 0
    @State private var refreshing = false

    func body(content: Content) -> some View {
        if #available(iOS 18, *) {
            content
                .refreshable {
                    refreshing = true
                    await action()
                    refreshing = false
                }
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    // How far the page has been pulled past its top.
                    max(0, -(geometry.contentOffset.y + geometry.contentInsets.top))
                } action: { _, distance in
                    pull = distance
                }
                .overlay(alignment: .top) { sun }
        } else {
            content.refreshable { await action() }
        }
    }

    @ViewBuilder
    private var sun: some View {
        let showing = refreshing || pull > 6
        if showing {
            // In the gap the pull opens, a little above its middle; held
            // where the page waits while it reloads.
            let gap = refreshing ? max(pull, 58) : pull
            TimelineView(.animation(paused: !refreshing || reduceMotion)) { timeline in
                let spin = refreshing && !reduceMotion
                    ? timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.4) / 2.4 * 360
                    : Double(pull) * 2.2
                SketchedSun(color: Atmosphere.resolve(raw).palette.accent)
                    .frame(width: 30, height: 30)
                    .rotationEffect(.degrees(spin))
            }
            .opacity(refreshing ? 1 : min(1, Double(pull) / 54))
            .scaleEffect(refreshing ? 1 : min(1, 0.6 + Double(pull) / 135))
            .offset(y: max(4, gap / 2 - 15))
            .allowsHitTesting(false)
            .transition(.opacity)
            .accessibilityHidden(true)
        }
    }
}

// MARK: - A page's corner, folded

/// A slip of paper's outline: barely rounded, and with `fold` its top-right
/// corner cut away on the diagonal where it's been folded over (the weekly
/// question, build 39). With no fold it's the plain slip every insert is.
struct SlipShape: Shape {
    var fold: CGFloat = 0
    var radius: CGFloat = 3

    func path(in rect: CGRect) -> Path {
        guard fold > 0 else {
            return Path(roundedRect: rect, cornerRadius: radius, style: .continuous)
        }
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + radius, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - fold, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + fold))
        path.addArc(
            tangent1End: CGPoint(x: rect.maxX, y: rect.maxY),
            tangent2End: CGPoint(x: rect.minX, y: rect.maxY), radius: radius
        )
        path.addArc(
            tangent1End: CGPoint(x: rect.minX, y: rect.maxY),
            tangent2End: CGPoint(x: rect.minX, y: rect.minY), radius: radius
        )
        path.addArc(
            tangent1End: CGPoint(x: rect.minX, y: rect.minY),
            tangent2End: CGPoint(x: rect.maxX, y: rect.minY), radius: radius
        )
        path.closeSubpath()
        return path
    }
}

/// The folded corner itself, lying back on the slip: the paper's underside,
/// a shade deeper, with a little shadow beneath it. In the dark room there's
/// no paper to fold, so it's the fold's two edges in the room's own rule.
struct FoldedCorner: View {
    @AppStorage("stanley.atmosphere") private var raw = "auto"
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let flap = Flap()
        Group {
            if DarkRoom.isDark(colorScheme) {
                flap.stroke(DarkRoom.line(1), lineWidth: 1)
            } else {
                flap
                    .fill(Atmosphere.resolve(raw).palette.floor)
                    .overlay(
                        flap.fill(
                            LinearGradient(
                                colors: [.black.opacity(0.11), .black.opacity(0.02)],
                                startPoint: .topTrailing, endPoint: .bottomLeading
                            )
                        )
                    )
                    .overlay(flap.stroke(DarkRoom.line(0.18), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.18), radius: 2.5, x: -1.5, y: 2)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The corner, mirrored across its fold line onto the slip.
    private struct Flap: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
            return path
        }
    }
}

// MARK: - A tab arriving, and the "+" asking

extension View {
    /// A tab's page fades in over the paper as it's chosen (0.15s), where
    /// the system swaps one for the next in a single frame.
    func tabFade(_ showing: Bool) -> some View {
        opacity(showing ? 1 : 0)
            .animation(.easeOut(duration: 0.15), value: showing)
    }

    /// A quiet invitation: every five seconds the view swells a little and
    /// a ring of its own color breathes out from it, while `asking` is
    /// true. Nothing under Reduce Motion.
    func gentlePulse(_ asking: Bool, color: Color) -> some View {
        modifier(GentlePulse(asking: asking, color: color))
    }
}

private struct GentlePulse: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let asking: Bool
    let color: Color
    @State private var beats = 0

    func body(content: Content) -> some View {
        content
            .keyframeAnimator(initialValue: 0.0, trigger: beats) { view, beat in
                view
                    .scaleEffect(1 + 0.12 * beat)
                    .background {
                        Circle()
                            .stroke(color.opacity(0.35 * beat), lineWidth: 1)
                            .scaleEffect(0.55 + 0.35 * beat)
                    }
            } keyframes: { _ in
                KeyframeTrack {
                    CubicKeyframe(1, duration: 0.45)
                    CubicKeyframe(0, duration: 0.75)
                }
            }
            .task(id: asking && !reduceMotion) {
                guard asking, !reduceMotion else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(5))
                    if Task.isCancelled { break }
                    beats += 1
                }
            }
    }
}
