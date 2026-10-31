import CoreLocation
import ImageIO
import PhotosUI
import SwiftUI

/// A photo chosen from the library, read the way Stanley needs it: upright,
/// no larger than it has to be, and with where it was taken, if the photo
/// says.
///
/// Read through ImageIO's thumbnail path, which decodes straight to the size
/// asked for and bakes in the orientation, so a 48-megapixel photo never sits
/// in memory at full size and the pixels are already the right way up.
///
/// Its metadata stays on the phone. What Stanley sends is encoded again from
/// these pixels, so a library photo's GPS never leaves the phone (the server
/// strips GPS from anything that reaches it, too). The location is read here
/// only to offer the place's name, and the person can change or clear it.
struct LibraryPhoto {
    let image: UIImage
    /// Where the photo was taken, from its own metadata.
    let location: CLLocation?

    /// The chosen photo, at most `longestSide` pixels on its longest side,
    /// or nil if it couldn't be read.
    static func load(_ item: PhotosPickerItem, longestSide: Int) async -> LibraryPhoto? {
        guard let data = try? await item.loadTransferable(type: Data.self) else { return nil }
        return await Task.detached(priority: .userInitiated) {
            read(data, longestSide: longestSide)
        }.value
    }

    static func read(_ data: Data, longestSide: Int) -> LibraryPhoto? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: longestSide,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let pixels = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let gps = properties?[kCGImagePropertyGPSDictionary] as? [CFString: Any]
        return LibraryPhoto(image: UIImage(cgImage: pixels), location: location(gps))
    }

    private static func location(_ gps: [CFString: Any]?) -> CLLocation? {
        guard let gps,
              var latitude = gps[kCGImagePropertyGPSLatitude] as? Double,
              var longitude = gps[kCGImagePropertyGPSLongitude] as? Double
        else { return nil }
        if (gps[kCGImagePropertyGPSLatitudeRef] as? String) == "S" { latitude = -latitude }
        if (gps[kCGImagePropertyGPSLongitudeRef] as? String) == "W" { longitude = -longitude }
        return CLLocation(latitude: latitude, longitude: longitude)
    }
}
