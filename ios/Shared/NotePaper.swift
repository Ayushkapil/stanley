import SwiftUI

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

/// A slip's outline: straight across the top where it was cut and down the
/// sides, ragged along the bottom where it was torn off. The tears are its
/// own, from the seed, so a note keeps its edge.
struct TornEdge: Shape {
    let seed: UInt32

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - 2))
        var state = seed | 1
        var x = rect.maxX
        while x > rect.minX {
            // xorshift: a tooth every 3 to 6pt, up to 3pt deep.
            state ^= state << 13; state ^= state >> 17; state ^= state << 5
            x = max(rect.minX, x - CGFloat(3 + state % 4))
            let depth = CGFloat((state >> 8) % 31) / 10
            path.addLine(to: CGPoint(x: x, y: rect.maxY - depth))
        }
        path.closeSubpath()
        return path
    }
}
