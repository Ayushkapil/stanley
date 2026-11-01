import SwiftUI

/// Where a photo sits in a window it fills: how far it's zoomed past just
/// covering the window, and how far its middle is moved from the window's.
/// One piece of arithmetic for every crop in Stanley, so the profile photo's
/// square and today's photo's `PhotoShape` frame cut the same way.
///
/// The photo always covers the window: it can't be zoomed out past filling
/// it or dragged off an edge, so a crop never has an empty corner. A crop is
/// cut from the photo's own pixels, never by rendering the screen again.
struct Framing: Equatable {
    var zoom: CGFloat = 1
    var offset: CGSize = .zero

    static let maxZoom: CGFloat = 5

    /// The photo's size on screen at zoom 1: just big enough to cover the
    /// window. Only the photo's shape matters, so any size of it will do.
    static func covering(_ photo: CGSize, _ window: CGSize) -> CGSize {
        let scale = max(window.width / max(1, photo.width), window.height / max(1, photo.height))
        return CGSize(width: photo.width * scale, height: photo.height * scale)
    }

    /// Whether there's anything to move: a photo of another shape than the
    /// window, or one zoomed in.
    func canMove(_ photo: CGSize, _ window: CGSize) -> Bool {
        let filled = Self.covering(photo, window)
        return filled.width * zoom > window.width + 0.5 || filled.height * zoom > window.height + 0.5
    }

    /// The same framing, kept over every part of the window.
    func clamped(_ photo: CGSize, _ window: CGSize) -> Framing {
        let filled = Self.covering(photo, window)
        let x = max(0, (filled.width * zoom - window.width) / 2)
        let y = max(0, (filled.height * zoom - window.height) / 2)
        return Framing(
            zoom: zoom,
            offset: CGSize(width: min(max(offset.width, -x), x), height: min(max(offset.height, -y), y))
        )
    }

    /// The window, in the photo's own pixels (top-left origin). `pixels` is
    /// the photo's full size, upright.
    func crop(pixels: CGSize, window: CGSize) -> CGRect {
        // Points on screen per pixel of the photo.
        let k = max(window.width / pixels.width, window.height / pixels.height) * zoom
        let width = window.width / k, height = window.height / k
        return CGRect(
            x: pixels.width / 2 - offset.width / k - width / 2,
            y: pixels.height / 2 - offset.height / k - height / 2,
            width: width, height: height
        )
        .integral
        .intersection(CGRect(origin: .zero, size: pixels))
    }

    /// Whether the window takes the whole photo, so there's nothing to cut:
    /// a camera shot, already the window's shape, left as it came.
    func isWhole(pixels: CGSize, window: CGSize) -> Bool {
        let cut = crop(pixels: pixels, window: window)
        return cut.width >= pixels.width - 2 && cut.height >= pixels.height - 2
    }
}

extension View {
    /// Drag to move and pinch to zoom a photo inside its window, both at
    /// once. `moving` is true while a finger is on it, for a guide to show.
    func framing(
        _ framing: Binding<Framing>, photo: CGSize, window: CGSize, moving: Binding<Bool> = .constant(false)
    ) -> some View {
        modifier(FramingGestures(framing: framing, photo: photo, window: window, moving: moving))
    }
}

private struct FramingGestures: ViewModifier {
    @Binding var framing: Framing
    let photo: CGSize
    let window: CGSize
    @Binding var moving: Bool
    /// The zoom when the current pinch began.
    @State private var pinchStart: CGFloat?
    /// How far the current drag had gone at its last step.
    @State private var dragged: CGSize = .zero

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .gesture(pinch)
            // Only when there's somewhere to move it. A photo that already
            // is the window's shape leaves a drag to whatever it sits in, so
            // the capture sheet still scrolls from it.
            .simultaneousGesture(drag, including: framing.canMove(photo, window) ? .all : .subviews)
    }

    private var pinch: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let start = pinchStart ?? framing.zoom
                pinchStart = start
                moving = true
                let next = min(max(start * value.magnification, 1), Framing.maxZoom)
                // Scale the offset with the photo, so what's in the middle of
                // the window stays in the middle.
                let ratio = next / framing.zoom
                framing = Framing(
                    zoom: next,
                    offset: CGSize(width: framing.offset.width * ratio, height: framing.offset.height * ratio)
                ).clamped(photo, window)
            }
            .onEnded { _ in
                pinchStart = nil
                moving = false
            }
    }

    /// Moves by each step of the drag rather than its total, so a drag and a
    /// pinch at the same time both move the same photo.
    private var drag: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                moving = true
                let step = CGSize(
                    width: value.translation.width - dragged.width,
                    height: value.translation.height - dragged.height
                )
                dragged = value.translation
                framing = Framing(
                    zoom: framing.zoom,
                    offset: CGSize(width: framing.offset.width + step.width, height: framing.offset.height + step.height)
                ).clamped(photo, window)
            }
            .onEnded { _ in
                dragged = .zero
                moving = false
            }
    }
}

/// Thirds, while a photo is being moved: where to put the horizon.
struct ThirdsGuide: View {
    var body: some View {
        GeometryReader { geo in
            Path { path in
                for i in 1...2 {
                    let x = geo.size.width * CGFloat(i) / 3
                    let y = geo.size.height * CGFloat(i) / 3
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: geo.size.height))
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: geo.size.width, y: y))
                }
            }
            .stroke(.white.opacity(0.55), lineWidth: 0.5)
            .shadow(color: .black.opacity(0.3), radius: 1)
        }
        .allowsHitTesting(false)
    }
}
