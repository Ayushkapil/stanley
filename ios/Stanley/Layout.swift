import SwiftUI
import UIKit

/// Stanley across the iPhone Duo's two displays.
///
/// The primary signal is the horizontal size class: **compact** is the outer
/// display — and every ordinary iPhone, which is why those keep today's
/// behaviour exactly — while **regular** is the inner display (and iPad). A
/// second, narrower check (`isLargeCanvas`) gates only enhancements that need
/// genuine real estate.
///
/// What changes between them is density and spatial arrangement, never
/// capability: every feature exists on both surfaces, and nothing is gated.
enum Density {
    /// The outer display, and any standard iPhone. The daily glance: complete
    /// in itself, tight, nothing wasted.
    case glance
    /// The inner display. The memory surface — the photo is the hero.
    case room

    init(_ sizeClass: UserInterfaceSizeClass?) {
        self = (sizeClass == .regular) ? .room : .glance
    }

    var isRoom: Bool { self == .room }

    // --- Today ---------------------------------------------------------------
    /// Today is a journal, not a card feed (build 17): each photo is a print
    /// in `PhotoShape`, as wide as the page allows, with its words beneath.
    /// On the inner display the page is a readable column, so a print doesn't
    /// grow taller than the screen.
    var journalWidth: CGFloat? { isRoom ? 560 : nil }

    private var screenHeight: CGFloat { Density.canvasBounds().height }

    /// The bounds of the display Stanley is actually on.
    ///
    /// Deliberately not `UIScreen.main`: on a two-display foldable, "main" is
    /// the built-in primary, which is not necessarily the display showing this
    /// app, and its identity does not change when the app moves between them.
    /// The window scene knows which screen it is on. A single-screen device
    /// resolves to the very same bounds, so an ordinary iPhone sees no change
    /// at all — which is the point.
    static func canvasBounds() -> CGRect {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        return scene?.screen.bounds ?? UIScreen.main.bounds
    }
    /// The capture preview's height at most: a share of the screen, so the
    /// place and the looks beneath it are in view without scrolling, even on
    /// the Duo's cover. Its width follows from `PhotoShape`.
    var capturePhotoMaxHeight: CGFloat { (screenHeight * 0.55).rounded() }
    var cardPadding: CGFloat { isRoom ? 20 : 12 }
    var cardCorner: CGFloat { isRoom ? 22 : 18 }
    /// The first story gets room to be read before it truncates.
    var storyLineLimit: Int { isRoom ? 3 : 1 }

    // --- Shared moments ------------------------------------------------------
    /// Inner: a pair at meaningful size, with a sliver of the third so it is
    /// obvious there is more. Outer: the scroll strip, slightly narrower.
    func momentTileWidth(container: CGFloat) -> CGFloat {
        isRoom ? (container - 30) / 2.25 : min(container * 0.7, 270)
    }

    // --- Weekly mosaic -------------------------------------------------------
    var mosaicHeight: CGFloat { isRoom ? 640 : 440 }

    // --- Returned ------------------------------------------------------------
    /// Handed to you, not squeezed into a notification.
    var returnedPhotoHeight: CGFloat { isRoom ? 320 : 180 }

    // --- Held ----------------------------------------------------------------
    /// A magazine on the inner display: two columns of large cards.
    var heldColumns: Int { isRoom ? 2 : 1 }
    var heldPhotoHeight: CGFloat { isRoom ? 340 : 280 }

    // --- You -----------------------------------------------------------------
    /// Three columns on both; on the inner display the extra width makes the
    /// tiles themselves larger, which is the point.
    var keptColumns: Int { 3 }
    var threadColumns: Int { isRoom ? 5 : 4 }
    /// Name and words sit beside the avatar once there is width for it.
    var profileIsHorizontal: Bool { isRoom }

    // --- Settings ------------------------------------------------------------
    /// 7.6" is wide enough that a full-bleed form stops being readable.
    var readableWidth: CGFloat? { isRoom ? 600 : nil }

    // --- The fold ------------------------------------------------------------
    /// A conservative margin for interactive elements near the crease. iOS 26.5
    /// exposes no fold geometry, so this is a buffer, not a measurement — when
    /// the SDK reports the crease, this should read it instead.
    var creaseBuffer: CGFloat { isRoom ? 20 : 0 }
}

/// The spaces between things (the polish pass, build 28): one unit, 16pt,
/// with its half and its double, so every gap on a page is one of three and
/// looks chosen rather than left. The page's side margin stays 20.
enum Spacing {
    /// Inside one thing: a heading and what it heads, a line and the next.
    static let tight: CGFloat = 8
    /// Between one section of a page and the next: the masthead and the
    /// board, the board and the question, the question and the first day, a
    /// tucked-in card and what follows it, a day's mark and its first print,
    /// either side of the rule between two prints.
    static let section: CGFloat = 16
    /// Before a new chapter of a page: a new day in Today, a headed section
    /// on You or a friend's page in Held; and the room left above the tab
    /// bar at the foot of every page.
    static let chapter: CGFloat = 32
}

/// The one shape every photo in Today has (build 17): the camera's own 4:3,
/// held upright, so three wide by four tall. A photo of any other shape fills
/// it and is cropped, never letterboxed, and capture crops to it before
/// posting, so what's posted is what Today shows. Width over height.
enum PhotoShape {
    static let aspect: CGFloat = 3.0 / 4.0
    /// Rounded the same at every corner, wherever a photo sits on the page.
    static let corner: CGFloat = 14
}

/// True on a canvas big enough to be the Duo's inner display (or an iPad).
/// Used only for enhancements that want real estate — never to gate a feature,
/// and never as the primary signal. The size class decides layout.
@MainActor
func isLargeCanvas() -> Bool {
    let bounds = Density.canvasBounds()
    return min(bounds.width, bounds.height) >= 600
}

extension View {
    /// Hold content to a readable column on wide canvases; full width elsewhere.
    @ViewBuilder
    func readableWidth(_ density: Density) -> some View {
        if let width = density.readableWidth {
            frame(maxWidth: width).frame(maxWidth: .infinity)
        } else {
            self
        }
    }

    /// Breathing room at the edges for interactive rows on the inner display,
    /// and a no-op (0pt) everywhere else.
    ///
    /// Honest about its limits: the crease on a book-fold runs *vertically down
    /// the middle*, so an outer inset cannot clear it. Nothing can, for a
    /// control that is full-width or centred — a text field or a primary button
    /// spans the centre by construction, the way a photo does. What this buys
    /// is that a wide row is not pressed into the curvature at either edge, and
    /// that rows of two controls keep their gap over the fold rather than a
    /// tap target. When the SDK finally reports fold geometry, this is where
    /// the real measurement goes.
    func creaseSafe(_ density: Density) -> some View {
        padding(.horizontal, density.creaseBuffer)
    }

    /// A row that scrolls sideways and draws past its own edges (a note's
    /// tape and shadow, a face's ring), but no further sideways than the
    /// page's margin. On an ordinary iPhone the margin ends at the screen's
    /// edge, so nothing changes. On the Duo's cover the tab bar is a dock
    /// down the trailing side, which the page clears but an unclipped row
    /// ran on under (build 44).
    func bleedsToMargin(_ margin: CGFloat = 20) -> some View {
        scrollClipDisabled()
            .mask {
                Rectangle()
                    .padding(.horizontal, -margin)
                    .padding(.vertical, -200)
            }
    }

    /// Fold and unfold mid-session: reflow, never reload.
    func foldAnimated(_ sizeClass: UserInterfaceSizeClass?) -> some View {
        animation(.default, value: sizeClass)
    }
}
