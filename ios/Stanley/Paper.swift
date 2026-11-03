import SwiftUI
import UIKit

/// Paper, not a flat fill (build 19). A fine, uneven grain of light and dark
/// specks with a few faint fibres, drawn once into a small tile and repeated,
/// so it costs nothing to scroll over. It's subtle on purpose: a page you
/// notice is paper only if you look. Used behind a member's profile page and
/// on the sticky note.
enum PaperGrain {
    static let tile: UIImage = {
        let size = CGSize(width: 180, height: 180)
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = 2
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let cg = ctx.cgContext
            // The same grain on every launch and every phone.
            var rng = SplitMix64(seed: 0x5354_414E_4C45_59)
            for _ in 0..<1600 {
                let r = 0.35 + rng.unit() * 0.8
                let rect = CGRect(x: rng.unit() * size.width, y: rng.unit() * size.height, width: r, height: r)
                let tone: UIColor = rng.unit() < 0.55 ? .black : .white
                cg.setFillColor(tone.withAlphaComponent(0.10 + rng.unit() * 0.22).cgColor)
                cg.fillEllipse(in: rect)
            }
            // Fibres: short, faint, lying every which way.
            cg.setLineWidth(0.35)
            for _ in 0..<36 {
                let x = rng.unit() * size.width, y = rng.unit() * size.height
                let angle = rng.unit() * .pi * 2, length = 3 + rng.unit() * 7
                cg.setStrokeColor(UIColor.black.withAlphaComponent(0.07).cgColor)
                cg.move(to: CGPoint(x: x, y: y))
                cg.addLine(to: CGPoint(x: x + cos(angle) * length, y: y + sin(angle) * length))
                cg.strokePath()
            }
        }
    }()
}

/// A small seeded generator, so the grain (and anything else drawn "by
/// hand") is the same every time rather than shimmering between launches.
struct SplitMix64 {
    private var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// A number from 0 up to 1.
    mutating func unit() -> CGFloat {
        CGFloat(next() >> 11) / CGFloat(1 << 53)
    }
}

/// The grain itself, laid over a surface. `strength` is its opacity. In the
/// dark room (build 24) there is no paper, so in dark mode it draws nothing,
/// wherever it's laid.
struct PaperGrainView: View {
    @Environment(\.colorScheme) private var colorScheme
    var strength: Double = 0.5

    var body: some View {
        Image(uiImage: PaperGrain.tile)
            .resizable(resizingMode: .tile)
            .opacity(DarkRoom.isDark(colorScheme) ? 0 : strength)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

extension View {
    /// A screen that's a page of the journal: the atmosphere's card color with
    /// the paper's grain, edge to edge, instead of the flat floor. With `card`
    /// off it's the floor itself with the grain (the morning paper).
    func paperPage(card: Bool = true) -> some View { modifier(PaperPage(card: card)) }
}

private struct PaperPage: ViewModifier {
    @AppStorage("stanley.atmosphere") private var raw = "auto"
    @Environment(\.colorScheme) private var colorScheme
    let card: Bool

    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background {
                ZStack {
                    let palette = Atmosphere.resolve(raw).palette
                    card ? palette.card : palette.floor
                    PaperGrainView(strength: 0.45)
                }
                .ignoresSafeArea()
            }
    }
}
