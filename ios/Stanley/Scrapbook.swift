import SwiftUI

/// An entry with more than one photo, laid out like prints put into a
/// scrapbook: different sizes, each leaning a few degrees, edges overlapping,
/// the later ones on top. Never a grid or a row of equal cells, and never a
/// number: nothing here says how many there are.
///
/// Where each lies is decided by the entry's own ids (`Placement`), so it is
/// the same on every draw and on every phone. Each print keeps `PhotoShape`.
/// What a print looks like inside (the photo, the fade, the tint) is the
/// caller's: `cell` draws one picture, clipped and printed.
struct Scrapbook<Cell: View>: View {
    let pictures: [PhotoImage]
    /// The entry's id, which decides which side the first photo sits on.
    let seed: String
    @ViewBuilder let cell: (PhotoImage) -> Cell

    /// The page is a little taller than one print is.
    static var pageAspect: CGFloat { PhotoShape.aspect / 1.1 }

    var body: some View {
        let shown = Array(pictures.prefix(3))
        let flip = Placement.hash(seed) % 2 == 1
        Color.clear
            .aspectRatio(Self.pageAspect, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay {
                GeometryReader { page in
                    ZStack {
                        ForEach(Array(shown.enumerated()), id: \.element.id) { index, picture in
                            let spot = Placement.spot(index, of: shown.count, flip: flip, id: picture.id)
                            let width = page.size.width * spot.width
                            cell(picture)
                                .frame(width: width, height: width / PhotoShape.aspect)
                                .rotationEffect(.degrees(spot.degrees))
                                .shadow(color: .black.opacity(0.14), radius: 5, y: 2)
                                .position(
                                    x: page.size.width * spot.x,
                                    y: page.size.height * spot.y
                                )
                                .zIndex(Double(index))
                        }
                    }
                    .frame(width: page.size.width, height: page.size.height)
                }
            }
    }
}

/// Where one print lies on the page: its width as a share of the page's,
/// its centre as a share of the page's width and height, and its lean.
enum Placement {
    struct Spot { let width: CGFloat; let x: CGFloat; let y: CGFloat; let degrees: Double }

    static func hash(_ s: String) -> UInt32 {
        s.unicodeScalars.reduce(UInt32(11)) { $0 &* 31 &+ $1.value }
    }

    /// The first print is the largest, to one side; the second overlaps its
    /// lower corner; the third is tucked in at the other edge. A degree or
    /// so of jitter from the picture's own id, so no two entries lean alike.
    static func spot(_ index: Int, of count: Int, flip: Bool, id: String) -> Spot {
        let base: (w: CGFloat, x: CGFloat, y: CGFloat, deg: Double)
        switch (count, index) {
        case (2, 0): base = (0.72, 0.41, 0.40, -3)
        case (2, _): base = (0.50, 0.72, 0.76, 4)
        case (_, 0): base = (0.66, 0.37, 0.36, -3)
        case (_, 1): base = (0.50, 0.73, 0.72, 4)
        default: base = (0.44, 0.27, 0.77, -5)
        }
        let jitter = (Double(hash(id) % 11) - 5) / 5   // -1...1 degree
        let degrees = (base.deg + jitter) * (flip ? -1 : 1)
        return Spot(width: base.w, x: flip ? 1 - base.x : base.x, y: base.y, degrees: degrees)
    }
}

extension View {
    /// A single photo sits in its print; a scrapbook's prints are each their
    /// own, so the page as a whole has no frame.
    @ViewBuilder
    func printed(_ photo: Photo) -> some View {
        if photo.pictures.count > 1 { self } else { asPrint() }
    }
}
