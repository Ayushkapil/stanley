import SwiftUI
import UIKit

/// The atmosphere: an ambient color temperature, never a skin. It tints
/// accents, the tab bar, card surfaces and the floor under everything, and
/// nothing else. It never affects feed order, visibility, or anything Stanley
/// does.
///
/// Neutral by default, personality by choice. Auto is Stanley's own quiet
/// look: warm paper and white cards in light mode, true black in dark, with a
/// charcoal or warm-white accent. The five moods (Spring, Warm, Fall, Cool,
/// Rain) are picked in Settings. In light mode each mixes its tone into the
/// floor and cards. In dark mode the tone is only a hint, about 5% over black,
/// because pilot users found the colored floors of build 10 to 15 artificial:
/// a dark mood is black with a little warmth or cool in it, and its color
/// lives in the accent.
enum Atmosphere: String, CaseIterable, Identifiable {
    case auto, spring, warm, fall, cool, rain
    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: return "Auto"
        case .spring: return "Spring"
        case .warm: return "Warm"
        case .fall: return "Fall"
        case .cool: return "Cool"
        case .rain: return "Rain"
        }
    }

    /// The colors an atmosphere is made of.
    struct Palette {
        /// Everything `.tint` reaches: the tab bar, buttons, bookmarks, edges.
        let accent: Color
        /// What sits *on* an accent fill: a prominent button's label, the
        /// chosen pill's name. White only where the accent is deep enough to
        /// carry it (Fall, in light mode); everywhere else a dark ink of the
        /// accent's own hue, so the control stays on-theme and stays legible.
        let ink: Color
        /// The opaque surface under everything: the room's temperature. Opaque
        /// on purpose: the root and each screen both paint it, and the same
        /// opaque color painted twice is one color, not a darker band where
        /// they overlap.
        let floor: Color
        /// Laid over a card's base fill, so cards carry the temperature too
        /// instead of reading as neutral gray cut-outs on a tinted floor.
        /// Opaque in dark mode, and in Auto's light mode: the card *is* this
        /// color.
        let card: Color
        /// Behind the rows of a grouped list (Settings, the edit sheets). The
        /// system's own row color in light mode; in dark, the card, so a
        /// screen of rows is in the same room as Today.
        let row: Color
        /// An on switch. The accent, except where the accent is near white
        /// (Auto in dark mode), which would hide the switch's white knob.
        let toggle: Color
    }

    var palette: Palette {
        switch self {
        case .auto:
            return .neutral
        // Light mode is the system's white with the tone blended in. Dark
        // mode is black with about 5% of the tone, and the accent carries
        // the mood. The hues are shifted slightly off the obvious choice
        // (warm sits in honey not amber, spring in moss not mint, fall in
        // terracotta not pumpkin, cool in slate not sky) so neighbours
        // don't blur into one and no mood reads as a stock color.
        case .spring:   // light: moss on linen · dark: new growth over black
            return .make(
                light: .init(accent: 0x7CA368, ink: 0x1E2E17, tone: 0xA6C294, floor: 0.14, card: 0.09),
                dark: .init(accent: 0x86C892, ink: 0x0A2414, tone: 0x86C892, floor: 0.05, card: 0.06))
        case .warm:     // light: honey, late afternoon · dark: candlelight
            return .make(
                light: .init(accent: 0xC98A2E, ink: 0x3A2608, tone: 0xE2B069, floor: 0.18, card: 0.11),
                dark: .init(accent: 0xE8A94B, ink: 0x2E1C02, tone: 0xE8A94B, floor: 0.06, card: 0.07))
        case .fall:     // light: wet brick, terracotta · dark: ember on black
            return .make(
                light: .init(accent: 0xAC4521, ink: 0xFBF0E2, tone: 0xC96234, floor: 0.10, card: 0.08),
                dark: .init(accent: 0xE27A3D, ink: 0x2B0F03, tone: 0xE27A3D, floor: 0.05, card: 0.06))
        case .cool:     // light: slate, winter sky at dusk · dark: starlight
            return .make(
                light: .init(accent: 0x4F7A9F, ink: 0x0C1D2E, tone: 0x6E96BD, floor: 0.13, card: 0.09),
                dark: .init(accent: 0x91C8EF, ink: 0x08203A, tone: 0x91C8EF, floor: 0.05, card: 0.06))
        case .rain:     // light: fog on a window · dark: petrichor
            return .make(
                light: .init(accent: 0x627284, ink: 0x1A2028, tone: 0x8291A1, floor: 0.20, card: 0.06),
                dark: .init(accent: 0xAAB8C9, ink: 0x141B23, tone: 0xAAB8C9, floor: 0.03, card: 0.04))
        }
    }

    static func resolve(_ raw: String) -> Atmosphere {
        Atmosphere(rawValue: raw) ?? .auto
    }
}

extension Atmosphere.Palette {
    /// Light mode, mixed: `tone` is the hue the floor and cards are tinted
    /// with — near the accent, but free to lean where the accent cannot (Warm
    /// more golden, Fall more red, Cool bluer, Rain grayer) so neighbours stay
    /// apart. `floor` and `card` say how much of it goes into each surface.
    struct Light {
        let accent: UInt32, ink: UInt32, tone: UInt32
        let floor: CGFloat, card: CGFloat
    }

    /// Dark mode: black with a hint of `tone`. `floor` and `card` say how
    /// much of it goes over black and over the neutral card, a few percent
    /// at most.
    struct Dark {
        let accent: UInt32, ink: UInt32, tone: UInt32
        let floor: CGFloat, card: CGFloat
    }

    /// Dark mode's neutral surfaces, before any tone: true black, and a card
    /// one step up from it.
    private static let darkFloor = UIColor(hex: 0x000000)
    private static let darkCard = UIColor(hex: 0x1A1A1A)

    static func make(light: Light, dark: Dark) -> Self {
        let tone = UIColor(hex: light.tone)
        let darkTone = UIColor(hex: dark.tone)
        let card = darkCard.blended(toward: darkTone, by: dark.card)
        let accent = adaptive(light: UIColor(hex: light.accent), dark: UIColor(hex: dark.accent))
        return Self(
            accent: accent,
            ink: adaptive(light: UIColor(hex: light.ink), dark: UIColor(hex: dark.ink)),
            floor: adaptive(
                light: UIColor.white.blended(toward: tone, by: light.floor),
                dark: darkFloor.blended(toward: darkTone, by: dark.floor)
            ),
            card: adaptive(light: tone.withAlphaComponent(light.card), dark: card),
            row: adaptive(light: .secondarySystemGroupedBackground, dark: card),
            toggle: accent
        )
    }

    /// Auto: warm paper and white cards in light mode, true black and a card
    /// one step up in dark. The accent is warm charcoal in light and warm
    /// white in dark, so the tab bar and buttons are black and white with a
    /// little warmth, and nothing else is tinted. A white accent would hide
    /// a switch's white knob, so in dark mode switches keep the system green.
    static let neutral: Self = {
        let card = adaptive(light: .white, dark: darkCard)
        return Self(
            accent: adaptive(light: UIColor(hex: 0x2A2621), dark: UIColor(hex: 0xEFE6D4)),
            ink: adaptive(light: UIColor(hex: 0xFAF6EB), dark: UIColor(hex: 0x141414)),
            floor: adaptive(light: UIColor(hex: 0xF6F0E4), dark: darkFloor),
            card: card,
            row: card,
            toggle: adaptive(light: UIColor(hex: 0x2A2621), dark: .systemGreen)
        )
    }()

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

/// Paint the atmosphere's floor behind a scrolling surface.
struct AtmosphereWash: ViewModifier {
    @AppStorage("stanley.atmosphere") private var raw = "auto"
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(Atmosphere.resolve(raw).palette.floor.ignoresSafeArea())
    }
}

/// A card's fill: the system's hierarchical shade with the atmosphere's tone
/// laid over it, so a card is the same temperature as the floor it sits on.
/// Every card in Today uses this, so they all shift together.
struct CardSurface: ViewModifier {
    @AppStorage("stanley.atmosphere") private var raw = "auto"
    let corner: CGFloat
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: corner)
        content.background {
            shape.fill(.quinary)
                .overlay(shape.fill(Atmosphere.resolve(raw).palette.card))
        }
    }
}

/// Grouped-list rows in the room's color: the system's own row color in light
/// mode, the card in dark — so Settings and the edit sheets are in the same
/// room as Today instead of neutral gray slabs on a colored floor. Put it on
/// the sections (or a Group of them), not on the List.
struct AtmosphereRows: ViewModifier {
    @AppStorage("stanley.atmosphere") private var raw = "auto"
    func body(content: Content) -> some View {
        content.listRowBackground(Atmosphere.resolve(raw).palette.row)
    }
}

/// The label of a control filled with the accent. Put it on the label content
/// of a `.borderedProminent` button so the text reads on every atmosphere —
/// white on golden amber does not.
struct AccentInk: ViewModifier {
    @AppStorage("stanley.atmosphere") private var raw = "auto"
    func body(content: Content) -> some View {
        content.foregroundStyle(Atmosphere.resolve(raw).palette.ink)
    }
}

extension View {
    func atmosphereWash() -> some View { modifier(AtmosphereWash()) }
    func cardSurface(corner: CGFloat) -> some View { modifier(CardSurface(corner: corner)) }
    func accentInk() -> some View { modifier(AccentInk()) }
    func atmosphereRows() -> some View { modifier(AtmosphereRows()) }
}

/// One named pill in a row of choices. The one that is on wears the
/// palette's accent with its ink for the word; the others are quiet
/// capsules. The capture filters are a row of these.
struct ChoicePill: View {
    let label: String
    let on: Bool
    let palette: Atmosphere.Palette
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.footnote.weight(.medium))
                .lineLimit(1)
                .foregroundStyle(on ? palette.ink : Color.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background {
                    ZStack {
                        Capsule().fill(on ? palette.accent : Color(.tertiarySystemFill))
                        // A gray fill all but vanishes into a dark, tinted
                        // row. A hairline keeps every pill a shape you can
                        // find; light mode needs none.
                        if !on && colorScheme == .dark {
                            Capsule().strokeBorder(.white.opacity(0.2), lineWidth: 1)
                        }
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
