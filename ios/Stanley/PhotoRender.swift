import CoreImage
#if canImport(UIKit)
import UIKit
#endif

#if canImport(UIKit)
/// A captured photo on its way to being posted: upright, at preview size
/// for the frame on screen, and cut to that frame at full size for upload.
/// Call the renders off the main thread: a full-size one is real work.
///
/// Until build 44 this also laid one of four looks over the photo (Mono,
/// Grain, Dusk, Clean). The filters were removed; a photo is posted as it
/// was taken, cropped to its frame and nothing else.
enum PhotoRenderer {
    static let context = CIContext(options: [.cacheIntermediates: false])

    /// The long edge Today shows (the server's derivative), so the preview
    /// is the photo the circle will see.
    static let previewEdge: CGFloat = 1080

    /// A captured photo as CoreImage sees it: upright, origin at zero.
    static func upright(_ image: UIImage) -> CIImage? {
        guard let cg = image.cgImage else { return nil }
        let turned = CIImage(cgImage: cg).oriented(CGImagePropertyOrientation(image.imageOrientation))
        return turned.transformed(by: CGAffineTransform(
            translationX: -turned.extent.minX, y: -turned.extent.minY
        ))
    }

    /// The same photo at preview size.
    static func preview(of source: CIImage) -> CIImage {
        let scale = min(1, previewEdge / max(source.extent.width, source.extent.height))
        return source.applyingFilter("CILanczosScaleTransform", parameters: [
            kCIInputScaleKey: scale,
            kCIInputAspectRatioKey: 1,
        ])
    }

    static func image(_ source: CIImage) -> UIImage? {
        guard let cg = context.createCGImage(
            source, from: source.extent, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)
        ) else { return nil }
        return UIImage(cgImage: cg)
    }

    /// The full-size photo, cut to `crop` if there is one: a rectangle in
    /// the photo's pixels, top-left origin, as `Framing` gives it, so the
    /// cut is exactly what the preview showed in its frame.
    static func jpeg(_ source: CIImage, crop: CGRect? = nil, quality: CGFloat = 0.9) -> Data? {
        var out = source
        if let crop {
            // CoreImage counts from the bottom.
            let flipped = CGRect(
                x: source.extent.minX + crop.minX,
                y: source.extent.maxY - crop.maxY,
                width: crop.width, height: crop.height
            )
            out = out.cropped(to: flipped)
                .transformed(by: CGAffineTransform(translationX: -flipped.minX, y: -flipped.minY))
        }
        return context.jpegRepresentation(
            of: out,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
            options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: quality]
        )
    }
}

private extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
#endif
