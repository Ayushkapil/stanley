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
        /// What sits *on* an accent fill — a prominent button's label, the
        /// chosen pill's name. White only where the accent is deep enough to
        /// carry it (Fall, in light mode); everywhere else a dark ink of the
        /// accent's own hue, so the control stays on-theme and stays legible.
        let ink: Color
        /// The opaque surface under everything: the room's temperature. The
        /// system background with the atmosphere's tone blended in — tinted
        /// paper in light mode, a lifted black in dark. Opaque on purpose: the
        /// root and each screen both paint it, and the same opaque color
        /// painted twice is one color, not a darker band where they overlap.
        let floor: Color
        /// Laid over a card's base fill, so cards carry the temperature too
        /// instead of reading as neutral gray cut-outs on a tinted floor.
        /// Opaque in dark mode: the card *is* this color.
        let card: Color
        /// Behind the rows of a grouped list (Settings, the edit sheets). The
        /// system's own row color in light mode; in dark, the card, so a
        /// screen of rows is in the same room as Today.
        let row: Color
    }

    var palette: Palette {
        switch self {
        // Light mode is the system's white with the tone blended in. Dark
        // mode is chosen outright: an accent with the saturation to read on
        // near-black, a deep floor of the mood's own hue, a card one step up.
        case .spring:   // light: soft sage, fresh mint · dark: deep sage, emerald
            return .make(
                light: .init(accent: 0x8CB87B, ink: 0x16291A, tone: 0x8CB87B, floor: 0.14, card: 0.09),
                dark: .init(accent: 0x6CC48E, ink: 0x0A2414, floor: 0x0A1710, card: 0x13291D))
        case .warm:     // light: golden amber, summer · dark: candlelight
            return .make(
                light: .init(accent: 0xF2B24A, ink: 0x3A2808, tone: 0xF0BE50, floor: 0.16, card: 0.10),
                dark: .init(accent: 0xFFB53D, ink: 0x2E1C02, floor: 0x1F1708, card: 0x3B2C11))
        case .fall:     // light: deep copper, burnt orange · dark: terracotta, ember
            return .make(
                light: .init(accent: 0xB85C2C, ink: 0xFFF4EA, tone: 0xC45A30, floor: 0.13, card: 0.09),
                dark: .init(accent: 0xE8773D, ink: 0x2B0F03, floor: 0x1D0D07, card: 0x351A0F))
        case .cool:     // light: slate blue, icy silver · dark: ice on deep navy
            return .make(
                light: .init(accent: 0x7B9EB8, ink: 0x0F1E2C, tone: 0x6D9BC4, floor: 0.16, card: 0.09),
                dark: .init(accent: 0x96D0F6, ink: 0x08203A, floor: 0x08111C, card: 0x122133))
        case .rain:     // light: blue-gray fog · dark: slate, through a wet window
            return .make(
                light: .init(accent: 0x8899AA, ink: 0x1B2229, tone: 0x949CA4, floor: 0.24, card: 0.05),
                dark: .init(accent: 0xA2B5C8, ink: 0x141B23, floor: 0x12161B, card: 0x1D242C))
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
    /// Light mode, mixed: `tone` is the hue the floor and cards are tinted
    /// with — near the accent, but free to lean where the accent cannot (Warm
    /// more golden, Fall more red, Cool bluer, Rain grayer) so neighbours stay
    /// apart. `floor` and `card` say how much of it goes into each surface.
    struct Light {
        let accent: UInt32, ink: UInt32, tone: UInt32
        let floor: CGFloat, card: CGFloat
    }

    /// Dark mode, chosen. Black mixed toward a pale tone comes out gray-olive
    /// for gold and brownish-gray for copper — a tint on black, not a mood —
    /// so each surface is named outright instead.
    struct Dark {
        let accent: UInt32, ink: UInt32, floor: UInt32, card: UInt32
    }

    static func make(light: Light, dark: Dark) -> Self {
        let tone = UIColor(hex: light.tone)
        let darkCard = UIColor(hex: dark.card)
        return Self(
            accent: adaptive(light: UIColor(hex: light.accent), dark: UIColor(hex: dark.accent)),
            ink: adaptive(light: UIColor(hex: light.ink), dark: UIColor(hex: dark.ink)),
            floor: adaptive(
                light: UIColor.white.blended(toward: tone, by: light.floor),
                dark: UIColor(hex: dark.floor)
            ),
            card: adaptive(light: tone.withAlphaComponent(light.card), dark: darkCard),
            row: adaptive(light: .secondarySystemGroupedBackground, dark: darkCard)
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

/// The atmosphere picker: one row of named pills, the way iOS reads a row of
/// filters. The one that is on wears its own accent, with the palette's ink
/// for the word; the others are quiet capsules. Nothing else is drawn — no
/// swatch, no checkmark — the chosen pill's color is the swatch. All six
/// share one row wherever they fit; where they cannot (a large text size),
/// the row scrolls and opens with the chosen one in view, so the one that
/// is on is never the one hidden.
struct AtmosphereChips: View {
    @Binding var selection: String
    @Environment(\.colorScheme) private var colorScheme

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
        .accessibilityLabel(atmosphere.label)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
