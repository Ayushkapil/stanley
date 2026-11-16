import SwiftUI
import UIKit

// The atmosphere's colors are in `Shared/AtmospherePalette.swift`, where the
// home screen widget reads them too (build 40). What follows is the words'
// colors (build 57), and how the app lays the palette on its own screens.
// Shared with the widget since build 57, so its words are the same inks.

/// The words' colors, everywhere (build 57, from the brief of 2026-11-14):
/// warm and ink-like in both rooms. In daylight a near black and a warm
/// gray, as they were; at night the same idea inverted, a warm off-white
/// and a warm gray, so nothing is ever #FFFFFF. Every screen takes them
/// through `darkRoomInk()` at its root; `DarkRoom.ink`, `.quiet` and
/// `.quietest` are these.
enum TextTone {
    private static func tone(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? rgb(dark) : rgb(light) })
    }

    static func rgb(_ hex: UInt32, alpha: CGFloat = 1) -> UIColor {
        UIColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha
        )
    }

    /// The words: #1A1A1A by day, #F2EADC at night.
    static let primary = tone(0x1A1A1A, 0xF2EADC)
    /// The quieter words: #6F6A65 by day, #ABA294 at night. (By day it was
    /// the brief's #8A8580 until build 67, about 3.5:1 on the page; the
    /// accessibility audit failed every dateline on it. #6F6A65 is the same
    /// warm gray at 4.5:1 or more on every daylight paper: 5.0 on the
    /// book's page, 5.1 on the floor, 5.4 on a card, 4.5 on Rain's floor.
    /// At night #ABA294 is 8.3:1 on black and was never short.)
    static let secondaryDay: UInt32 = 0x6F6A65
    static let secondaryNight: UInt32 = 0xABA294
    static let secondaryUI = UIColor { $0.userInterfaceStyle == .dark ? rgb(secondaryNight) : rgb(secondaryDay) }
    static let secondary = Color(secondaryUI)
    /// Quieter still, a placeholder or a hint: #B5B1AC by day, #6E675D at
    /// night.
    static let tertiary = tone(0xB5B1AC, 0x6E675D)
    /// Small capitals and labels set over the room: the words at 70% at
    /// night, the quieter words by day.
    static let label = Color(UIColor {
        $0.userInterfaceStyle == .dark ? rgb(0xF2EADC, alpha: 0.7) : rgb(secondaryDay)
    })
    /// Words laid on a photograph, in either room (the cover's title, a
    /// held photo's caption): the warm off-white, never pure white.
    static let onPhoto = Color(rgb(0xF2EADC))
    /// Small capitals on a photograph: that at 70%.
    static let onPhotoLabel = Color(rgb(0xF2EADC, alpha: 0.7))
}

/// The journal's covers (build 57: their colors are here, not in the
/// cover's own code).
enum CoverTone {
    /// The slab's glass: a little white by day, less at night, where
    /// material over black goes muddy and the edge carries it.
    static func slab(_ scheme: ColorScheme) -> Color { .white.opacity(scheme == .dark ? 0.08 : 0.2) }
    /// The slab's edge: a thin line of the words' off-white.
    static let edge = TextTone.onPhoto.opacity(0.55)
    /// The sheen across the slab's top left.
    static let sheen = TextTone.onPhoto.opacity(0.4)
    /// The hairline at the slab's foot.
    static let hairline = TextTone.onPhoto.opacity(0.45)
    /// Under the words on a photo: dark at the head and the foot.
    static let scrimHead = Color.black.opacity(0.38)
    static let scrimFoot = Color.black.opacity(0.5)
    /// A journal with no photo yet: a warm ground, light from the top left,
    /// a little deeper at the foot.
    static func ground(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(TextTone.rgb(0x402B1F)) : Color(TextTone.rgb(0xCC946B))
    }
    static func light(_ scheme: ColorScheme) -> Color {
        Color(TextTone.rgb(0xFFD199)).opacity(scheme == .dark ? 0.22 : 0.55)
    }
    static func deep(_ scheme: ColorScheme) -> Color {
        Color(TextTone.rgb(0x593324)).opacity(scheme == .dark ? 0.35 : 0.3)
    }
    /// How much of the palette's accent is laid over that ground.
    static func accentWash(_ scheme: ColorScheme) -> Double { scheme == .dark ? 0.22 : 0.18 }
    /// The card's shadow.
    static func shadow(_ scheme: ColorScheme) -> Color { .black.opacity(scheme == .dark ? 0.5 : 0.22) }

    // The room behind the cards (build 58): the cover photo, blurred and
    // laid under everything, or a glow of the journal's own warm colour.

    /// How far the photo is blurred.
    static let backdropBlur: CGFloat = 60
    /// What's laid over the blurred photo: at night black, leaving it at
    /// about 35% of its brightness; by day the floor, so the room stays
    /// light and the words under the cards keep their dark ink.
    static func backdropVeil(_ scheme: ColorScheme, floor: Color) -> Color {
        scheme == .dark ? .black.opacity(0.65) : floor.opacity(0.6)
    }
    /// The two glows of a journal with no photo yet: top left, bottom right.
    static let glowNear = 0.30
    static let glowFar = 0.18
    /// A journal's own warm colour, the same every time for the same
    /// journal: a stable hash of its id (FNV-1a, never Swift's `hashValue`,
    /// which changes each launch), kept to reds, oranges and ambers.
    static func warmth(_ id: String) -> Color {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in id.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        let hue = 0.03 + Double(hash % 1000) / 1000 * 0.09
        let saturation = 0.5 + Double((hash >> 16) % 100) / 100 * 0.18
        let brightness = 0.78 + Double((hash >> 32) % 100) / 100 * 0.12
        return Color(hue: hue, saturation: saturation, brightness: brightness)
    }
}

/// Paint the atmosphere's floor behind a scrolling surface: flat, no grain
/// (Quiet Warmth, build 44; from build 20 every page was grained paper).
/// Paper is now only what a person made by hand: a note, a letter, a
/// journal page.
struct AtmosphereWash: ViewModifier {
    @AppStorage("stanley.atmosphere") private var raw = "auto"
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background { Atmosphere.resolve(raw).palette.floor.ignoresSafeArea() }
    }
}

/// The three looks Settings offers, over the two things stored: whether
/// light or dark is forced (`stanley.appearance`) and the palette
/// (`stanley.atmosphere`). Light and Dark are the plain palette held to one
/// appearance; Rain is the rain palette in whichever the phone is in. With
/// none chosen Stanley matches the phone, which is the default.
enum Look: String, CaseIterable, Identifiable {
    case light, dark, rain
    var id: String { rawValue }

    var label: String {
        switch self {
        case .light: "Light"
        case .dark: "Dark"
        case .rain: "Rain"
        }
    }

    /// What's chosen, from what's stored; nil is matching the phone.
    static func current(appearance: String, atmosphere: String) -> Look? {
        if Atmosphere.resolve(atmosphere) == .rain { return .rain }
        switch appearance {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    /// What to store for a look, or for matching the phone (nil).
    static func stored(_ look: Look?) -> (appearance: String, atmosphere: String) {
        switch look {
        case .light: ("light", Atmosphere.plain.rawValue)
        case .dark: ("dark", Atmosphere.plain.rawValue)
        case .rain: ("system", Atmosphere.rain.rawValue)
        case nil: ("system", Atmosphere.plain.rawValue)
        }
    }
}

/// A field's or a tile's fill inside a form: the card color with the
/// card's hairline.
struct CardSurface: ViewModifier {
    @AppStorage("stanley.atmosphere") private var raw = "auto"
    let corner: CGFloat
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        let palette = Atmosphere.resolve(raw).palette
        content.background {
            shape.fill(palette.row).overlay(shape.strokeBorder(palette.edge, lineWidth: 0.5))
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
