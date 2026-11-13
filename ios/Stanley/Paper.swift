import SwiftUI
import UIKit

// The grain's tile is in `Shared/PaperGrain.swift`, drawn for the widget too.

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
