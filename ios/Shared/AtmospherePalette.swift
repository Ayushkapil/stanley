import SwiftUI
import UIKit

/// The atmosphere: the room Stanley is in. Since the Quiet Warmth pass
/// (build 44) there are two palettes and three looks. The plain one is
/// Stanley's own: warm white (#FAFAF7), white cards edged in a warm
/// hairline, a warm charcoal accent in daylight; true black with a warm
/// white accent in the dark, the gallery. Rain is the one mood pilot users
/// kept: fog on a window, a muted blue-gray, in light and dark both.
/// Settings offers Light, Dark and Rain (`Look`, in the app), or matching
/// the phone, which is the default. Spring, Warm, Fall and Cool are gone;
/// a phone that had one chosen reads as plain.
///
/// It never affects feed order, visibility, or anything Stanley does.
enum Atmosphere: String, Identifiable {
    /// Stored as "auto", the name the default has always had, so a phone
    /// that never chose (and the widget's snapshot) reads the same.
    case plain = "auto"
    case rain
    var id: String { rawValue }

    /// The colors an atmosphere is made of.
    struct Palette {
        /// Everything `.tint` reaches: the tab bar, buttons, bookmarks, edges.
        let accent: Color
        /// What sits *on* an accent fill: a prominent button's label.
        let ink: Color
        /// The opaque surface under everything. Opaque on purpose: the root
        /// and each screen both paint it, and the same opaque color painted
        /// twice is one color, not a darker band where they overlap.
        let floor: Color
        /// A card's fill in daylight. In the dark there are no cards:
        /// content sits on the black, and this is the floor again.
        let card: Color
        /// The hairline round a card or a photo in daylight (0.5pt); in the
        /// dark, the faint light edge of an interactive surface.
        let edge: Color
        /// Behind the rows of a grouped list (Settings, the edit sheets).
        let row: Color
        /// An on switch. The accent, except where the accent is near white
        /// (the plain look in the dark), which would hide the switch's knob.
        let toggle: Color
    }

    var palette: Palette {
        switch self {
        case .plain: return .plain
        case .rain: return .rain
        }
    }

    static func resolve(_ raw: String) -> Atmosphere {
        Atmosphere(rawValue: raw) ?? .plain
    }
}

extension Atmosphere.Palette {
    /// One step up from black, for the rows of a grouped list in the dark.
    private static let darkRow = UIColor(hex: 0x1A1A1A)

    /// Light and Dark: warm white and white cards; true black.
    static let plain = Self(
        accent: adaptive(light: UIColor(hex: 0x5C5550), dark: UIColor(hex: 0xF0EBE3)),
        ink: adaptive(light: UIColor(hex: 0xFAFAF7), dark: UIColor(hex: 0x141414)),
        floor: adaptive(light: UIColor(hex: 0xFAFAF7), dark: .black),
        card: adaptive(light: .white, dark: .black),
        edge: adaptive(light: UIColor(hex: 0xE8E5E0), dark: UIColor.white.withAlphaComponent(0.10)),
        row: adaptive(light: .white, dark: darkRow),
        toggle: adaptive(light: UIColor(hex: 0x5C5550), dark: .systemGreen)
    )

    /// Rain: fog on a window. A muted blue-gray page with paler cards in
    /// daylight; in the dark still black (pilot users called colored dark
    /// floors artificial), with the fog in the accent and the rows.
    static let rain = Self(
        accent: adaptive(light: UIColor(hex: 0x5B6B7D), dark: UIColor(hex: 0xAAB8C9)),
        ink: adaptive(light: UIColor(hex: 0xF7F9FA), dark: UIColor(hex: 0x141B23)),
        floor: adaptive(light: UIColor(hex: 0xE9ECEF), dark: .black),
        card: adaptive(light: UIColor(hex: 0xF8F9FA), dark: .black),
        edge: adaptive(light: UIColor(hex: 0xD6DBE1), dark: UIColor(hex: 0xAAB8C9).withAlphaComponent(0.14)),
        row: adaptive(light: UIColor(hex: 0xF8F9FA), dark: darkRow.blended(toward: UIColor(hex: 0xAAB8C9), by: 0.05)),
        toggle: adaptive(light: UIColor(hex: 0x5B6B7D), dark: UIColor(hex: 0x8496AA))
    )

    fileprivate static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }
}

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }

    private var rgb: (r: CGFloat, g: CGFloat, b: CGFloat) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r, g, b)
    }

    /// An opaque mix: this color with `amount` of `other` laid over it.
    func blended(toward other: UIColor, by amount: CGFloat) -> UIColor {
        let from = rgb, to = other.rgb
        return UIColor(
            red: from.r + (to.r - from.r) * amount,
            green: from.g + (to.g - from.g) * amount,
            blue: from.b + (to.b - from.b) * amount,
            alpha: 1
        )
    }
}
