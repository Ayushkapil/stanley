import SwiftUI

/// One circle's countdown under Today's dateline (build 35): a route sketched
/// on a paper map. A dotted path edge to edge, a dot where it starts, a ring
/// where it ends, and a small plane along it by how much of the wait has
/// passed; once landed, a house where the route was. Under it, in a hand,
/// where things stand. Thin strokes in the page's secondary ink, a nod rather
/// than a banner, and not a control: nothing here can be tapped.
///
/// Drawn only for the circle the server flagged (`CircleInfo.countdown`);
/// every other circle never sees it.
struct CountdownRoute: View {
    let countdown: Countdown

    var body: some View {
        // Read again each minute, so a page left open crosses midnight into
        // the next phase on its own. The plane moves too little to see.
        TimelineView(.everyMinute) { context in
            if let phase = countdown.phase(at: context.date) {
                VStack(spacing: 4) {
                    switch phase.mark {
                    case .plane(let progress):
                        RouteSketch(progress: progress)
                    case .home:
                        Text("🏠")
                            .font(.system(size: 15))
                            .frame(height: RouteSketch.height)
                    }
                    Text(phase.text)
                        .font(.hand(16, relativeTo: .subheadline))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 2)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(phase.text)
            }
        }
    }
}

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
