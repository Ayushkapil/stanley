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
    /// The photo is the moment, so it takes roughly two thirds of the screen in
    /// every card. The remaining third is the story — face, name, time, caption,
    /// place, first comment, gestures — deliberately secondary to the image.
    /// Expressed as a share of the screen rather than in points, so the ratio
    /// holds on both displays and only the scale changes.
    static let photoShare: CGFloat = 0.67
    static let cardGapShare: CGFloat = 0.05

    private var screenHeight: CGFloat { UIScreen.main.bounds.height }
    var feedSpacing: CGFloat { (screenHeight * Density.cardGapShare).rounded() }
    var feedPhotoHeight: CGFloat { (screenHeight * Density.photoShare).rounded() }
    var cardPadding: CGFloat { isRoom ? 20 : 12 }
    var cardCorner: CGFloat { isRoom ? 22 : 18 }
    /// The first story gets room to be read before it truncates.
    var storyLineLimit: Int { isRoom ? 3 : 1 }

    // --- Shared moments ------------------------------------------------------
    /// Inner: a pair at meaningful size, with a sliver of the third so it is
    /// obvious there is more. Outer: the scroll strip, slightly narrower.
    func momentTileWidth(container: CGFloat) -> CGFloat {
        isRoom ? (container - 30) / 2.25 : min(container * 0.62, 220)
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
    /// Room for more faces before the cluster overflows.
    var circleFacesShown: Int { isRoom ? 10 : 5 }
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

/// True on a canvas big enough to be the Duo's inner display (or an iPad).
/// Used only for enhancements that want real estate — never to gate a feature,
/// and never as the primary signal. The size class decides layout.
@MainActor
func isLargeCanvas() -> Bool {
    let bounds = UIScreen.main.bounds
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

    /// Keeps interactive content off the crease. Photos may span the fold —
    /// a picture crossing it is fine — but tap targets should not straddle it.
    func creaseSafe(_ density: Density) -> some View {
        padding(.horizontal, density.creaseBuffer)
    }

    /// Fold and unfold mid-session: reflow, never reload.
    func foldAnimated(_ sizeClass: UserInterfaceSizeClass?) -> some View {
        animation(.default, value: sizeClass)
    }
}
