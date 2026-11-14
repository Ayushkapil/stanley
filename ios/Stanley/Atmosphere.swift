import SwiftUI
import UIKit

// The atmosphere's colors are in `Shared/AtmospherePalette.swift`, where the
// home screen widget reads them too (build 40). What follows is how the app
// lays them on its own screens.

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
