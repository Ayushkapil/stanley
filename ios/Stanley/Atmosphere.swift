import SwiftUI
import UIKit

/// Seasonal atmosphere (Part 5): an ambient color-temperature shift, never a
/// skin. It tints accents, the tab bar, card surfaces, and the floor under
/// everything — and nothing else. It never affects feed order, visibility, or
/// any functionality. Every palette reads in both light and dark mode, and the
/// five are meant to be told apart at a glance — golden, copper, icy, sage,
/// fog — so a person knows which one is on without opening Settings.
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
        /// What sits *on* an accent fill — a prominent button's label. White
        /// only where the accent is deep enough to carry it (Fall); the rest
        /// use a dark ink of their own hue, so the control stays on-theme and
        /// stays legible.
        let ink: Color
        /// The opaque surface under everything: the room's temperature. The
        /// system background with the atmosphere's tone blended in — tinted
        /// paper in light mode, a lifted black in dark. Opaque on purpose: the
        /// root and each screen both paint it, and the same opaque color
        /// painted twice is one color, not a darker band where they overlap.
        let floor: Color
        /// Laid over a card's base fill, so cards carry the temperature too
        /// instead of reading as neutral gray cut-outs on a tinted floor.
        let card: Color
    }

    var palette: Palette {
        switch self {
        case .spring:   // soft sage, fresh mint, a little warmth
            return .make(accent: 0x8CB87B, ink: 0x16291A, tone: 0x8CB87B,
                         floor: (light: 0.14, dark: 0.16), card: (light: 0.09, dark: 0.10))
        case .warm:     // golden amber, summer
            return .make(accent: 0xF2B24A, ink: 0x3A2808, tone: 0xF0BE50,
                         floor: (light: 0.16, dark: 0.18), card: (light: 0.10, dark: 0.10))
        case .fall:     // deep copper, burnt orange, rich brown
            return .make(accent: 0xB85C2C, ink: 0xFFF4EA, tone: 0xC45A30,
                         floor: (light: 0.13, dark: 0.17), card: (light: 0.09, dark: 0.11))
        case .cool:     // slate blue, icy silver, cold gray
            return .make(accent: 0x7B9EB8, ink: 0x0F1E2C, tone: 0x6D9BC4,
                         floor: (light: 0.16, dark: 0.18), card: (light: 0.09, dark: 0.10))
        case .rain:     // blue-gray, desaturated, foggy, low contrast
            return .make(accent: 0x8899AA, ink: 0x1B2229, tone: 0x949CA4,
                         floor: (light: 0.24, dark: 0.26), card: (light: 0.05, dark: 0.06))
        case .auto:
            return Atmosphere.seasonNow.palette
        }
    }

    /// The current real-world season as a concrete atmosphere, by hemisphere.
    static var seasonNow: Atmosphere {
        let month = Calendar.current.component(.month, from: Date())
        let northern = !isSouthernHemisphere(TimeZone.current.identifier)
        // Northern mapping; southern is shifted by six months.
        let m = northern ? month : ((month + 5) % 12) + 1
        switch m {
        case 3...5: return .spring
        case 6...8: return .warm
        case 9...11: return .fall
        default: return .cool   // Dec–Feb
        }
    }

    /// Coarse hemisphere guess from the timezone identifier's region.
    static func isSouthernHemisphere(_ tz: String) -> Bool {
        let south = [
            "Australia/", "Pacific/Auckland", "Pacific/Chatham", "Antarctica/",
            "America/Argentina", "America/Sao_Paulo", "America/Santiago",
            "America/La_Paz", "America/Asuncion", "America/Montevideo", "America/Lima",
            "Africa/Johannesburg", "Africa/Windhoek", "Africa/Maputo", "Africa/Harare",
            "Indian/", "Pacific/Fiji", "Pacific/Port_Moresby",
        ]
        return south.contains { tz.hasPrefix($0) || tz == $0 }
    }

    static func resolve(_ raw: String) -> Atmosphere {
        Atmosphere(rawValue: raw) ?? .auto
    }
}

extension Atmosphere.Palette {
    /// `tone` is the hue the floor and cards are tinted with — near the
    /// accent, but free to lean where the accent cannot: Warm's floor goes
    /// more golden and Fall's more red so the two browns stay apart in dark
    /// mode; Cool's goes bluer and Rain's grayer so ice and fog do too. The
    /// opacities say how much of it goes into each surface, per mode: dark
    /// needs a little more to lift black at all.
    static func make(
        accent: UInt32, ink: UInt32, tone: UInt32,
        floor: (light: CGFloat, dark: CGFloat),
        card: (light: CGFloat, dark: CGFloat)
    ) -> Self {
        let tone = UIColor(hex: tone)
        return Self(
            accent: Color(uiColor: UIColor(hex: accent)),
            ink: Color(uiColor: UIColor(hex: ink)),
            floor: adaptive(
                light: UIColor.white.blended(toward: tone, by: floor.light),
                dark: UIColor.black.blended(toward: tone, by: floor.dark)
            ),
            card: adaptive(
                light: tone.withAlphaComponent(card.light),
                dark: tone.withAlphaComponent(card.dark)
            )
        )
    }

    private static func adaptive(light: UIColor, dark: UIColor) -> Color {
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
}

/// The atmosphere picker: one row of named pills, the way iOS reads a row of
/// filters. The one that is on wears its own accent, with the palette's ink
/// for the word; the others are quiet capsules. Nothing else is drawn — no
/// swatch, no checkmark — the chosen pill's color is the swatch. All six
/// share one row wherever they fit; where they cannot (a large text size),
/// the row scrolls and opens with the chosen one in view, so the one that
/// is on is never the one hidden.
struct AtmosphereChips: View {
    @Binding var selection: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Atmosphere")
            ViewThatFits(in: .horizontal) {
                pills
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        pills
                    }
                    // Run under the row's own margins rather than stopping
                    // at them, so a pill half out of view reads as scrolled,
                    // not clipped.
                    .contentMargins(.horizontal, 20, for: .scrollContent)
                    .padding(.horizontal, -20)
                    .onAppear { proxy.scrollTo(selection, anchor: .center) }
                }
            }
            .padding(.vertical, 2)
            .animation(.easeInOut(duration: 0.2), value: selection)
        }
    }

    private var pills: some View {
        HStack(spacing: 4) {
            ForEach(Atmosphere.allCases) { atmosphere in
                pill(atmosphere).id(atmosphere.rawValue)
            }
        }
    }

    private func pill(_ atmosphere: Atmosphere) -> some View {
        let palette = atmosphere.palette
        let on = selection == atmosphere.rawValue
        return Button {
            selection = atmosphere.rawValue
        } label: {
            Text(atmosphere.label)
                .font(.footnote.weight(.medium))
                .lineLimit(1)
                .foregroundStyle(on ? palette.ink : Color.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Capsule().fill(on ? palette.accent : Color(.tertiarySystemFill)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(atmosphere.label)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
