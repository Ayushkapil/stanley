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

