import CoreImage
#if canImport(UIKit)
import UIKit
#endif

/// The four capture filters, and none. Each one is meant to make the photo
/// better, not to turn it into a preset: a well-printed black and white, a
/// warm roll of film, the last hour of daylight, and a cleaner version of
/// what the camera saw. One tap picks one. There are no sliders and no
/// intensity, and the look is baked into the pixels before upload, so it
/// can't change after posting. The server keeps only the name.
///
/// The looks are plain CoreImage with no UIKit, so the same code can run in
/// a macOS harness against sample photos.
enum PhotoFilter: String, CaseIterable, Identifiable {
    case none, mono, grain, dusk, clean

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: "None"
        case .mono: "Mono"
        case .grain: "Grain"
        case .dusk: "Dusk"
        case .clean: "Clean"
        }
    }

    /// The name the server keeps with the photo, or nil for no filter.
    var serverName: String? { self == .none ? nil : rawValue }

    /// The look, applied to an upright image whose origin is zero. Every
    /// distance (grain, vignette, clarity) is taken from the image's own
    /// size, so a preview and the full-size upload get the same look.
    /// `context` is only used by Clean, which measures the photo first.
    func apply(to image: CIImage, context: CIContext) -> CIImage {
        let out: CIImage
        switch self {
        case .none: return image
        case .mono: out = Self.mono(image)
        case .grain: out = Self.grain(image)
        case .dusk: out = Self.dusk(image)
        case .clean: out = Self.clean(image, context: context)
        }
        return out.cropped(to: image.extent)
    }

    // MARK: the looks

    /// A black and white with a print's depth rather than a desaturated
    /// color photo's flatness: open shadows, held-back highlights, and the
    /// contrast put back in the midtones.
    private static func mono(_ image: CIImage) -> CIImage {
        image
            // Shape the tones while there's still color to read them from.
            .applyingFilter("CIHighlightShadowAdjust", parameters: [
                "inputShadowAmount": 0.35,
                "inputHighlightAmount": 0.75,
            ])
            .applyingFilter("CIPhotoEffectMono")
            // A gentle S: steeper through the middle, with the ends eased so
            // the opened shadows and the held highlights stay that way.
            .applyingFilter("CIToneCurve", parameters: [
                "inputPoint0": CIVector(x: 0, y: 0.01),
                "inputPoint1": CIVector(x: 0.25, y: 0.21),
                "inputPoint2": CIVector(x: 0.5, y: 0.51),
                "inputPoint3": CIVector(x: 0.75, y: 0.80),
                "inputPoint4": CIVector(x: 1, y: 0.97),
            ])
    }

    /// Warm film, Portra rather than a preset: a little less saturation,
    /// blacks that never reach black, an amber cast that sits mostly in the
    /// shadows, and fine grain.
    private static func grain(_ image: CIImage) -> CIImage {
        let film = image
            .applyingFilter("CIColorControls", parameters: [
                kCIInputSaturationKey: 0.85,
                kCIInputContrastKey: 1,
                kCIInputBrightnessKey: 0,
            ])
            // Lifted blacks and a soft shoulder.
            .applyingFilter("CIToneCurve", parameters: [
                "inputPoint0": CIVector(x: 0, y: 0.07),
                "inputPoint1": CIVector(x: 0.25, y: 0.28),
                "inputPoint2": CIVector(x: 0.5, y: 0.52),
                "inputPoint3": CIVector(x: 0.75, y: 0.76),
                "inputPoint4": CIVector(x: 1, y: 0.97),
            ])
        return perceptual(film) { encoded in
            // A small constant warm offset. It hardly moves a highlight, so
            // the amber shows where the blacks were lifted.
            let warm = encoded.applyingFilter("CIColorMatrix", parameters: [
                "inputBiasVector": CIVector(x: 0.018, y: 0.006, z: -0.012, w: 0),
            ])
            return overlayGrain(on: warm)
        }
    }

    /// The last hour of daylight: warmer, a little deeper in the shadows,
    /// and a soft fall-off toward the edges.
    private static func dusk(_ image: CIImage) -> CIImage {
        let warm = image
            .applyingFilter("CITemperatureAndTint", parameters: [
                "inputNeutral": CIVector(x: 6500, y: 0),
                "inputTargetNeutral": CIVector(x: 5600, y: 0),
            ])
            // Deeper shadows only. Golden hour is luminous, so the
            // highlights are left where they were.
            .applyingFilter("CIHighlightShadowAdjust", parameters: [
                "inputShadowAmount": -0.1,
                "inputHighlightAmount": 1,
            ])
        return perceptual(warm) { vignette($0, strength: 0.12) }
    }

    /// "Make it look better": a gentle white balance, Apple's own auto
    /// enhance, a touch of clarity and a hair more contrast. No color of its
    /// own, only a clearer version of the same photo.
    private static func clean(_ image: CIImage, context: CIContext) -> CIImage {
        let edge = max(image.extent.width, image.extent.height)
        // Everything Clean decides, it decides from a 1080 copy: faster on a
        // 12-megapixel frame, and the preview and the upload are measured
        // from the same pixels, so they get the same settings.
        let probe = image.applyingFilter("CILanczosScaleTransform", parameters: [
            kCIInputScaleKey: min(1, 1080 / edge),
            kCIInputAspectRatioKey: 1,
        ])
        let balance = whiteBalance(of: probe, context: context)
        var out = image.applyingFilter("CIColorMatrix", parameters: balance)
        let balancedProbe = probe.applyingFilter("CIColorMatrix", parameters: balance)
        for filter in balancedProbe.autoAdjustmentFilters(options: [.redEye: false]) {
            filter.setValue(out, forKey: kCIInputImageKey)
            if let next = filter.outputImage { out = next }
        }
        return out
            .clampedToExtent()
            // Clarity: local contrast at a radius that scales with the photo.
            .applyingFilter("CIUnsharpMask", parameters: [
                kCIInputRadiusKey: edge / 300,
                kCIInputIntensityKey: 0.2,
            ])
            .applyingFilter("CISharpenLuminance", parameters: [
                kCIInputSharpnessKey: 0.25,
                kCIInputRadiusKey: max(1, edge / 1600),
            ])
            .cropped(to: image.extent)
            .applyingFilter("CIColorControls", parameters: [
                kCIInputSaturationKey: 1,
                kCIInputContrastKey: 1.03,
                kCIInputBrightnessKey: 0.005,
            ])
    }

    // MARK: pieces

    /// CoreImage works in linear light, where a constant offset or a blend
    /// centered on gray lands far harder in the shadows than it looks. Grain,
    /// warm casts and vignettes are judged by eye, so they're done on
    /// gamma-encoded values, the way a photo editor would.
    private static func perceptual(_ image: CIImage, _ body: (CIImage) -> CIImage) -> CIImage {
        body(image.applyingFilter("CILinearToSRGBToneCurve"))
            .applyingFilter("CISRGBToneCurveToLinear")
    }

    /// Fine, even grain laid over the photo with soft light, so it shows in
    /// the midtones and leaves the extremes alone. The grain is sized from
    /// the photo's long edge: Today shows photos 1080 pixels long, so a
    /// full-size upload and a 1080 preview end up with the same grain once
    /// the server scales the upload down.
    private static func overlayGrain(on image: CIImage) -> CIImage {
        let edge = max(image.extent.width, image.extent.height)
        let cell = edge / 720
        let amplitude: CGFloat = 0.22
        let noise = CIFilter(name: "CIRandomGenerator")!.outputImage!
            .transformed(by: CGAffineTransform(scaleX: cell, y: cell))
            // The generator's alpha is random too, and every filter divides
            // color by alpha first, so a near-transparent pixel comes out
            // thousands of times too bright: white specks, not grain. Make
            // it opaque before anything reads it.
            .settingAlphaOne(in: image.extent)
            // Gray noise centered on 0.5, which soft light leaves alone.
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0, y: amplitude, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: amplitude, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: amplitude, z: 0, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputBiasVector": CIVector(
                    x: 0.5 - amplitude / 2, y: 0.5 - amplitude / 2, z: 0.5 - amplitude / 2, w: 1
                ),
            ])
            .cropped(to: image.extent)
        return noise.applyingFilter("CISoftLightBlendMode", parameters: [
            kCIInputBackgroundImageKey: image,
        ])
    }

    /// Darkens toward the corners by at most `strength`, starting well
    /// outside the middle, measured from the photo's own size.
    private static func vignette(_ image: CIImage, strength: CGFloat) -> CIImage {
        let extent = image.extent
        let reach = hypot(extent.width, extent.height) / 2
        let shade = CIFilter(name: "CIRadialGradient", parameters: [
            "inputCenter": CIVector(x: extent.midX, y: extent.midY),
            "inputRadius0": reach * 0.45,
            "inputRadius1": reach * 1.05,
            "inputColor0": CIColor(red: 1, green: 1, blue: 1),
            "inputColor1": CIColor(red: 1 - strength, green: 1 - strength, blue: 1 - strength),
        ])!.outputImage!.cropped(to: extent)
        return shade.applyingFilter("CIMultiplyCompositing", parameters: [
            kCIInputBackgroundImageKey: image,
        ])
    }

    /// A gray-world white balance, held back on purpose: it corrects a third
    /// of the photo's overall cast and never moves a channel more than 4%.
    /// A sunset stays a sunset; a yellow kitchen bulb gets a little whiter.
    /// Returned as `CIColorMatrix` parameters, so it can be measured on one
    /// image and applied to another.
    private static func whiteBalance(of image: CIImage, context: CIContext) -> [String: Any] {
        let average = image.applyingFilter("CIAreaAverage", parameters: [
            kCIInputExtentKey: CIVector(cgRect: image.extent),
        ])
        var pixel = [Float](repeating: 0, count: 4)
        context.render(
            average,
            toBitmap: &pixel,
            rowBytes: 16,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBAf,
            colorSpace: nil
        )
        let (r, g, b) = (CGFloat(pixel[0]), CGFloat(pixel[1]), CGFloat(pixel[2]))
        guard r > 0.01, g > 0.01, b > 0.01 else { return [:] }
        let gray = (r + g + b) / 3
        func gain(_ channel: CGFloat) -> CGFloat {
            let full = gray / channel
            return min(1.04, max(0.96, 1 + (full - 1) / 3))
        }
        return [
            "inputRVector": CIVector(x: gain(r), y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: gain(g), z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: gain(b), w: 0),
        ]
    }
}

#if canImport(UIKit)
/// Puts a captured photo through a filter, for the preview and for upload.
/// Call it off the main thread: a full-size render is real work.
enum FilterRenderer {
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

    static func image(_ source: CIImage, _ filter: PhotoFilter) -> UIImage? {
        let out = filter.apply(to: source, context: context)
        guard let cg = context.createCGImage(
            out, from: source.extent, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)
        ) else { return nil }
        return UIImage(cgImage: cg)
    }

    static func jpeg(_ source: CIImage, _ filter: PhotoFilter, quality: CGFloat = 0.9) -> Data? {
        context.jpegRepresentation(
            of: filter.apply(to: source, context: context),
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
