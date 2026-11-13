import SwiftUI
import UIKit

// The atmosphere's colors are in `Shared/AtmospherePalette.swift`, where the
// home screen widget reads them too (build 40). What follows is how the app
// lays them on its own screens.

/// Paint the atmosphere's floor behind a scrolling surface, as paper: the
/// floor with the paper's grain over it (build 20), so every page of the
/// journal is the same stock as the morning paper's.
struct AtmosphereWash: ViewModifier {
    @AppStorage("stanley.atmosphere") private var raw = "auto"
    @Environment(\.colorScheme) private var colorScheme
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background {
                ZStack {
                    Atmosphere.resolve(raw).palette.floor
                    PaperGrainView(strength: 0.45)
                }
                .ignoresSafeArea()
            }
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
