import SwiftUI

/// Stanley on two displays.
///
/// The iPhone Duo's outer screen is a glance; its inner screen is something you
/// sit with. The horizontal size class is the signal — compact on the outer
/// display (and on every ordinary iPhone), regular on the inner one (and on
/// iPad) — so one rule covers hardware this project cannot test against.
///
/// Only density changes. Every feature exists on both surfaces: nothing is
/// hidden on the outer display and nothing is exclusive to the inner one.
enum Density {
    /// Compact: the outer display. Tight, scannable, no wasted space.
    case glance
    /// Regular: the inner display. Room to breathe; a memory surface.
    case room

    init(_ sizeClass: UserInterfaceSizeClass?) {
        self = (sizeClass == .regular) ? .room : .glance
    }

    var isRoom: Bool { self == .room }

    // Today
    var feedSpacing: CGFloat { isRoom ? 34 : 20 }
    var feedPhotoHeight: CGFloat { isRoom ? 460 : 300 }
    var cardPadding: CGFloat { isRoom ? 18 : 12 }
    var cardCorner: CGFloat { isRoom ? 22 : 18 }

    // Shared moments: side by side, with width to spare on the inner display.
    var momentTile: CGFloat { isRoom ? 360 : 240 }

    // Weekly mosaic: more photo presence per card.
    var mosaicHeight: CGFloat { isRoom ? 620 : 460 }

    // Held: a memory wall rather than a column.
    var heldPhotoHeight: CGFloat { isRoom ? 440 : 300 }

    // You: more tiles per row where there is width for them.
    var keptColumns: Int { isRoom ? 5 : 3 }
    var threadColumns: Int { isRoom ? 6 : 4 }
}

extension View {
    /// Keeps content clear of a fold or any other hardware intrusion. The
    /// system reports the crease through safe-area insets, so the fix is to
    /// respect them rather than to guess at a hinge position.
    func foldSafe() -> some View {
        self.safeAreaPadding(.horizontal)
    }
}
