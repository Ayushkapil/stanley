import SwiftUI

/// A tap on the tab you're already on (build 22): the page scrolls back to
/// its top, and at the top already it refreshes, as a pull would. Today,
/// Held, You and World; Settings has nowhere to go. `AppState` holds one,
/// `HomeView` counts the taps, and each page watches its own count.
@MainActor
@Observable
final class TabTaps {
    enum Page { case today, held, you, world }

    private(set) var today = 0
    private(set) var held = 0
    private(set) var you = 0
    private(set) var world = 0

    func tap(_ page: Page) {
        switch page {
        case .today: today += 1
        case .held: held += 1
        case .you: you += 1
        case .world: world += 1
        }
    }
}

extension View {
    /// On a tap of this page's tab (`taps` bumped), scroll to the view with
    /// id `top`; already there, run `refresh`, the pull's own work. Goes on
    /// the scroll view itself, which is where its top is read from.
    func onTabTap(
        _ taps: Int, scroll proxy: ScrollViewProxy, to top: String,
        orRefresh refresh: @escaping () async -> Void
    ) -> some View {
        modifier(TabTapToTop(taps: taps, proxy: proxy, top: top, refresh: refresh))
    }
}

private struct TabTapToTop: ViewModifier {
    let taps: Int
    let proxy: ScrollViewProxy
    let top: String
    let refresh: () async -> Void
    /// Whether the page is at its top. Known from iOS 18
    /// (`onScrollGeometryChange`); before that it's never known, so a tap
    /// only ever scrolls, which at the top does nothing.
    @State private var atTop: Bool?

    func body(content: Content) -> some View {
        tracked(content)
            .onChange(of: taps) { _, _ in
                if atTop == true {
                    // The same refresh as a pull, felt the same.
                    Haptics.refreshed()
                    Task { await refresh() }
                } else {
                    withAnimation(.easeInOut(duration: 0.45)) {
                        proxy.scrollTo(top, anchor: .top)
                    }
                }
            }
    }

    @ViewBuilder
    private func tracked(_ content: Content) -> some View {
        if #available(iOS 18, *) {
            content.onScrollGeometryChange(for: Bool.self) { geometry in
                // Zero at rest, however the page is inset under the clock.
                geometry.contentOffset.y + geometry.contentInsets.top <= 2
            } action: { _, now in
                atTop = now
            }
        } else {
            content
        }
    }
}
